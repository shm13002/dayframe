import Foundation

/// Chat and one-off text turns for the CLI providers (Codex, Claude, Grok). Everything is
/// shared; each provider only names its models and where the CLI prints its reasoning.
protocol CLITextProvider: AgentCLISupporting {
  /// The model for Chat, which streams and resumes its session.
  static var chatModel: (model: String, reasoningEffort: String?) { get }
  /// The model for one-off text such as summaries.
  static var textModel: (model: String, reasoningEffort: String?) { get }
  /// The model's reasoning, when the CLI printed it.
  func thinking(from run: ChatCLIRunResult) -> String?
}

extension CodexProvider: CLITextProvider {
  static let chatModel: (model: String, reasoningEffort: String?) = ("gpt-5.6-luna", "low")
  static let textModel: (model: String, reasoningEffort: String?) = ("gpt-5.2", "high")

  func thinking(from run: ChatCLIRunResult) -> String? {
    runner.parseThinkingFromOutput(run.rawStdout)
  }
}

extension ClaudeProvider: CLITextProvider {
  static let chatModel: (model: String, reasoningEffort: String?) = ("sonnet", nil)
  static let textModel: (model: String, reasoningEffort: String?) = ("sonnet", "high")

  func thinking(from run: ChatCLIRunResult) -> String? {
    parseThinkingFromStderr(run.stderr)
  }
}

extension CLITextProvider {
  private var errorDomain: String { String(describing: Self.self) }

  func generateChatStreaming(prompt: String, sessionId: String? = nil) -> AsyncThrowingStream<
    ChatStreamEvent, Error
  > {
    runner.runStreaming(
      tool: cliTool,
      prompt: prompt,
      workingDirectory: config.workingDirectory,
      model: Self.chatModel.model,
      reasoningEffort: Self.chatModel.reasoningEffort,
      sessionId: sessionId
    )
  }

  func generateTextStreaming(prompt: String) -> AsyncThrowingStream<String, Error> {
    let stream = generateChatStreaming(prompt: prompt)
    let domain = errorDomain
    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await event in stream {
            switch event {
            case .textDelta(let chunk):
              continuation.yield(chunk)
            case .error(let message):
              continuation.finish(
                throwing: NSError(
                  domain: domain,
                  code: -1,
                  userInfo: [NSLocalizedDescriptionKey: message]
                ))
              return
            default:
              break
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  func generateText(prompt: String) async throws -> (text: String, log: LLMCall) {
    try await generateText(
      prompt: prompt,
      model: Self.textModel.model,
      reasoningEffort: Self.textModel.reasoningEffort,
      disableTools: false
    )
  }

  func generateText(
    prompt: String,
    model: String,
    reasoningEffort: String? = nil,
    disableTools: Bool = true
  ) async throws -> (text: String, log: LLMCall) {
    let callStart = Date()
    let ctx = makeCtx(
      batchId: nil, operation: "generateText", model: model, startedAt: callStart)

    let run: ChatCLIRunResult
    do {
      run = try await Task.detached {
        try self.runAndScrub(
          prompt: prompt,
          model: model,
          reasoningEffort: reasoningEffort,
          disableTools: disableTools
        )
      }.value
    } catch {
      let nsErr = error as NSError
      let partialOut = nsErr.userInfo["partialStdout"] as? String
      let partialErr = nsErr.userInfo["partialStderr"] as? String
      logFailure(
        ctx: ctx, finishedAt: Date(), error: error, stdout: partialOut, stderr: partialErr)
      throw error
    }

    guard run.exitCode == 0 else {
      let errorMessage = run.stderr.isEmpty ? "CLI exited with code \(run.exitCode)" : run.stderr
      let error = NSError(
        domain: errorDomain, code: Int(run.exitCode),
        userInfo: [NSLocalizedDescriptionKey: errorMessage])
      logFailure(
        ctx: ctx, finishedAt: run.finishedAt, error: error, stdout: run.stdout, stderr: run.stderr,
        run: run)
      throw error
    }

    logSuccess(
      ctx: ctx, finishedAt: run.finishedAt, stdout: run.stdout, stderr: run.stderr,
      responseHeaders: tokenHeaders(from: run.usage))

    let log = makeLLMCall(start: callStart, end: run.finishedAt, input: prompt, output: run.stdout)
    let text = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if let thinking = thinking(from: run), !thinking.isEmpty {
      return ("---THINKING---\n\(thinking)\n---END_THINKING---\n\(text)", log)
    }
    return (text, log)
  }
}
