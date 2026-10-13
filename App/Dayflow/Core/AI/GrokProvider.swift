//
//  GrokProvider.swift
//  Dayframe
//
//  xAI's Grok as a timeline, Chat and recap provider, through the Grok CLI signed in with
//  the user's own plan (ADR 0003; `grok login`, no API key).
//
//  Cards, Chat and text use the shared CLI code (StreamingCardWriter, CLITextProvider);
//  only the models are Grok's. Transcription differs: Grok's headless mode takes no images,
//  so it reads the frames' on-screen text (Apple Vision OCR) instead of the pictures.
//

import Foundation

final class GrokProvider: AgentCLISupporting {
  let providerID: LLMProviderID = .grok
  var cliTool: ChatCLITool { .grok }
  let runner = ChatCLIProcessRunner()
  let config = ChatCLIConfigManager.shared

  init() {
    config.ensureWorkingDirectory()
  }

  /// True when the Grok CLI is installed (`~/.grok/bin/grok`, or `grok` on the login shell's PATH).
  static var isInstalled: Bool {
    GrokCLI.executable() != "grok" || LoginShellRunner.isInstalled("grok")
  }

  /// Transcripts and cards are routine and frequent: the main model at low effort.
  static func transcriptionModelConfiguration() -> (model: String, reasoningEffort: String?) {
    (model: "grok-4.5", reasoningEffort: "low")
  }
}

extension GrokProvider: StreamingCardWriter {
  static func activityCardModelConfiguration() -> (model: String, reasoningEffort: String?) {
    (model: "grok-4.5", reasoningEffort: "low")
  }

  /// Cards are written from the prompt alone: no shell, files or web.
  static let cardTurnsAreTextOnly = true
}

extension GrokProvider: CLITextProvider {
  static let chatModel: (model: String, reasoningEffort: String?) = ("grok-4.5", "medium")
  static let textModel: (model: String, reasoningEffort: String?) = ("grok-4.5", "medium")

  /// Grok's JSON output carries no separate reasoning text.
  func thinking(from run: ChatCLIRunResult) -> String? { nil }
}
