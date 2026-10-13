import Foundation

extension GrokProvider {
  // MARK: - Transcription from on-screen text

  /// Grok's headless mode takes no images, so each sampled frame is described by its time and
  /// the text Apple Vision read on it (the same OCR and app hints Claude's input carries).
  func transcribeScreenshots(
    _ screenshots: [Screenshot], batchStartTime: Date, batchId: Int64?
  ) async throws -> (observations: [Observation], log: LLMCall) {
    guard !screenshots.isEmpty else {
      throw NSError(
        domain: "GrokProvider", code: -96,
        userInfo: [NSLocalizedDescriptionKey: "No screenshots to transcribe"])
    }
    let callStart = Date()
    let (model, effort) = Self.transcriptionModelConfiguration()
    func ctx(_ attempt: Int) -> LLMCallContext {
      makeCtx(
        batchId: batchId, operation: "transcribe_screenshots", model: model,
        startedAt: callStart, attempt: attempt)
    }

    let input: ClaudePreparedTranscriptionInput
    do {
      input = try await ClaudeTranscriptionInputBuilder().prepare(screenshots: screenshots)
    } catch {
      logFailure(ctx: ctx(1), finishedAt: Date(), error: error)
      throw error
    }
    defer { input.cleanup() }

    let durationSeconds = max(1, Int(input.durationSeconds.rounded()))
    let duration = formatSeconds(TimeInterval(durationSeconds))
    let basePrompt =
      buildScreenshotTranscriptionPrompt(
        numFrames: input.selectedScreenshots.count, duration: duration,
        startTime: "00:00:00", endTime: duration,
        frameTiming: "Each one's time is in the list below.")
      + Self.textOnlyEvidence(input.metadataJSON)
    var prompt = basePrompt
    var lastRun: ChatCLIRunResult?
    var lastError: Error = NSError(
      domain: "GrokProvider", code: -99,
      userInfo: [NSLocalizedDescriptionKey: "No observations could be created from segments."])

    for attempt in 1...3 {
      do {
        let turnPrompt = prompt
        let run = try await Task.detached {
          try self.runAndScrub(
            prompt: turnPrompt, model: model, reasoningEffort: effort, disableTools: true)
        }.value
        lastRun = run
        guard run.exitCode == 0 else { throw Self.cliError(run) }
        let segments = try parseSegments(from: run.stdout, stderr: run.stderr)
        if let problem = validateSegments(segments, duration: TimeInterval(durationSeconds)) {
          throw NSError(
            domain: "GrokProvider", code: -98, userInfo: [NSLocalizedDescriptionKey: problem])
        }
        let observations = observations(
          from: segments, durationSeconds: durationSeconds, batchStartTime: batchStartTime,
          batchId: batchId, model: model)
        guard !observations.isEmpty else { throw lastError }
        logSuccess(
          ctx: ctx(attempt), finishedAt: run.finishedAt, stdout: run.stdout, stderr: run.stderr,
          responseHeaders: tokenHeaders(from: run.usage))
        let log = makeLLMCall(
          start: callStart, end: run.finishedAt, input: turnPrompt, output: run.stdout)
        return (observations, log)
      } catch {
        lastError = error
        // Retrying can't fix an expired sign-in; the user runs `grok login`.
        if GrokCLIOutput.isSignInError(error.localizedDescription) { break }
        prompt =
          basePrompt + "\n\nPREVIOUS ATTEMPT FAILED - FIX THE FOLLOWING:\n"
          + error.localizedDescription + "\n\nReturn JSON only."
      }
    }

    logFailure(
      ctx: ctx(3), finishedAt: lastRun?.finishedAt ?? Date(), error: lastError,
      stdout: lastRun?.stdout, stderr: lastRun?.stderr, run: lastRun)
    throw lastError
  }

  /// The error for a CLI run that failed: the CLI's own first line (e.g. "Not signed in.").
  static func cliError(_ run: ChatCLIRunResult) -> NSError {
    let message =
      run.stderr.split(whereSeparator: \.isNewline).first
      .map { String($0).replacingOccurrences(of: "Error: ", with: "") }
      ?? "Grok CLI exited with code \(run.exitCode)"
    return NSError(
      domain: "GrokProvider", code: Int(run.exitCode),
      userInfo: [NSLocalizedDescriptionKey: message])
  }

  private static func textOnlyEvidence(_ metadataJSON: String) -> String {
    """


    You can't see the screenshots. For each one you get its time and the text Apple Vision read on the screen (OCR), plus an app hint when one was clear. Work out what the person was doing from that text: name the app, the document, page or conversation, and the task. OCR is fallible; when the text is too thin to tell, say only what is certain.
    Screenshots: \(metadataJSON)

    Send exactly one bare JSON object. The first character of the response must be { and the last must be }; no preamble and no Markdown fence.
    """
  }
}
