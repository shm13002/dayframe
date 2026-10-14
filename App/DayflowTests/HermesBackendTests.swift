import XCTest

@testable import Dayflow

final class HermesBackendTests: XCTestCase {
  private let home = "/Users/me"

  private func locate(
    env: [String: String] = [:], files: Set<String> = [], executables: Set<String> = []
  ) -> HermesLocator.Launch? {
    HermesLocator.locate(
      environment: env, home: home, isFile: { files.contains($0) },
      isExecutable: { executables.contains($0) })
  }

  func testManagedInstallWithLauncherWins() {
    let root = "/Users/me/.hermes/hermes-agent"
    let launch = locate(
      files: [root + "/hermes_cli/subcommands/dashboard.py"],
      executables: [
        root + "/.hermes/bin/hermes", root + "/venv/bin/python", "/opt/homebrew/bin/hermes",
      ])
    XCTAssertEqual(launch?.command, [root + "/.hermes/bin/hermes"])
    XCTAssertEqual(launch?.root, root)
  }

  func testOldLayoutRunsTheModuleWithTheVenvPython() {
    let root = "/Users/me/.hermes/hermes-agent"
    let launch = locate(
      files: [root + "/hermes_cli/subcommands/dashboard.py"],
      executables: [root + "/venv/bin/python"])
    XCTAssertEqual(launch?.command, [root + "/venv/bin/python", "-m", "hermes_cli.main"])
  }

  func testCheckoutWithoutServeIsSkippedForPath() {
    let root = "/Users/me/.hermes/hermes-agent"
    let launch = locate(
      env: ["PATH": "/usr/bin"], files: [],
      executables: [root + "/.hermes/bin/hermes", "/Users/me/.local/bin/hermes"])
    XCTAssertEqual(launch?.command, ["/Users/me/.local/bin/hermes"])
    XCTAssertNil(launch?.root)
  }

  func testOverrideAndCustomHermesHome() {
    let files: Set<String> = [
      "/dev/hermes/hermes_cli/subcommands/dashboard.py",
      "/custom/hermes-agent/hermes_cli/subcommands/dashboard.py",
    ]
    let executables: Set<String> = [
      "/dev/hermes/.hermes/bin/hermes", "/custom/hermes-agent/.hermes/bin/hermes",
    ]
    XCTAssertEqual(
      locate(env: ["JARVIS_HERMES_ROOT": "/dev/hermes"], files: files, executables: executables)?
        .root,
      "/dev/hermes")
    XCTAssertEqual(
      locate(env: ["HERMES_HOME": "/custom"], files: files, executables: executables)?.root,
      "/custom/hermes-agent")
  }

  func testNothingInstalled() {
    XCTAssertNil(locate(env: ["PATH": "/usr/bin:/bin"]))
  }

  func testReadyLine() {
    XCTAssertEqual(HermesReadyLine.port(in: "HERMES_BACKEND_READY port=8123\n"), 8123)
    XCTAssertEqual(HermesReadyLine.port(in: "  HERMES_DASHBOARD_READY port=9 "), 9)
    XCTAssertNil(HermesReadyLine.port(in: "HERMES_BACKEND_READY port=70000"))
    XCTAssertNil(HermesReadyLine.port(in: "INFO uvicorn running on port=8123"))
    XCTAssertNil(HermesReadyLine.port(in: "HERMES_BACKEND_READY port=12ab"))
  }

  func testRestartBackoffGivesUpAfterFourTries() {
    XCTAssertEqual(HermesRestartPolicy.delay(afterFailures: 0), .seconds(1))
    XCTAssertEqual(HermesRestartPolicy.delay(afterFailures: 3), .seconds(15))
    XCTAssertNil(HermesRestartPolicy.delay(afterFailures: 4))
  }

  func testLineBufferKeepsTheUnfinishedTail() {
    var buffer = LineBuffer()
    XCTAssertEqual(buffer.push("one\r\ntw"), ["one"])
    XCTAssertEqual(buffer.push("o\nthree"), ["two"])
    XCTAssertEqual(buffer.push("\n"), ["three"])
  }
}

final class JarvisAuditEntryTests: XCTestCase {
  func testNewestFirstWithToolSummaryAndDecision() {
    let log = """
      {"ts": "2026-10-14T12:01:02-04:00", "tool": "system_info", "tier": "read", "decision": "auto", "ok": true, "summary": "system facts"}
      not json
      {"ts": "2026-10-14T12:05:00-04:00", "tool": "system_files", "tier": "mutate", "decision": "denied", "ok": false, "summary": "move a.pdf"}
      """
    let entries = JarvisAuditEntry.parse(log, limit: 10)
    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries[0].line, "system_files: move a.pdf")
    XCTAssertEqual(entries[0].decision, "denied")
    XCTAssertFalse(entries[0].ok)
    XCTAssertFalse(entries[0].time.isEmpty)
    XCTAssertEqual(entries[1].line, "system_info: system facts")
  }
}
