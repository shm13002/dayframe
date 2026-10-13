//
//  IslandSound.swift
//  Dayframe
//
//  The island's glassy sound effects, synthesized in code (no audio files): sine
//  "tones" with exponential envelopes and band-passed noise "whooshes". These are
//  the same recipes as the liquid-island-motion skill and Web/src/island/sound.ts.
//  Each cue is rendered into a short buffer and played on a small pool of player
//  nodes, so overlapping cues mix naturally. Plays at system volume; silent when
//  the Mac is muted or the island's sound setting is off.
//

import AVFoundation
import Foundation

enum IslandCue: String, CaseIterable {
  case drip, pop, grain, bloop, eyes, ping1, ping2, ping3
  case streamStart, count, swoosh, finale, settle
  // Native pill moments
  case blink, closeEyes, openEyes, hover, open, close
}

final class IslandSound {
  static let shared = IslandSound()

  static let enabledKey = "islandSoundEnabled"
  static let volumeKey = "islandSoundVolume"

  private let engine = AVAudioEngine()
  private let format: AVAudioFormat
  private var players: [AVAudioPlayerNode] = []
  private var nextPlayer = 0
  private let queue = DispatchQueue(label: "local.dayframe.island.sound", qos: .userInitiated)
  private var cache: [IslandCue: AVAudioPCMBuffer] = [:]
  private var idleStop: DispatchWorkItem?
  private var configured = false

  private init() {
    format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
  }

  var isEnabled: Bool {
    UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
  }

  /// 0...1, default 0.8.
  var volume: Float {
    let v = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 0.8
    return Float(min(max(v, 0), 1))
  }

  func play(_ cue: IslandCue, value: Double = 0) {
    guard isEnabled else { return }
    queue.async { [self] in
      guard let buffer = buffer(for: cue, value: value) else { return }
      guard startEngineIfNeeded() else { return }
      let player = players[nextPlayer]
      nextPlayer = (nextPlayer + 1) % players.count
      player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
      if !player.isPlaying { player.play() }
      scheduleIdleStop()
    }
  }

  // MARK: - Engine

  private func startEngineIfNeeded() -> Bool {
    if !configured {
      for _ in 0..<12 {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        players.append(player)
      }
      configured = true
    }
    engine.mainMixerNode.outputVolume = volume
    if engine.isRunning { return true }
    do {
      try engine.start()
      return true
    } catch {
      print("[IslandSound] engine failed to start: \(error.localizedDescription)")
      return false
    }
  }

  /// Let the audio hardware sleep when the island is quiet.
  private func scheduleIdleStop() {
    idleStop?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.players.forEach { $0.stop() }
      self.engine.stop()
    }
    idleStop = work
    queue.asyncAfter(deadline: .now() + 8, execute: work)
  }

  // MARK: - Recipes (seconds, Hz, linear gain)

  private func buffer(for cue: IslandCue, value: Double) -> AVAudioPCMBuffer? {
    // Grains and count chirps vary every time; everything else is rendered once.
    let varies = cue == .grain || cue == .count
    if !varies, let cached = cache[cue] { return cached }
    var s = Synth(sampleRate: format.sampleRate)
    switch cue {
    case .drip: s.whoosh(from: 1200, to: 3000, dur: 0.45, gain: 0.22)
    case .pop:
      s.tink(1000, gain: 0.25)
      s.tone(160, to: 55, dur: 0.3, gain: 0.45)
    case .grain: s.tone(Double.random(in: 2000...3600), dur: 0.05, gain: 0.018)
    case .bloop: s.tone(2000, to: 2900, dur: 0.12, gain: 0.08)
    case .eyes:
      s.tink(900, gain: 0.18)
      s.tink(1200, gain: 0.1, delay: 0.04)
    case .ping1: s.tone(3200, dur: 0.15, gain: 0.07)
    case .ping2: s.tone(2900, dur: 0.15, gain: 0.07)
    case .ping3:
      s.tone(3300, dur: 0.15, gain: 0.06)
      s.tone(2600, dur: 0.2, gain: 0.05, delay: 0.08)
    case .streamStart: s.whoosh(from: 800, to: 2800, dur: 0.6, gain: 0.15)
    case .count:
      let v = min(max(value, 0), 100)
      s.tone(1600 + v * 15, to: 2100 + v * 15, dur: 0.07, gain: 0.05)
    case .swoosh: s.whoosh(from: 3000, to: 900, dur: 0.6, gain: 0.2)
    case .finale:
      s.tink(1000, gain: 0.25)
      s.tink(1600, gain: 0.12, delay: 0.03)
      s.tink(2400, gain: 0.06, delay: 0.06)
      s.tone(350, dur: 0.6, gain: 0.18, attack: 0.02)
    case .settle:
      s.tone(3000, dur: 0.2, gain: 0.05)
      s.tone(2400, dur: 0.8, gain: 0.06, delay: 0.05)
    case .blink: s.tone(3100, dur: 0.1, gain: 0.04)
    case .closeEyes:
      for i in 0..<3 { s.tone(3000 - Double(i) * 260, dur: 0.1, gain: 0.04, delay: Double(i) * 0.07) }
    case .openEyes: s.tone(1600, to: 2600, dur: 0.16, gain: 0.06)
    case .hover: s.tone(2600, dur: 0.08, gain: 0.035)
    case .open:
      s.whoosh(from: 400, to: 2200, dur: 0.45, gain: 0.22)
      s.tink(1050, gain: 0.18, delay: 0.12)
    case .close:
      s.tink(950, gain: 0.14)
      for i in 0..<4 { s.tone(3300 - Double(i) * 180, dur: 0.1, gain: 0.04, delay: 0.08 + Double(i) * 0.07) }
    }
    let buffer = s.render(format: format)
    if !varies, let buffer { cache[cue] = buffer }
    return buffer
  }
}

/// Offline mixer for one cue: voices are summed into a sample array, then soft-clipped.
private struct Synth {
  let sampleRate: Double
  private(set) var samples: [Float] = []

  init(sampleRate: Double) {
    self.sampleRate = sampleRate
  }

  private mutating func ensure(_ count: Int) {
    if samples.count < count { samples.append(contentsOf: repeatElement(0, count: count - samples.count)) }
  }

  /// Exponential attack from silence to `gain`, then exponential decay to silence at `dur`.
  private func envelope(_ t: Double, dur: Double, gain: Double, attack: Double) -> Double {
    let floor = 0.0001
    if t < attack { return floor * pow(gain / floor, t / attack) }
    return gain * pow(floor / gain, (t - attack) / max(dur - attack, 0.001))
  }

  /// Sine with an optional exponential pitch glide.
  mutating func tone(
    _ freq: Double, to: Double? = nil, dur: Double = 0.35, gain: Double = 0.2, attack: Double = 0.005,
    delay: Double = 0
  ) {
    let start = Int(delay * sampleRate)
    let n = Int(dur * sampleRate)
    ensure(start + n)
    var phase = 0.0
    for i in 0..<n {
      let t = Double(i) / sampleRate
      let f = to.map { freq * pow($0 / freq, t / dur) } ?? freq
      phase += 2 * .pi * f / sampleRate
      samples[start + i] += Float(sin(phase) * envelope(t, dur: dur, gain: gain, attack: attack))
    }
  }

  /// Glassy chime: the fundamental plus two quieter inharmonic partials.
  mutating func tink(_ freq: Double, gain: Double, delay: Double = 0) {
    tone(freq, dur: 0.45, gain: gain, delay: delay)
    tone(freq * 1.17, dur: 0.35, gain: gain * 0.6, delay: delay)
    tone(freq * 2.76, dur: 0.15, gain: gain * 0.12, delay: delay)
  }

  /// White noise through a band-pass (Q 1.2) whose center sweeps from `from` to `to`.
  mutating func whoosh(from: Double, to: Double, dur: Double, gain: Double, delay: Double = 0) {
    let start = Int(delay * sampleRate)
    let n = Int(dur * sampleRate)
    ensure(start + n)
    let q = 1.2
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    for i in 0..<n {
      let t = Double(i) / sampleRate
      let f = from * pow(to / from, t / dur)
      // RBJ band-pass (constant 0 dB peak gain)
      let w0 = 2 * .pi * f / sampleRate
      let alpha = sin(w0) / (2 * q)
      let a0 = 1 + alpha
      let b0 = alpha / a0, b2 = -alpha / a0
      let a1 = -2 * cos(w0) / a0, a2 = (1 - alpha) / a0
      let x0 = Double.random(in: -1...1)
      let y0 = b0 * x0 + b2 * x2 - a1 * y1 - a2 * y2
      x2 = x1; x1 = x0; y2 = y1; y1 = y0
      samples[start + i] += Float(y0 * envelope(t, dur: dur, gain: gain, attack: dur * 0.4))
    }
  }

  /// Master gain 0.55 like the prototypes, with a soft clip in place of their compressor.
  func render(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let tail = Int(0.05 * sampleRate)
    let count = samples.count + tail
    guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
      let out = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(count)
    for i in 0..<count {
      let x = i < samples.count ? samples[i] * 0.55 : 0
      out[i] = tanhf(x * 1.2) / 1.2
    }
    return buffer
  }
}
