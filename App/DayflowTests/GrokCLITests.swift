import XCTest

@testable import Dayflow

/// The Grok CLI (0.2.99) run headless: arguments Dayframe passes, and what it prints back.
final class GrokCLITests: XCTestCase {
  // MARK: Arguments

  func testTextTurnsGetNoToolsAndOneTurn() {
    let args = GrokCLICommand(promptFile: "/tmp/p.txt", model: "grok-4.5").arguments()
    XCTAssertEqual(Array(args.prefix(2)), ["--prompt-file", "/tmp/p.txt"])
    XCTAssertEqual(value(after: "--output-format", in: args), "json")
    XCTAssertEqual(value(after: "-m", in: args), "grok-4.5")
    XCTAssertEqual(value(after: "--max-turns", in: args), "1")
    XCTAssertTrue(
      value(after: "--disallowed-tools", in: args)?.contains("run_terminal_cmd") == true)
    for flag in ["--disable-web-search", "--no-subagents", "--no-memory", "--no-plan"] {
      XCTAssertTrue(args.contains(flag), flag)
    }
    XCTAssertFalse(args.contains("--always-approve"))
  }

  func testChatGetsOnlyTheShellAndCanResume() {
    let command = GrokCLICommand(
      promptFile: "/tmp/p.txt", resumeSessionID: "s-1", streaming: true, access: .shell)
    let args = command.arguments()
    XCTAssertEqual(value(after: "--output-format", in: args), "streaming-json")
    XCTAssertEqual(value(after: "-r", in: args), "s-1")
    XCTAssertFalse(
      value(after: "--disallowed-tools", in: args)?.contains("run_terminal_cmd") == true)
    XCTAssertTrue(value(after: "--disallowed-tools", in: args)?.contains("web_fetch") == true)
    XCTAssertTrue(args.contains("--always-approve"))
    XCTAssertFalse(args.contains("--max-turns"))
  }

  func testThePromptNeverAppearsInTheArguments() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = try GrokCLI.writePromptFile("my private note", in: folder)
    let args = GrokCLICommand(promptFile: file.path).arguments()
    XCTAssertFalse(args.joined(separator: " ").contains("my private note"))
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "my private note")
    let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
    XCTAssertEqual((mode as? NSNumber)?.intValue, 0o600)
  }

  func testUsesTheInstalledCLIWhenPresent() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    XCTAssertEqual(GrokCLI.executable(home: home), "grok")
    let bin = home.appendingPathComponent(".grok/bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let exe = bin.appendingPathComponent("grok")
    try Data("#!/bin/sh\n".utf8).write(to: exe)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    XCTAssertEqual(GrokCLI.executable(home: home), exe.path)
  }

  // MARK: Output

  func testJSONEnvelopeGivesTextSessionAndUsage() throws {
    let stdout = """
      {"text":"Hi there","stopReason":"EndTurn","sessionId":"abc123","usage":{"input_tokens":7210,"cache_read_input_tokens":41000,"output_tokens":1893,"reasoning_tokens":412}}
      """
    let envelope = try XCTUnwrap(GrokCLIOutput.parseEnvelope(stdout))
    XCTAssertEqual(envelope.text, "Hi there")
    XCTAssertEqual(envelope.sessionID, "abc123")
    XCTAssertNil(envelope.error)
    XCTAssertEqual(envelope.usage?.input, 7210)
    XCTAssertEqual(envelope.usage?.cachedInput, 41000)
    XCTAssertEqual(envelope.usage?.output, 1893)
  }

  func testExpiredSignInIsReadable() throws {
    // The exact line Grok 0.2.99 printed on this Mac when its 7-day sign-in had expired.
    let stdout = #"""
      {"type":"error","message":"Not signed in. To authenticate without a browser, run:\n  grok login --device-code\n\nAlternatively, set the XAI_API_KEY environment variable or run `grok login` on a machine with a browser."}
      """#
    let envelope = try XCTUnwrap(GrokCLIOutput.parseEnvelope(stdout))
    XCTAssertEqual(envelope.text, "")
    XCTAssertEqual(envelope.error, "Not signed in. To authenticate without a browser, run:")
    XCTAssertTrue(GrokCLIOutput.isSignInError(envelope.error ?? ""))
  }

  func testStreamingLinesBecomeChatEvents() {
    guard
      case .textDelta("Here's")? = GrokCLIOutput.parseStreamLine(
        #"{"type":"text","data":"Here's"}"#)
    else { return XCTFail("text") }
    guard
      case .thinking("Looking")? = GrokCLIOutput.parseStreamLine(
        #"{"type":"thought","data":"Looking"}"#)
    else { return XCTFail("thought") }
    guard
      case .sessionStarted(let id)? = GrokCLIOutput.parseStreamLine(
        #"{"type":"end","stopReason":"EndTurn","sessionId":"abc123","usage":{}}"#)
    else { return XCTFail("end") }
    XCTAssertEqual(id, "abc123")
    guard
      case .error("Not signed in.")? = GrokCLIOutput.parseStreamLine(
        #"{"type":"error","message":"Not signed in.\nmore"}"#)
    else { return XCTFail("error") }
    XCTAssertNil(GrokCLIOutput.parseStreamLine("not json"))
    XCTAssertNil(GrokCLIOutput.parseStreamLine(#"{"type":"text","data":""}"#))
  }

  // MARK: Where Grok joins the app

  func testRunnerReadsGrokOutput() {
    let runner = ChatCLIProcessRunner()
    let ok = runner.parseAssistant(
      tool: .grok,
      raw: #"{"text":"4","sessionId":"s","usage":{"input_tokens":3,"output_tokens":1}}"#)
    XCTAssertEqual(ok.text, "4")
    XCTAssertEqual(ok.usage?.output, 1)
    let signedOut = runner.parseAssistant(
      tool: .grok, raw: #"{"type":"error","message":"Not signed in."}"#)
    XCTAssertEqual(signedOut.text, "")
    guard
      case .textDelta("hi")? = runner.parseJSONLLine(
        tool: .grok, line: #"{"type":"text","data":"hi"}"#)
    else { return XCTFail("stream line") }
  }

  func testGrokIsAChatAndRecapProviderWithItsOwnSession() {
    XCTAssertTrue(DashboardChatProvider.grok.usesCLISession)
    XCTAssertEqual(DashboardChatProvider.fromStoredValue("grok"), .grok)
    XCTAssertTrue(DailyRecapProvider.allCases.contains(.grok))
    XCTAssertEqual(ChatCLITool.grok.providerID, .grok)
    XCTAssertEqual(CLITool(providerID: .grok), .grok)
    XCTAssertNil(CLITool(providerID: .local))
    XCTAssertEqual(ChatCLITool.grok.signInCommand, "grok login")
  }

  @MainActor
  func testMissingGrokSessionStartsANewOne() {
    XCTAssertTrue(ChatService.isMissingSessionError("Error: Session abc not found"))
    XCTAssertFalse(ChatService.isMissingSessionError("Not signed in."))
  }

  func testUsageIsLoggedPerCLI() {
    // Settings › AI usage groups by this name; all CLIs used to share "chat_cli".
    XCTAssertEqual(
      GrokProvider().makeCtx(batchId: nil, operation: "x", model: "m", startedAt: Date()).provider,
      "grok_cli")
    XCTAssertEqual(
      ClaudeProvider().makeCtx(batchId: nil, operation: "x", model: "m", startedAt: Date())
        .provider,
      "claude_cli")
  }

  func testGrokCardTurnsAreTextOnly() {
    XCTAssertTrue(GrokProvider.cardTurnsAreTextOnly)
    XCTAssertFalse(CodexProvider.cardTurnsAreTextOnly)
  }

  private func value(after flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
  }
}
