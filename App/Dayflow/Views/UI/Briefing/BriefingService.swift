//
//  BriefingService.swift
//  Dayframe
//
//  Talks to the local Briefing service (~/Briefing, http://127.0.0.1:<port>).
//  Everything stays on this Mac; the service is just another local process.
//

import Foundation
import OSLog

private let briefingLog = Logger(subsystem: "local.dayframe.app", category: "briefing")

struct BriefingTodo: Identifiable, Decodable, Equatable {
  let id: String
  let text: String
  let done: Bool
  let source: String?
}

struct BriefingCard: Identifiable, Decodable, Equatable {
  var id: String { "\(startTs)-\(ln ?? 0)" }
  let ln: Int?
  let ts: Double?
  let rawStart: Double?
  let rawEnd: Double?
  let title: String?
  let summary: String?
  let category: String?
  let type: String?

  /// Cards have start/end; notes only have `ts`.
  var startTs: Int { Int(rawStart ?? ts ?? 0) }
  var endTs: Int? { rawEnd.map { Int($0) } }

  enum CodingKeys: String, CodingKey {
    case ln, ts, title, summary, category, type
    case rawStart = "start_ts"
    case rawEnd = "end_ts"
  }
}

/// Decodes an array, skipping elements that don't fit instead of failing the whole response.
struct Lossy<Element: Decodable & Equatable>: Decodable, Equatable {
  let items: [Element]
  init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var out: [Element] = []
    while !c.isAtEnd {
      if let e = try? c.decode(Element.self) { out.append(e) } else { _ = try? c.decode(Skip.self) }
    }
    items = out
  }
  private struct Skip: Decodable {}
}

struct BriefingProject: Identifiable, Decodable, Equatable {
  var id: String { slug }
  let slug: String
  let minutes: Int?
  let last: String?
}

struct BriefingStats: Decodable, Equatable {
  let totalMinutes: Int?
  let bestHours: [Int]?
  let byCategory: [String: Int]?

  enum CodingKeys: String, CodingKey {
    case totalMinutes = "total_minutes"
    case bestHours = "best_hours"
    case byCategory = "by_category"
  }
}

struct BriefingState: Decodable, Equatable {
  let briefing: String?
  let briefingAt: Double?
  let sessionGoal: String?
  private let rawTimeline: Lossy<BriefingCard>?
  private let rawTodos: Lossy<BriefingTodo>?
  private let rawProjects: Lossy<BriefingProject>?
  let stats: BriefingStats?
  let settings: [String: JSONValue]?

  var timeline: [BriefingCard]? { rawTimeline?.items }
  var todos: [BriefingTodo]? { rawTodos?.items }
  var projects: [BriefingProject]? { rawProjects?.items }

  enum CodingKeys: String, CodingKey {
    case briefing, stats, settings
    case rawTimeline = "timeline"
    case rawTodos = "todos"
    case rawProjects = "projects"
    case briefingAt = "briefing_at"
    case sessionGoal = "session_goal"
  }
}

/// Minimal JSON value so unknown settings decode without failing.
enum JSONValue: Decodable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case other

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? c.decode(Double.self) {
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else {
      self = .other
    }
  }

  var stringValue: String? {
    if case .string(let s) = self { return s }
    return nil
  }
}

/// The briefing text split into the sections the model writes.
struct BriefingSections: Equatable {
  var leftOff: String = ""
  var goal: String = ""
  var nextSteps: [String] = []
  var refs: String = ""
  /// Briefing's "Question for you: …" about a memory that disagrees with itself.
  var question: String = ""
  /// The trailing one-liners Briefing appends (stale facts, a suggested improvement, more loops).
  var notes: [String] = []

  init(_ raw: String) {
    var current = "left"
    var buffers: [String: [String]] = [:]
    for line in raw.components(separatedBy: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      let upper = t.uppercased()
      if let r = Self.header(upper, t, "WHERE YOU LEFT OFF") {
        current = "left"
        buffers[current, default: []].append(r)
        continue
      }
      if let r = Self.header(upper, t, "YOUR GOAL") {
        current = "goal"
        buffers[current, default: []].append(r)
        continue
      }
      if let r = Self.header(upper, t, "NEXT STEPS") {
        current = "next"
        buffers[current, default: []].append(r)
        continue
      }
      if let r = Self.header(upper, t, "QUESTION FOR YOU") {
        current = "question"
        buffers[current, default: []].append(r)
        continue
      }
      if Self.isNote(t) {
        buffers["notes", default: []].append(t)
        continue
      }
      if upper.hasPrefix("REFS:") {
        current = "refs"
        buffers[current, default: []].append(String(t.dropFirst(5)))
        continue
      }
      buffers[current, default: []].append(t)
    }
    func joined(_ k: String) -> String {
      (buffers[k] ?? []).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "  ", with: " ")
    }
    leftOff = Self.stripCitations(joined("left"))
    goal = Self.stripCitations(joined("goal"))
    refs = joined("refs")
    question = joined("question")
    notes = (buffers["notes"] ?? []).filter { !$0.isEmpty }
    nextSteps = (buffers["next"] ?? [])
      .map {
        $0.replacingOccurrences(
          of: #"^\s*(\d+[.)]|[-•*])\s*"#, with: "", options: .regularExpression)
      }
      .map(Self.stripCitations)
      .filter { !$0.isEmpty }
  }

  /// Lines briefing.py adds after the model's sections (cmd_brief / fallback_brief).
  private static func isNote(_ line: String) -> Bool {
    line.hasPrefix("Suggested improvement")
      || line.range(of: #"^\d+ (remembered fact|more open loop)"#, options: .regularExpression)
        != nil
  }

  private static func header(_ upper: String, _ line: String, _ name: String) -> String? {
    guard upper.hasPrefix(name) else { return nil }
    var rest = line.dropFirst(name.count)
    if rest.hasPrefix(":") { rest = rest.dropFirst() }
    return rest.trimmingCharacters(in: .whitespaces)
  }

  /// "(2026-10-12#2)" / "[2026-10-12#3]" / "(projects/x.md)" are for the model, not for reading.
  static func stripCitations(_ s: String) -> String {
    s.replacingOccurrences(
      of: #"\s*[\(\[]\d{4}-\d\d-\d\d#\d+[\)\]]"#, with: "", options: .regularExpression
    )
    .replacingOccurrences(
      of: #"\s*\((?:memory/|projects/)[^)]*\)"#, with: "", options: .regularExpression
    )
    .trimmingCharacters(in: .whitespaces)
  }

  var isEmpty: Bool { leftOff.isEmpty && goal.isEmpty && nextSteps.isEmpty }
}

@MainActor
final class BriefingService: ObservableObject {
  static let shared = BriefingService()

  enum Phase: Equatable { case loading, ready, offline }

  @Published private(set) var phase: Phase = .loading
  @Published private(set) var state: BriefingState?
  @Published private(set) var isBriefing = false
  @Published private(set) var askAnswer: String?
  @Published private(set) var isAsking = false
  @Published var lastError: String?

  private var refreshTask: Task<Void, Never>?

  static var port: Int {
    let cfg = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Briefing/config.json")
    if let data = try? Data(contentsOf: cfg),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let port = obj["dashboard_port"] as? Int
    {
      return port
    }
    return 8765
  }

  private static let unreadableState = "Couldn't read the briefing data."

  static var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

  var sections: BriefingSections { BriefingSections(state?.briefing ?? "") }

  /// Which model writes briefings (Briefing's `llm_backend`).
  var writer: String { state?.settings?["llm_backend"]?.stringValue ?? "ollama" }

  func startAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
      }
    }
  }

  func stopAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  func refresh() async {
    do {
      let data = try await get("/api/state")
      let decoded = try JSONDecoder().decode(BriefingState.self, from: data)
      if decoded != state { state = decoded }
      phase = .ready
      if lastError == Self.unreadableState { lastError = nil }
    } catch is DecodingError {
      lastError = Self.unreadableState
      phase = state == nil ? .offline : .ready
    } catch {
      if state == nil { phase = .offline }
    }
  }

  func newBriefing() async {
    isBriefing = true
    defer { isBriefing = false }
    await perform("write a new briefing", "/api/brief", [:], timeout: 300)
    await refresh()
  }

  func setTodo(_ todo: BriefingTodo, done: Bool) async {
    await perform("update the to-do", "/api/todo", ["id": todo.id, "done": done])
    await refresh()
  }

  func addTodo(_ text: String) async {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    await perform("add the to-do", "/api/todo", ["add": t])
    await refresh()
  }

  func feedback(up: Bool) async {
    await perform("send feedback", "/api/brief/feedback", ["rating": up ? "up" : "down"])
  }

  func ask(_ question: String) async {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    isAsking = true
    askAnswer = nil
    defer { isAsking = false }
    if let data = await perform("answer the question", "/api/ask", ["q": q], timeout: 300),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      askAnswer = (obj["answer"] as? String) ?? "No answer."
    } else {
      askAnswer = "Couldn't reach your briefing service."
    }
  }

  func clearAnswer() { askAnswer = nil }

  func resume() async {
    await perform("resume", "/api/resume", ["confirm": true])
  }

  func setWriter(_ backend: String) async {
    await perform("change who writes briefings", "/api/settings", ["llm_backend": backend])
    await refresh()
  }

  // MARK: - HTTP

  /// Runs one user action against the service. A failure is shown (`lastError`) and logged
  /// instead of dropped, so a click that seems to do nothing always says why.
  @discardableResult
  private func perform(
    _ action: String, _ path: String, _ body: [String: Any], timeout: TimeInterval = 15
  ) async -> Data? {
    do {
      let data = try await post(path, body, timeout: timeout)
      lastError = nil
      return data
    } catch {
      lastError = BriefingServiceError.message(action: action, error: error)
      briefingLog.error(
        "[Briefing] \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private func get(_ path: String) async throws -> Data {
    var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
    req.timeoutInterval = 5
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400 else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  @discardableResult
  private func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 15) async throws
    -> Data
  {
    var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = timeout
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400 else {
      throw BriefingServiceError(body: data)
    }
    return data
  }
}

/// A Briefing request the service refused. Carries the service's own `{"error": …}` text
/// when it sent one, so the banner can say why instead of showing a raw response body.
struct BriefingServiceError: Error, Equatable {
  let serverMessage: String?

  init(body: Data) {
    let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    let text = (obj?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    serverMessage = text.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
  }

  /// The banner text for a failed action.
  static func message(action: String, error: Error) -> String {
    if let reason = (error as? BriefingServiceError)?.serverMessage {
      return "Couldn't \(action): \(reason)" + (reason.hasSuffix(".") ? "" : ".")
    }
    return "Couldn't \(action): the Briefing service didn't answer."
  }
}
