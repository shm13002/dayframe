//
//  JarvisVoice.swift
//  Jarvis
//
//  Jarvis speaks with the owner's cloned Jarvis voice: the local OmniVoice server in
//  ~/jarvis-voice (LaunchAgent local.jarvis.tts, http://127.0.0.1:5055).
//    POST /tts {"text": ≤400 chars, "voice": "jarvis", "steps": 32}
//    Authorization: Bearer <~/jarvis-voice/service.token>; requests with an Origin header are refused
//    200 WAV (X-Jarvis-Verified: true) · 401 bad token · 429 busy (one at a time)
//    422 failed its own intelligibility check three times · 503 generation failed
//  Long answers go one sentence-sized piece at a time; the next piece is generated while the
//  current one plays. If the server is down, the system voice speaks instead.
//

import AVFoundation
import Foundation
import os.log

/// Turns an answer into speakable pieces of at most 400 characters. Pure, unit-tested.
enum JarvisSpeechText {
  static let maxPiece = 400

  static func pieces(_ text: String) -> [String] {
    let clean = speakable(text)
    guard !clean.isEmpty else { return [] }
    var pieces: [String] = []
    var current = ""
    for sentence in sentences(clean) {
      for part in hardSplit(sentence) {
        if current.isEmpty {
          current = part
        } else if current.count + 1 + part.count <= 160 {
          // Short sentences ride together: fewer round trips, steadier rhythm.
          current += " " + part
        } else {
          pieces.append(current)
          current = part
        }
      }
    }
    if !current.isEmpty { pieces.append(current) }
    return pieces
  }

  /// Removes what reads badly aloud: code blocks, markdown marks, link targets, bare URLs.
  static func speakable(_ text: String) -> String {
    var s = text
    s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(
      of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
    s = s.replacingOccurrences(of: "https?://\\S+", with: "a link", options: .regularExpression)
    s = s.replacingOccurrences(of: "[*_`#>|]+", with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: "(?m)^\\s*[-•]\\s+", with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func sentences(_ text: String) -> [String] {
    var result: [String] = []
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
      if let sentence = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
        result.append(sentence)
      }
    }
    return result.isEmpty ? [text] : result
  }

  /// A sentence longer than the limit breaks at the last comma or space before it.
  private static func hardSplit(_ sentence: String) -> [String] {
    var rest = Substring(sentence)
    var parts: [String] = []
    while rest.count > maxPiece {
      let window = rest.prefix(maxPiece)
      let cut =
        window.lastIndex(where: { $0 == "," || $0 == ";" }).map { rest.index(after: $0) }
        ?? window.lastIndex(of: " ") ?? window.endIndex
      parts.append(rest[..<cut].trimmingCharacters(in: .whitespaces))
      rest = rest[cut...].drop(while: { $0 == " " })
    }
    if !rest.isEmpty { parts.append(String(rest)) }
    return parts.filter { !$0.isEmpty }
  }
}

/// One request to the voice server. `send` is injectable so tests run without the server.
struct JarvisVoiceClient {
  enum Failure: Error, Equatable {
    case noToken
    case unreachable
    case unauthorized
    case busy
    case unverified
    case failed(Int)
  }

  typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)

  var endpoint = URL(string: "http://127.0.0.1:5055/tts")!
  var token: () -> String? = JarvisVoiceClient.readToken
  var send: Send = JarvisVoiceClient.urlSessionSend
  /// How often a busy server (429) is asked again, half a second apart.
  var busyRetries = 20

  func wav(for text: String) async throws -> Data {
    guard let token = token() else { throw Failure.noToken }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(
      withJSONObject: [
        "text": String(text.prefix(JarvisSpeechText.maxPiece)), "voice": "jarvis", "steps": 32,
      ])
    var attempt = 0
    while true {
      let data: Data
      let response: HTTPURLResponse
      do {
        (data, response) = try await send(request)
      } catch {
        throw Failure.unreachable
      }
      switch response.statusCode {
      case 200: return data
      case 401: throw Failure.unauthorized
      case 422: throw Failure.unverified
      case 429:
        attempt += 1
        guard attempt <= busyRetries else { throw Failure.busy }
        try await Task.sleep(for: .milliseconds(500))
      default: throw Failure.failed(response.statusCode)
      }
    }
  }

  static let tokenPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("jarvis-voice/service.token")

  static func readToken() -> String? {
    guard let raw = try? String(contentsOf: tokenPath, encoding: .utf8) else { return nil }
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return token.count >= 32 ? token : nil
  }

  /// URLSession never adds an Origin header, which the server requires.
  static func urlSessionSend(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (data, http)
  }
}

@MainActor
final class JarvisVoice: NSObject, ObservableObject, AVAudioPlayerDelegate {
  static let shared = JarvisVoice()

  enum Keys {
    static let enabled = "dayframeJarvisVoiceEnabled"
  }

  enum Source: Equatable {
    case jarvisVoice
    case systemVoice
  }

  @Published private(set) var isSpeaking = false
  /// Which voice spoke last, for Settings › Jarvis.
  @Published private(set) var lastSource: Source?

  var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.enabled)
      if !newValue { stop() }
    }
  }

  var client = JarvisVoiceClient()
  private let logger = Logger(subsystem: "local.dayframe.app", category: "jarvis")
  private var queue: [String] = []
  private var pipeline: Task<Void, Never>?
  private var player: AVAudioPlayer?
  private var playbackDone: CheckedContinuation<Void, Never>?
  private let synthesizer = AVSpeechSynthesizer()

  /// Speaks the text after anything already queued.
  func speak(_ text: String) {
    guard isEnabled else { return }
    queue += JarvisSpeechText.pieces(text)
    guard pipeline == nil, !queue.isEmpty else { return }
    pipeline = Task { await run() }
  }

  /// Stops now and forgets the rest (the owner interrupted, or a new answer started).
  func stop() {
    queue.removeAll()
    pipeline?.cancel()
    pipeline = nil
    player?.stop()
    player = nil
    synthesizer.stopSpeaking(at: .immediate)
    finishPlayback()
    isSpeaking = false
  }

  /// One generated piece: the Jarvis voice's audio, or text the system voice has to read.
  private enum Spoken {
    case wav(Data)
    case fallback(String)
  }

  private func run() async {
    isSpeaking = true
    defer {
      isSpeaking = false
      pipeline = nil
    }
    var next: Task<Spoken, Never>?
    while !Task.isCancelled, !queue.isEmpty || next != nil {
      let pending = next ?? fetch(queue.removeFirst())
      next = nil
      let spoken = await pending.value
      if Task.isCancelled { return }
      // The next piece generates while this one plays.
      if !queue.isEmpty { next = fetch(queue.removeFirst()) }
      switch spoken {
      case .wav(let wav):
        lastSource = .jarvisVoice
        await play(wav)
      case .fallback(let piece):
        await speakWithSystemVoice(piece)
      }
    }
  }

  /// Generates one piece. Any failure (server down, busy, 422) falls back to the system voice.
  private func fetch(_ piece: String) -> Task<Spoken, Never> {
    Task { [client, logger] in
      do {
        return .wav(try await client.wav(for: piece))
      } catch {
        logger.error(
          "Jarvis voice fell back to the system voice: \(String(describing: error), privacy: .public)"
        )
        return .fallback(piece)
      }
    }
  }

  private func play(_ wav: Data) async {
    guard let player = try? AVAudioPlayer(data: wav) else { return }
    self.player = player
    player.delegate = self
    await withCheckedContinuation { continuation in
      playbackDone = continuation
      if !player.play() { finishPlayback() }
    }
  }

  private func speakWithSystemVoice(_ piece: String) async {
    guard !Task.isCancelled, isEnabled else { return }
    lastSource = .systemVoice
    let utterance = AVSpeechUtterance(string: piece)
    utterance.voice =
      AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-GB.Malcolm")
      ?? AVSpeechSynthesisVoice(language: "en-GB")
    synthesizer.speak(utterance)
    while synthesizer.isSpeaking, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  private func finishPlayback() {
    playbackDone?.resume()
    playbackDone = nil
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.finishPlayback() }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    Task { @MainActor in self.finishPlayback() }
  }
}
