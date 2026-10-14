//
//  JarvisVoice.swift
//  Jarvis
//
//  Two local voice servers, plus the phrase cache and a British Mac voice:
//    Cloned Jarvis voice  ~/jarvis-voice  127.0.0.1:5055  ~50 s per sentence (OmniVoice)
//    Fast filler voice    ~/jarvis-piper  127.0.0.1:5056  Alan (Piper), until a trained voice exists
//  Both refuse an Origin header and want a bearer token from their service.token.
//    .live   cache, then Alan, then the Mac voice. Never waits on the cloned voice.
//    .notice cache, then the cloned voice, then Alan, then the Mac voice.
//  Every line the cloned voice produces is kept in the phrase cache.
//

import AVFoundation
import CryptoKit
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

/// Which server speaks next. Pure, unit-tested. Alan is the fast filler.
enum JarvisVoiceRoute {
  enum Mode: Equatable {
    case live
    case notice
  }

  enum Step: Equatable {
    case cache
    case piper
    case cloned
    case mac
  }

  static func steps(mode: Mode) -> [Step] {
    switch mode {
    case .live: return [.cache, .piper, .mac]
    case .notice: return [.cache, .cloned, .piper, .mac]
    }
  }

  /// Milliseconds from `speak()` until playback starts.
  static func firstAudioMs(from asked: Date, to played: Date) -> Int {
    max(0, Int((played.timeIntervalSince(asked) * 1000).rounded()))
  }
}

/// One request to a voice server. `send` is injectable so tests run without the server.
struct JarvisVoiceClient {
  enum Engine: Equatable {
    /// OmniVoice clone, port 5055. Slow; retried when busy.
    case cloned
    /// Piper (Alan for now), port 5056. One try, 3 s.
    case piper
  }

  enum Failure: Error, Equatable {
    case noToken
    case unreachable
    case unauthorized
    case busy
    case unverified
    case failed(Int)
  }

  typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)

  var engine: Engine = .cloned
  var endpoint = URL(string: "http://127.0.0.1:5055/tts")!
  var token: () -> String? = JarvisVoiceClient.readToken
  var send: Send = JarvisVoiceClient.urlSessionSend
  /// How often a busy cloned server (429) is asked again, half a second apart.
  var busyRetries = 20

  static func makePiper() -> JarvisVoiceClient {
    var client = JarvisVoiceClient()
    client.engine = .piper
    client.token = { JarvisVoiceClient.readToken(at: piperTokenPath) }
    client.busyRetries = 0
    return client
  }

  func wav(for text: String) async throws -> Data {
    guard let token = token() else { throw Failure.noToken }
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.timeoutInterval = engine == .piper ? 3 : 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let spoken = String(text.prefix(JarvisSpeechText.maxPiece))
    let body: [String: Any] =
      engine == .piper
      ? ["text": spoken]
      : ["text": spoken, "voice": "jarvis", "steps": 32]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let retryLimit = engine == .piper ? 0 : busyRetries
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
        guard attempt <= retryLimit else { throw Failure.busy }
        try await Task.sleep(for: .milliseconds(500))
      default: throw Failure.failed(response.statusCode)
      }
    }
  }

  private var requestURL: URL {
    engine == .piper ? URL(string: "http://127.0.0.1:5056/tts")! : endpoint
  }

  static let tokenPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("jarvis-voice/service.token")
  static let piperTokenPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("jarvis-piper/service.token")

  static func readToken() -> String? { readToken(at: tokenPath) }

  static func readToken(at path: URL) -> String? {
    guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
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
    case piperVoice
    case systemVoice
  }

  enum Mode {
    /// The owner is waiting: never wait on the slow cloned voice.
    case live
    /// Nobody is waiting (briefings, notices): the cloned voice even when slow.
    case notice
  }

  /// Lines Jarvis says often, prepared in the Jarvis voice ahead of time.
  static let commonPhrases = [
    "On it.", "One moment.", "Done.", "All done.", "Right away.", "Working on it.",
    "I need your approval for that.", "Here's what I found.", "I couldn't do that.",
    "Good morning, Shahzeb.", "Good afternoon, Shahzeb.", "Good evening, Shahzeb.",
    "Jarvis is online and ready.", "Your briefing is ready.", "I've finished.",
    "Nothing needs your attention right now.", "Hermes isn't running.",
    "Sorry, I didn't catch that.",
  ]

  @Published private(set) var isSpeaking = false
  /// Which voice spoke last, for Settings › Jarvis.
  @Published private(set) var lastSource: Source?
  /// How many of the common phrases are ready in the Jarvis voice.
  @Published private(set) var preparedPhrases = 0

  var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.enabled)
      if !newValue { stop() }
    }
  }

  var client = JarvisVoiceClient()
  var piper = JarvisVoiceClient.makePiper()
  let cache = JarvisPhraseCache()
  private let logger = Logger(subsystem: "local.dayframe.app", category: "jarvis")
  private var queue: [(text: String, mode: Mode, askedAt: Date)] = []
  private var pipeline: Task<Void, Never>?
  private var preparing: Task<Void, Never>?
  private var player: AVAudioPlayer?
  private var playbackDone: CheckedContinuation<Void, Never>?
  private let synthesizer = AVSpeechSynthesizer()

  /// Speaks the text after anything already queued.
  func speak(_ text: String, mode: Mode = .live) {
    guard isEnabled else { return }
    let askedAt = Date()
    queue += JarvisSpeechText.pieces(text).map { ($0, mode, askedAt) }
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

  /// Prepares the common phrases in the Jarvis voice, one at a time, only while nothing is spoken.
  func prepareCommonPhrases() {
    preparedPhrases = Self.commonPhrases.filter { cache.wav(for: $0) != nil }.count
    guard preparing == nil, preparedPhrases < Self.commonPhrases.count else { return }
    preparing = Task(priority: .background) { [weak self] in
      guard let self else { return }
      defer { self.preparing = nil }
      for phrase in Self.commonPhrases where self.cache.wav(for: phrase) == nil {
        while self.isSpeaking, !Task.isCancelled { try? await Task.sleep(for: .seconds(5)) }
        guard !Task.isCancelled else { return }
        // The voice server is shared (other apps use it too) and makes one line at a time:
        // when it is busy, wait and ask again rather than give up on the phrase.
        var wav: Data?
        for _ in 0..<40 where wav == nil && !Task.isCancelled {
          do {
            wav = try await self.client.wav(for: phrase)
          } catch JarvisVoiceClient.Failure.busy {
            try? await Task.sleep(for: .seconds(30))
          } catch {
            self.logger.error(
              "Couldn't prepare \"\(phrase, privacy: .public)\": \(String(describing: error), privacy: .public)"
            )
            break
          }
        }
        if let wav {
          self.cache.store(wav, for: phrase)
          self.preparedPhrases += 1
          self.logger.info(
            "Prepared a Jarvis phrase (\(self.preparedPhrases)/\(Self.commonPhrases.count))")
        }
      }
    }
  }

  private func run() async {
    isSpeaking = true
    defer {
      isSpeaking = false
      pipeline = nil
    }
    while !Task.isCancelled, !queue.isEmpty {
      let (piece, mode, askedAt) = queue.removeFirst()
      let route: JarvisVoiceRoute.Mode = mode == .notice ? .notice : .live
      for step in JarvisVoiceRoute.steps(mode: route) {
        switch step {
        case .cache:
          if let wav = cache.wav(for: piece) {
            lastSource = .jarvisVoice
            logFirstAudio("cache", askedAt: askedAt)
            await play(wav)
          } else {
            continue
          }
        case .piper:
          if let wav = await piperWav(piece) {
            lastSource = .piperVoice
            logFirstAudio("piper", askedAt: askedAt)
            await play(wav)
          } else {
            continue
          }
        case .cloned:
          if let wav = await cloned(piece) {
            lastSource = .jarvisVoice
            logFirstAudio("cloned", askedAt: askedAt)
            await play(wav)
          } else {
            continue
          }
        case .mac:
          await speakWithSystemVoice(piece, askedAt: askedAt)
        }
        break
      }
    }
  }

  /// Logged at the moment playback starts, measured from the `speak()` that queued the piece.
  private func logFirstAudio(_ engine: String, askedAt: Date) {
    let ms = JarvisVoiceRoute.firstAudioMs(from: askedAt, to: Date())
    logger.info(
      "Voice engine=\(engine, privacy: .public) firstAudioMs=\(ms, privacy: .public)")
  }

  /// Alan (Piper). Not cached: the phrase cache belongs to the cloned Jarvis voice.
  private func piperWav(_ piece: String) async -> Data? {
    do {
      return try await piper.wav(for: piece)
    } catch {
      logger.error(
        "Piper voice fell back: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// The Jarvis voice for one piece (slow); kept in the cache. Nil when the server fails.
  private func cloned(_ piece: String) async -> Data? {
    do {
      let wav = try await client.wav(for: piece)
      cache.store(wav, for: piece)
      return wav
    } catch {
      logger.error(
        "Jarvis voice fell back to the system voice: \(String(describing: error), privacy: .public)"
      )
      return nil
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

  private func speakWithSystemVoice(_ piece: String, askedAt: Date) async {
    guard !Task.isCancelled, isEnabled else { return }
    lastSource = .systemVoice
    logFirstAudio("mac", askedAt: askedAt)
    let utterance = AVSpeechUtterance(string: piece)
    utterance.voice = Self.bestBritishVoice
    synthesizer.speak(utterance)
    while synthesizer.isSpeaking, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  /// The highest-quality British English voice installed (Premium, then Enhanced, then Daniel).
  static var bestBritishVoice: AVSpeechSynthesisVoice? {
    let british = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-GB" }
    let ranked = british.sorted { $0.quality.rawValue > $1.quality.rawValue }
    let male = ranked.first {
      ["Jamie", "Daniel", "Oliver", "Arthur", "Malcolm"].contains($0.name) && $0.quality != .default
    }
    return male ?? ranked.first { $0.quality != .default } ?? AVSpeechSynthesisVoice(
      identifier: "com.apple.voice.compact.en-GB.Daniel")
      ?? AVSpeechSynthesisVoice(language: "en-GB")
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

/// WAVs of lines the Jarvis voice has already said, keyed by their normalized text.
struct JarvisPhraseCache {
  var folder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(
      "Library/Application Support/Dayflow/Jarvis/voice-cache", isDirectory: true)

  /// "On it!" and "on it." are the same line. Pure, unit-tested.
  static func key(_ text: String) -> String {
    let normalized = text.lowercased()
      .replacingOccurrences(of: "’", with: "'")
      .replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression)
      .split(separator: " ").joined(separator: " ")
    let digest = SHA256.hash(data: Data(normalized.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  func wav(for text: String) -> Data? {
    try? Data(contentsOf: folder.appendingPathComponent(Self.key(text) + ".wav"))
  }

  func store(_ wav: Data, for text: String) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? wav.write(to: folder.appendingPathComponent(Self.key(text) + ".wav"), options: .atomic)
  }
}
