//
//  FocusShortcut.swift
//  Dayframe
//
//  Turns on a Focus when the day starts. macOS has no public API to set a Focus, so the
//  user makes a Shortcut with the "Set Focus" action once (e.g. "Work Focus"), and Start
//  of day runs it by name through /usr/bin/shortcuts.
//

import Foundation

enum FocusShortcut {
  static let suggestedName = "Work Focus"
  private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

  /// Shortcut names from `shortcuts list` (one per line).
  static func names(fromList output: String) -> [String] {
    output.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// The user's shortcuts, alphabetically. Empty if there are none or the tool fails.
  static func available() -> [String] {
    let result = runTool(["list"])
    return result.exitCode == 0 ? names(fromList: result.output).sorted() : []
  }

  /// Runs the shortcut; nil when it ran, otherwise what went wrong.
  static func run(_ name: String) -> String? {
    let result = runTool(["run", name])
    guard result.exitCode != 0 else { return nil }
    let reason = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    return reason.isEmpty ? "shortcuts exited with code \(result.exitCode)" : reason
  }

  private static func runTool(_ arguments: [String]) -> (exitCode: Int32, output: String) {
    let process = Process()
    process.executableURL = tool
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return (-1, error.localizedDescription)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }
}
