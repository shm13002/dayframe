//
//  GrokMCPRegistration.swift
//  Dayframe
//
//  Lets the Grok CLI read the timeline: registers Dayframe's MCP server ("dayflow") with
//  Grok's own commands, so Dayframe never edits ~/.grok/config.toml itself.
//    grok mcp add dayflow --scope user -- <bundled dayflow> mcp
//    grok mcp remove dayflow --scope user
//    grok mcp list --json   → [{"name":"dayflow","command":…,"enabled":true,"scope":"user"}]
//  Each takes about 0.2 s (Grok 0.2.99).
//

import Foundation

struct GrokMCPRegistration {
  enum Status: Equatable {
    case notInstalled
    case available
    /// Registered, but for another app path (the app moved) or switched off.
    case stale
    case connected
  }

  typealias CommandRunner = (_ executable: String, _ arguments: [String]) -> CommandResult

  struct CommandResult: Equatable {
    var exitCode: Int32
    var output: String
  }

  private struct Server: Decodable {
    var name: String
    var command: String?
    var enabled: Bool?
  }

  let cliPath: String
  var executable: () -> String? = { GrokProvider.isInstalled ? GrokCLI.executable() : nil }
  var run: CommandRunner = GrokMCPRegistration.runProcess

  func status() -> Status {
    guard let grok = executable() else { return .notInstalled }
    let listed = run(grok, ["mcp", "list", "--json"])
    guard listed.exitCode == 0,
      let servers = try? JSONDecoder().decode([Server].self, from: Data(listed.output.utf8)),
      let entry = servers.first(where: { $0.name == "dayflow" })
    else { return .available }
    return entry.command == cliPath && entry.enabled != false ? .connected : .stale
  }

  /// Adds or refreshes the entry. Returns nil when connected, or why it isn't.
  func connect() -> String? {
    guard let grok = executable() else {
      return String(localized: "The Grok CLI isn't installed on this Mac.")
    }
    let added = run(grok, ["mcp", "add", "dayflow", "--scope", "user", "--", cliPath, "mcp"])
    guard added.exitCode == 0 else {
      let reason = added.output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
      return String(localized: "Grok couldn't add the connection: \(reason)")
    }
    return status() == .connected
      ? nil
      : String(localized: "Grok saved the connection, but Dayframe couldn't verify it.")
  }

  func disconnect() {
    guard let grok = executable(), status() != .available else { return }
    _ = run(grok, ["mcp", "remove", "dayflow", "--scope", "user"])
  }

  /// At launch: if the app moved since Grok was connected, point Grok at this copy.
  func repairIfStale() {
    if status() == .stale { _ = connect() }
  }

  static func runProcess(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    // A neutral folder, so a project's own .grok/config.toml can't change the answer.
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return CommandResult(exitCode: -1, output: error.localizedDescription)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(
      exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
  }
}
