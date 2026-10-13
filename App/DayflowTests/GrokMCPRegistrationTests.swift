import XCTest

@testable import Dayflow

/// Connecting the Grok CLI to Dayframe's MCP server, against a fake `grok` that keeps an
/// in-memory server list (the JSON shape is Grok 0.2.99's `grok mcp list --json`).
final class GrokMCPRegistrationTests: XCTestCase {
  private let cliPath = "/Applications/Dayframe.app/Contents/Helpers/dayflow"

  private final class FakeGrok {
    var servers: [[String: Any]] = []
    var calls: [[String]] = []
    var failAdd = false

    func run(_ executable: String, _ arguments: [String]) -> GrokMCPRegistration.CommandResult {
      calls.append(arguments)
      switch Array(arguments.prefix(2)) {
      case ["mcp", "list"]:
        let data = try! JSONSerialization.data(withJSONObject: servers)
        return .init(exitCode: 0, output: String(decoding: data, as: UTF8.self))
      case ["mcp", "add"]:
        if failAdd { return .init(exitCode: 1, output: "error: config is read-only\nmore") }
        let command = arguments[arguments.firstIndex(of: "--")! + 1]
        servers.removeAll { $0["name"] as? String == arguments[2] }
        servers.append(["name": arguments[2], "command": command, "enabled": true, "scope": "user"])
        return .init(exitCode: 0, output: "Added")
      case ["mcp", "remove"]:
        servers.removeAll { $0["name"] as? String == arguments[2] }
        return .init(exitCode: 0, output: "Removed")
      default:
        return .init(exitCode: 2, output: "unknown")
      }
    }
  }

  private func registration(_ fake: FakeGrok, installed: Bool = true) -> GrokMCPRegistration {
    var registration = GrokMCPRegistration(cliPath: cliPath)
    registration.executable = { installed ? "/fake/grok" : nil }
    registration.run = fake.run
    return registration
  }

  func testStatusFollowsGrokOwnList() {
    let fake = FakeGrok()
    XCTAssertEqual(registration(fake, installed: false).status(), .notInstalled)
    XCTAssertEqual(registration(fake).status(), .available)
    fake.servers = [["name": "dayflow", "command": cliPath, "enabled": true]]
    XCTAssertEqual(registration(fake).status(), .connected)
    fake.servers = [["name": "dayflow", "command": "/old/Dayframe.app/Contents/Helpers/dayflow"]]
    XCTAssertEqual(registration(fake).status(), .stale)
    fake.servers = [["name": "dayflow", "command": cliPath, "enabled": false]]
    XCTAssertEqual(registration(fake).status(), .stale)
  }

  func testConnectAddsOnlyOurEntryAtUserScope() {
    let fake = FakeGrok()
    fake.servers = [["name": "github", "command": "/usr/local/bin/gh-mcp"]]
    XCTAssertNil(registration(fake).connect())
    XCTAssertTrue(
      fake.calls.contains(["mcp", "add", "dayflow", "--scope", "user", "--", cliPath, "mcp"]))
    XCTAssertEqual(fake.servers.count, 2)  // the user's own server is untouched
    XCTAssertEqual(registration(fake).status(), .connected)
  }

  func testConnectReportsGrokError() {
    let fake = FakeGrok()
    fake.failAdd = true
    XCTAssertEqual(
      registration(fake).connect(), "Grok couldn't add the connection: error: config is read-only")
  }

  func testDisconnectRemovesOnlyWhenPresentAndRepairFixesAMovedApp() {
    let fake = FakeGrok()
    registration(fake).disconnect()
    XCTAssertFalse(fake.calls.contains { $0.starts(with: ["mcp", "remove"]) })

    fake.servers = [["name": "dayflow", "command": "/old/path/dayflow"]]
    registration(fake).repairIfStale()
    XCTAssertEqual(registration(fake).status(), .connected)

    registration(fake).disconnect()
    XCTAssertTrue(fake.calls.contains(["mcp", "remove", "dayflow", "--scope", "user"]))
    XCTAssertEqual(registration(fake).status(), .available)
  }

  func testGrokIsOfferedAsAnAgentClient() {
    XCTAssertTrue(AgentClient.allCases.contains(.grok))
    XCTAssertEqual(AgentClient.grok.displayName, "Grok CLI")
    XCTAssertEqual(AgentClient.allCases.first, .codex)
  }
}
