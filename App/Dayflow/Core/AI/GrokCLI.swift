//
//  GrokCLI.swift
//  Dayframe
//
//  How Dayframe runs xAI's Grok CLI headless, signed in with the user's own plan
//  (`grok login`; no API key). Two pure pieces, both unit-tested:
//  - GrokCLICommand builds the arguments for one turn.
//  - GrokCLIOutput reads what the CLI prints (`json` or `streaming-json`).
//
//  The prompt always goes through a private file (`--prompt-file`): the CLI doesn't read
//  stdin, and a command-line argument is visible to every process on the Mac.
//

import Foundation

enum GrokCLI {
  /// The installer's location, used when it exists; otherwise `grok` from the login shell's PATH.
  static func executable(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> String {
    let installed = home.appendingPathComponent(".grok/bin/grok").path
    return fileManager.isExecutableFile(atPath: installed) ? installed : "grok"
  }

  /// Writes the prompt to an owner-only file next to the run. Delete it when the run ends.
  static func writePromptFile(_ prompt: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("grok-prompt-\(UUID().uuidString).txt")
    try Data(prompt.utf8).write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return url
  }
}

/// One headless Grok turn.
struct GrokCLICommand: Equatable {
  /// What the turn may do. Text turns (cards, recaps, transcripts) get no tools at all;
  /// chat gets only the shell, to query the timeline with sqlite3 as Claude and Codex chat do.
  enum Access: Equatable {
    case textOnly
    case shell
  }

  /// Every built-in tool except the shell, plus subagents.
  static let toolsExceptShell =
    "search_replace,read_file,grep,list_dir,todo_write,task,web_search,web_fetch,Agent"

  var promptFile: String
  var model: String?
  var reasoningEffort: String?
  var resumeSessionID: String?
  var streaming = false
  var access = Access.textOnly

  func arguments() -> [String] {
    var args = ["--prompt-file", promptFile]
    args += ["--output-format", streaming ? "streaming-json" : "json"]
    if let model, !model.isEmpty { args += ["-m", model] }
    if let reasoningEffort, !reasoningEffort.isEmpty {
      args += ["--reasoning-effort", reasoningEffort]
    }
    if let resumeSessionID { args += ["-r", resumeSessionID] }
    args += [
      "--disable-web-search", "--no-subagents", "--no-memory", "--no-plan", "--no-auto-update",
    ]
    switch access {
    case .textOnly:
      args += [
        "--max-turns", "1", "--disallowed-tools", "run_terminal_cmd," + Self.toolsExceptShell,
      ]
    case .shell:
      args += ["--disallowed-tools", Self.toolsExceptShell, "--always-approve"]
    }
    return args
  }
}

/// What the Grok CLI prints.
enum GrokCLIOutput {
  struct Envelope {
    var text: String
    var sessionID: String?
    var usage: TokenUsage?
    var error: String?
  }

  private struct Line: Decodable {
    struct Usage: Decodable {
      var inputTokens: Int?
      var cacheReadInputTokens: Int?
      var outputTokens: Int?

      enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
      }
    }

    var type: String?
    var text: String?
    var data: String?
    var message: String?
    var sessionId: String?
    var usage: Usage?
  }

  /// The single object `--output-format json` prints (the last JSON line of stdout).
  static func parseEnvelope(_ stdout: String) -> Envelope? {
    let last = stdout.split(whereSeparator: \.isNewline).last { $0.hasPrefix("{") }
    guard let last, let line = decode(String(last)) else { return nil }
    if line.type == "error" {
      return Envelope(text: "", error: firstLine(line.message ?? "Grok CLI error"))
    }
    return Envelope(text: line.text ?? "", sessionID: line.sessionId, usage: usage(line.usage))
  }

  /// One line of `--output-format streaming-json`. The session ID only arrives in the final
  /// `end` line, which carries no text: the caller collects the `text` deltas.
  static func parseStreamLine(_ raw: String) -> ChatStreamEvent? {
    guard let line = decode(raw) else { return nil }
    switch line.type {
    case "text":
      return line.data.flatMap { $0.isEmpty ? nil : .textDelta($0) }
    case "thought":
      return line.data.flatMap { $0.isEmpty ? nil : .thinking($0) }
    case "end":
      return line.sessionId.map { .sessionStarted(id: $0) }
    case "error":
      return .error(firstLine(line.message ?? "Grok CLI error"))
    default:
      return nil
    }
  }

  /// True when the CLI's sign-in has expired (it lasts 7 days); the fix is `grok login`.
  static func isSignInError(_ message: String) -> Bool {
    let lower = message.lowercased()
    return lower.contains("not signed in") || lower.contains("grok login")
  }

  private static func decode(_ raw: String) -> Line? {
    try? JSONDecoder().decode(Line.self, from: Data(raw.utf8))
  }

  private static func usage(_ u: Line.Usage?) -> TokenUsage? {
    guard let u else { return nil }
    // Same split as Claude's envelope: uncached input, cached input, output.
    return TokenUsage(
      input: u.inputTokens ?? 0, cachedInput: u.cacheReadInputTokens ?? 0,
      output: u.outputTokens ?? 0)
  }

  private static func firstLine(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
  }
}
