import XCTest

@testable import Dayflow

/// Dayframe: Chat on the on-device model (Qwen on Ollama).
final class LocalDashboardChatTests: XCTestCase {

  // MARK: - Provider selection

  func testStoredProviderFallsBackToLocal() {
    XCTAssertEqual(DashboardChatProvider.fromStoredValue(nil), .local)
    XCTAssertEqual(DashboardChatProvider.fromStoredValue("gemini"), .local)
    XCTAssertEqual(DashboardChatProvider.fromStoredValue("nonsense"), .local)
    XCTAssertEqual(DashboardChatProvider.fromStoredValue("local"), .local)
    XCTAssertEqual(DashboardChatProvider.fromStoredValue("claude"), .claude)
    XCTAssertEqual(DashboardChatProvider.fromStoredValue("codex"), .codex)
  }

  func testOnlyCLIProvidersResumeSessions() {
    XCTAssertFalse(DashboardChatProvider.local.usesCLISession)
    XCTAssertFalse(DashboardChatProvider.gemini.usesCLISession)
    XCTAssertTrue(DashboardChatProvider.claude.usesCLISession)
    XCTAssertTrue(DashboardChatProvider.codex.usesCLISession)
    XCTAssertEqual(DashboardChatProvider.local.runtimeLabel, "local_function_calling")
  }

  // MARK: - Streaming

  func testAccumulatorCollectsTextDeltas() throws {
    var accumulator = LocalChatStreamAccumulator()
    XCTAssertEqual(
      try accumulator.consume(
        line: #"data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"You "}}]}"#),
      "You ")
    XCTAssertEqual(
      try accumulator.consume(
        line: #"data: {"choices":[{"index":0,"delta":{"content":"coded."}}]}"#),
      "coded.")
    XCTAssertNil(try accumulator.consume(line: ""))
    XCTAssertNil(try accumulator.consume(line: "data: [DONE]"))
    XCTAssertTrue(accumulator.isDone)
    XCTAssertEqual(accumulator.content, "You coded.")
    XCTAssertTrue(accumulator.toolCalls.isEmpty)
  }

  func testAccumulatorJoinsToolCallSplitAcrossChunks() throws {
    var accumulator = LocalChatStreamAccumulator()
    _ = try accumulator.consume(
      line:
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"fetchTimeline","arguments":"{\"date\":"}}]}}]}"#
    )
    _ = try accumulator.consume(
      line:
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"2026-10-12\"}"}}]}}]}"#
    )
    XCTAssertEqual(
      accumulator.toolCalls,
      [.init(id: "call_1", name: "fetchTimeline", arguments: #"{"date":"2026-10-12"}"#)])
  }

  func testAccumulatorSurfacesServerError() {
    var accumulator = LocalChatStreamAccumulator()
    XCTAssertThrowsError(
      try accumulator.consume(line: #"data: {"error":{"message":"model not found"}}"#))
  }

  func testHistoryIsTrimmedAndStartsWithUser() {
    var history: [DashboardChatTurn] = []
    for index in 0..<5 {
      history.append(.user("q\(index)"))
      history.append(.assistant("a\(index)"))
    }
    history.append(.user("latest"))
    let messages = OllamaProvider.localChatMessages(systemInstruction: "sys", history: history)
    XCTAssertEqual(messages.first?["role"] as? String, "system")
    XCTAssertEqual(messages[1]["role"] as? String, "user")
    XCTAssertEqual(messages.last?["content"] as? String, "latest")
    XCTAssertLessThanOrEqual(messages.count - 1, OllamaProvider.dashboardChatMaxHistoryTurns)
  }

  // MARK: - Compact tool results

  func testCompactTimelineIsOneLinePerCard() {
    let result: [String: Any] = [
      "summary": "Fetched 2 timeline cards for Mon, Oct 12.",
      "items": [
        [
          "day": "2026-10-12", "startTime": "9:00 AM", "endTime": "9:30 AM",
          "category": "Work", "title": "Wrote the brief", "summary": "Drafted section II.",
          "detailedSummary": "LONG DETAIL",
        ],
        [
          "day": "2026-10-12", "startTime": "9:30 AM", "endTime": "10:00 AM",
          "category": "Personal", "title": "Email", "summary": "",
        ],
      ],
    ]
    let text = DashboardChatTools.compactResult(name: "fetchTimeline", result: result)
    XCTAssertEqual(
      text,
      """
      Fetched 2 timeline cards for Mon, Oct 12. Total time across these cards: 1 h.
      [2026-10-12]
      9:00 AM–9:30 AM (30 min) · Work · Wrote the brief — Drafted section II.
      9:30 AM–10:00 AM (30 min) · Personal · Email
      """)
    XCTAssertFalse(text.contains("LONG DETAIL"))
  }

  func testCompactResultRespectsBudget() {
    let items: [[String: Any]] = (0..<200).map { index in
      [
        "day": "2026-10-12", "startTime": "9:00 AM", "endTime": "9:15 AM",
        "category": "Work", "title": "Card \(index)",
        "summary": String(repeating: "x", count: 400),
      ]
    }
    let text = DashboardChatTools.compactResult(
      name: "fetchTimeline", result: ["summary": "Fetched 200.", "items": items])
    XCTAssertLessThanOrEqual(text.count, DashboardChatTools.compactResultCharacterBudget + 120)
    XCTAssertTrue(text.contains("more lines omitted"))
  }

  func testDurationsHandleMidnightAndFormat() {
    XCTAssertEqual(DashboardChatTools.minutesBetween("11:50 PM", "12:10 AM"), 20)
    XCTAssertEqual(DashboardChatTools.minutesBetween("11:53 AM", "12:08 PM"), 15)
    XCTAssertNil(DashboardChatTools.minutesBetween("soon", "12:08 PM"))
    XCTAssertEqual(DashboardChatTools.formattedDuration(45), "45 min")
    XCTAssertEqual(DashboardChatTools.formattedDuration(93), "1 h 33 min")
  }

  func testBareTrailingSuggestionsAreExtracted() {
    let text = """
      - You coded most of the morning.

      ["What was I reading at 2pm?", "How long did I code?", "Any breaks?"]
      """
    let extracted = ChatMetadataParser.extractTrailingBareSuggestions(from: text)
    XCTAssertEqual(
      extracted?.0.trimmingCharacters(in: .whitespacesAndNewlines),
      "- You coded most of the morning.")
    XCTAssertNotNil(extracted?.1.data(using: .utf8))
    XCTAssertNil(ChatMetadataParser.extractTrailingBareSuggestions(from: "Totals: [1, 2, 3]"))
    XCTAssertNil(
      ChatMetadataParser.extractTrailingBareSuggestions(from: "See the list:\n[\"only one\"]"))
  }

  func testCompactResultReportsToolError() {
    let text = DashboardChatTools.compactResult(
      name: "fetchTimeline",
      result: [
        "summary": "bad", "error": ["code": "validation_error", "message": "Use YYYY-MM-DD."],
      ])
    XCTAssertEqual(text, "Error: Use YYYY-MM-DD.")
  }

  // MARK: - Live (skipped unless Ollama and the saved model are up)

  func testLiveQwenAnswersFromTimeline() async throws {
    guard await LocalChatAvailability.isReady() else {
      throw XCTSkip("Local model not reachable")
    }
    let endpoint =
      UserDefaults.standard.string(forKey: "llmLocalBaseURL") ?? "http://localhost:11434"
    let stream = OllamaProvider(endpoint: endpoint).generateDashboardChatStreaming(
      systemInstruction: ChatPromptBuilder.localSystemPrompt(),
      history: [.user("What did I work on today? Two short bullets.")]
    )

    var tools: [String] = []
    var toolOutputs: [String] = []
    var answer = ""
    for try await event in stream {
      switch event {
      case .toolStart(let command): tools.append(command)
      case .toolEnd(let output, _): toolOutputs.append(output)
      case .complete(let text): answer = text
      case .error(let message): XCTFail(message)
      default: break
      }
    }
    print("LIVE QWEN tools=\(tools) outputs=\(toolOutputs)\nLIVE QWEN answer:\n\(answer)")
    XCTAssertTrue(
      tools.contains { $0.hasPrefix("fetchTimeline") }, "Qwen should fetch the timeline")
    XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }
}
