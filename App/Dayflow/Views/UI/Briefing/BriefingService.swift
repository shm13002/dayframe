//
//  BriefingService.swift
//  Dayframe
//
//  Talks to the local Briefing service (~/Briefing, http://127.0.0.1:<port>).
//  Everything stays on this Mac; the service is just another local process.
//

import Foundation

struct BriefingTodo: Identifiable, Decodable, Equatable {
  let id: String
  let text: String
  let done: Bool
  let source: String?
}

struct BriefingCard: Identifiable, Decodable, Equatable {
  var id: String { "\(startTs)-\(ln ?? 0)" }
  let ln: Int?
  let startTs: Int
  let endTs: Int?
  let title: String?
  let summary: String?
  let category: String?
  let type: String?

  enum CodingKeys: String, CodingKey {
    case ln, title, summary, category, type
    case startTs = "start_ts"
    case endTs = "end_ts"
  }
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
  let timeline: [BriefingCard]?
  let todos: [BriefingTodo]?
  let projects: [BriefingProject]?
  let stats: BriefingStats?
  let settings: [String: JSONValue]?

  enum CodingKeys: String, CodingKey {
    case briefing, timeline, todos, projects, stats, settings
    case briefingAt = "briefing_at"
    case sessionGoal = "session_goal"
  }
}

/// Minimal JSON value so unknown settings decode without failing.
enum JSONValue: Decodable, Equatable {
  case string(String), number(Double), bool(Bool), other

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else { self = .other }
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

  init(_ raw: String) {
    var current = "left"
    var buffers: [String: [String]] = [:]
    for line in raw.components(separatedBy: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      let upper = t.uppercased()
      if let r = Self.header(upper, t, "WHERE YOU LEFT OFF") { current = "left"; buffers[current, default: []].append(r); continue }
      if let r = Self.header(upper, t, "YOUR GOAL") { current = "goal"; buffers[current, default: []].append(r); continue }
      if let r = Self.header(upper, t, "NEXT STEPS") { current = "next"; buffers[current, default: []].append(r); continue }
      if upper.hasPrefix("REFS:") { current = "refs"; buffers[current, default: []].append(String(t.dropFirst(5))); continue }
      buffers[current, default: []].append(t)
    }
    func joined(_ k: String) -> String {
      (buffers[k] ?? []).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "  ", with: " ")
    }
    leftOff = Self.stripCitations(joined("left"))
    goal = Self.stripCitations(joined("goal"))
    refs = joined("refs")
    nextSteps = (buffers["next"] ?? [])
      .map { $0.replacingOccurrences(of: #"^\s*(\d+[.)]|[-•*])\s*"#, with: "", options: .regularExpression) }
      .map(Self.stripCitations)
      .filter { !$0.isEmpty }
  }

  private static func header(_ upper: String, _ line: String, _ name: String) -> String? {
    guard upper.hasPrefix(name) else { return nil }
    var rest = line.dropFirst(name.count)
    if rest.hasPrefix(":") { rest = rest.dropFirst() }
    return rest.trimmingCharacters(in: .whitespaces)
  }

  /// "(2026-10-12#2)" / "[2026-10-12#3]" / "(projects/x.md)" are for the model, not for reading.
  static func stripCitations(_ s: String) -> String {
    s.replacingOccurrences(of: #"\s*[\(\[]\d{4}-\d\d-\d\d#\d+[\)\]]"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s*\((?:memory/|projects/)[^)]*\)"#, with: "", options: .regularExpression)
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
    } catch {
      if state == nil { phase = .offline }
    }
  }

  func newBriefing() async {
    isBriefing = true
    defer { isBriefing = false }
    _ = try? await post("/api/brief", [:], timeout: 300)
    await refresh()
  }

  func setTodo(_ todo: BriefingTodo, done: Bool) async {
    _ = try? await post("/api/todo", ["id": todo.id, "done": done])
    await refresh()
  }

  func addTodo(_ text: String) async {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    _ = try? await post("/api/todo", ["add": t])
    await refresh()
  }

  func feedback(up: Bool) async {
    _ = try? await post("/api/brief/feedback", ["rating": up ? "up" : "down"])
  }

  func ask(_ question: String) async {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    isAsking = true
    askAnswer = nil
    defer { isAsking = false }
    if let data = try? await post("/api/ask", ["q": q], timeout: 300),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      askAnswer = (obj["answer"] as? String) ?? "No answer."
    } else {
      askAnswer = "Couldn't reach your briefing service."
    }
  }

  func clearAnswer() { askAnswer = nil }

  func resume() async {
    _ = try? await post("/api/resume", ["confirm": true])
  }

  func setWriter(_ backend: String) async {
    _ = try? await post("/api/settings", ["llm_backend": backend])
    await refresh()
  }

  // MARK: - HTTP

  private func get(_ path: String) async throws -> Data {
    var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
    req.timeoutInterval = 5
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400 else { throw URLError(.badServerResponse) }
    return data
  }

  @discardableResult
  private func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 15) async throws -> Data {
    var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = timeout
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400 else {
      lastError = String(data: data, encoding: .utf8)
      throw URLError(.badServerResponse)
    }
    return data
  }
}
