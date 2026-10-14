//
//  JarvisListener.swift
//  Jarvis
//
//  Push-to-talk: records the microphone at 16 kHz mono until the owner stops talking (or presses
//  the key again), then asks Hermes to transcribe it (POST /api/audio/transcribe, the speech-to-text
//  provider set in ~/.hermes/config.yaml). Nothing is recorded until the key is pressed.
//

import AVFoundation
import Foundation
import os.log

/// Decides when a recording is finished. Pure, so the timing is unit-tested.
struct JarvisSilenceGate {
  /// Above this RMS (0…1) counts as speech.
  var speechLevel: Float = 0.02
  /// Quiet this long after speech ends the recording.
  var trailingSilence: TimeInterval = 1.2
  /// Nobody spoke this long after the key: give up.
  var noSpeechTimeout: TimeInterval = 6
  var maxLength: TimeInterval = 45

  private(set) var heardSpeech = false
  private var elapsed: TimeInterval = 0
  private var quiet: TimeInterval = 0

  enum Verdict: Equatable {
    case keepListening
    case done
    case nothingSaid
  }

  mutating func feed(rms: Float, duration: TimeInterval) -> Verdict {
    elapsed += duration
    if rms >= speechLevel {
      heardSpeech = true
      quiet = 0
    } else {
      quiet += duration
    }
    if elapsed >= maxLength { return heardSpeech ? .done : .nothingSaid }
    if heardSpeech { return quiet >= trailingSilence ? .done : .keepListening }
    return elapsed >= noSpeechTimeout ? .nothingSaid : .keepListening
  }
}

/// 16-bit PCM mono samples wrapped in a WAV header.
enum JarvisWAV {
  static func encode(_ samples: [Int16], sampleRate: Int = 16000) -> Data {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let byteCount = samples.count * 2
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + byteCount))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))  // PCM
    append(UInt16(1))  // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(byteCount))
    for sample in samples { append(sample) }
    return data
  }
}

@MainActor
final class JarvisListener: ObservableObject {
  static let shared = JarvisListener()

  enum State: Equatable {
    case idle
    case listening
    case transcribing
  }

  @Published private(set) var state: State = .idle
  /// Live input level 0…1 for a meter.
  @Published private(set) var level: Float = 0

  private let logger = Logger(subsystem: "local.dayframe.app", category: "jarvis")
  private let engine = AVAudioEngine()
  private var samples: [Int16] = []
  private var gate = JarvisSilenceGate()
  private var onTranscript: ((String) -> Void)?

  /// Starts listening, or finishes early when already listening.
  func toggle(onTranscript: @escaping (String) -> Void) {
    switch state {
    case .idle: start(onTranscript: onTranscript)
    case .listening: finish(send: true)
    case .transcribing: break
    }
  }

  func cancel() { finish(send: false) }

  private func start(onTranscript: @escaping (String) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        Task { @MainActor in if granted { self.start(onTranscript: onTranscript) } }
      }
      return
    case .denied, .restricted:
      logger.error("Microphone access is off for Jarvis (System Settings › Privacy › Microphone)")
      return
    default: break
    }
    self.onTranscript = onTranscript
    samples.removeAll()
    gate = JarvisSilenceGate()
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard
      let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
      let converter = AVAudioConverter(from: inputFormat, to: target)
    else {
      logger.error("Jarvis couldn't set up the microphone converter")
      return
    }
    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      let ratio = 16000 / inputFormat.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
      guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
      var fed = false
      converter.convert(to: out, error: nil) { _, status in
        if fed {
          status.pointee = .noDataNow
          return nil
        }
        fed = true
        status.pointee = .haveData
        return buffer
      }
      guard let channel = out.int16ChannelData?[0] else { return }
      let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
      let rms = Self.rms(chunk)
      let duration = Double(chunk.count) / 16000
      Task { @MainActor in self?.receive(chunk, rms: rms, duration: duration) }
    }
    do {
      try engine.start()
      state = .listening
      logger.info("Jarvis is listening")
    } catch {
      input.removeTap(onBus: 0)
      logger.error(
        "Jarvis couldn't start the microphone: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func receive(_ chunk: [Int16], rms: Float, duration: TimeInterval) {
    guard state == .listening else { return }
    samples += chunk
    level = min(1, rms * 8)
    switch gate.feed(rms: rms, duration: duration) {
    case .keepListening: break
    case .done: finish(send: true)
    case .nothingSaid:
      logger.info("Jarvis heard nothing; stopped listening")
      finish(send: false)
    }
  }

  private func finish(send: Bool) {
    guard state == .listening else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    level = 0
    let recorded = samples
    samples.removeAll()
    guard send, !recorded.isEmpty, let onTranscript else {
      state = .idle
      return
    }
    state = .transcribing
    Task {
      let text = await transcribe(JarvisWAV.encode(recorded))
      state = .idle
      if let text, !text.isEmpty { onTranscript(text) }
    }
  }

  private func transcribe(_ wav: Data) async -> String? {
    guard let base = HermesBackend.shared.baseURL else {
      logger.error("Jarvis can't transcribe: Hermes isn't running")
      return nil
    }
    var request = URLRequest(url: base.appendingPathComponent("api/audio/transcribe"))
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HermesBackend.shared.token, forHTTPHeaderField: "X-Hermes-Session-Token")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "data_url": "data:audio/wav;base64," + wav.base64EncodedString(), "mime_type": "audio/wav",
    ])
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      guard status == 200, let transcript = body?["transcript"] as? String else {
        logger.error(
          "Transcription failed (HTTP \(status)): \(String(decoding: data.prefix(300), as: UTF8.self), privacy: .public)"
        )
        return nil
      }
      logger.info("Jarvis heard \(transcript.count) characters")
      return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  nonisolated private static func rms(_ chunk: [Int16]) -> Float {
    guard !chunk.isEmpty else { return 0 }
    var sum: Float = 0
    for sample in chunk {
      let value = Float(sample) / 32768
      sum += value * value
    }
    return (sum / Float(chunk.count)).squareRoot()
  }
}
