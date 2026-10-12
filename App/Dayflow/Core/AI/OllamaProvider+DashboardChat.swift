import Foundation

// MARK: - Dashboard Chat (local model: Qwen on Ollama, OpenAI-style function calling)
//
// Dayframe: Chat used to need Claude Code, the Codex CLI or a Gemini key. This runs the
// same fetchTimeline / fetchObservations tool loop as Gemini against the model already
// used for the timeline. Ollama gives Qwen a ~4k-token window, so the history is trimmed
// and tool results are compact text (DashboardChatTools.compactResult). num_ctx is never
// sent: a different context size would make Ollama reload the model and stall the timeline.

/// Collects one streamed /v1/chat/completions response: text deltas plus tool calls whose
/// name and arguments arrive split across chunks (keyed by `index`).
struct LocalChatStreamAccumulator {
  struct ToolCall: Equatable {
    var id: String
    var name: String
    var arguments: String
  }

  private(set) var content = ""
  private(set) var toolCallsByIndex: [Int: ToolCall] = [:]
  private(set) var isDone = false

  var toolCalls: [ToolCall] {
    toolCallsByIndex.keys.sorted().compactMap { toolCallsByIndex[$0] }
      .filter { !$0.name.isEmpty }
  }

  /// Feeds one SSE line. Returns the text delta it carried, if any.
  mutating func consume(line: String) throws -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("data:") else { return nil }
    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if payload == "[DONE]" {
      isDone = true
      return nil
    }
    guard let data = payload.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    if let error = object["error"] as? [String: Any] {
      throw NSError(
        domain: "LocalDashboardChat", code: 2,
        userInfo: [NSLocalizedDescriptionKey: error["message"] as? String ?? "Model error"])
    }

    guard let choice = (object["choices"] as? [[String: Any]])?.first,
      let delta = choice["delta"] as? [String: Any]
    else { return nil }

    for (position, fragment) in (delta["tool_calls"] as? [[String: Any]] ?? []).enumerated() {
      let index = fragment["index"] as? Int ?? position
      var call = toolCallsByIndex[index] ?? ToolCall(id: "", name: "", arguments: "")
      if let id = fragment["id"] as? String, !id.isEmpty { call.id = id }
      if let function = fragment["function"] as? [String: Any] {
        if let name = function["name"] as? String, !name.isEmpty { call.name = name }
        if let arguments = function["arguments"] as? String { call.arguments += arguments }
      }
      toolCallsByIndex[index] = call
    }

    if let text = delta["content"] as? String, !text.isEmpty {
      content += text
      return text
    }
    return nil
  }
}

extension OllamaProvider {
  static let dashboardChatMaxToolRounds = 6
  static let dashboardChatMaxHistoryTurns = 6

  func generateDashboardChatStreaming(
    systemInstruction: String,
    history: [DashboardChatTurn]
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await runLocalDashboardChatLoop(
            systemInstruction: systemInstruction,
            history: history,
            continuation: continuation
          )
          continuation.finish()
        } catch {
          let message = Self.friendlyLocalChatError(error)
          continuation.yield(.error(message))
          continuation.finish(
            throwing: NSError(
              domain: "LocalDashboardChat", code: 1,
              userInfo: [NSLocalizedDescriptionKey: message]))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func localChatMessages(
    systemInstruction: String,
    history: [DashboardChatTurn]
  ) -> [[String: Any]] {
    var recent = Array(history.suffix(dashboardChatMaxHistoryTurns))
    while let first = recent.first, first.role != .user, recent.count > 1 {
      recent.removeFirst()
    }
    var messages: [[String: Any]] = [["role": "system", "content": systemInstruction]]
    messages += recent.map { ["role": $0.role.rawValue, "content": $0.content] }
    return messages
  }

  private func runLocalDashboardChatLoop(
    systemInstruction: String,
    history: [DashboardChatTurn],
    continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
  ) async throws {
    var messages = Self.localChatMessages(systemInstruction: systemInstruction, history: history)
    let tools = DashboardChatTools()

    for _ in 0..<Self.dashboardChatMaxToolRounds {
      let turn = try await streamLocalDashboardTurn(messages: messages, continuation: continuation)
      let calls = turn.toolCalls
      if calls.isEmpty {
        continuation.yield(.complete(text: turn.content))
        return
      }

      let assistantMessage: [String: Any] = [
        "role": "assistant",
        "content": turn.content,
        "tool_calls": calls.enumerated().map { offset, call in
          [
            "id": call.id.isEmpty ? "call_\(offset)" : call.id,
            "type": "function",
            "function": ["name": call.name, "arguments": call.arguments],
          ] as [String: Any]
        },
      ]
      messages.append(assistantMessage)

      for (offset, call) in calls.enumerated() {
        let argsData = call.arguments.data(using: .utf8) ?? Data()
        let args =
          (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
        let argsText = call.arguments.isEmpty ? "{}" : call.arguments
        continuation.yield(.toolStart(command: "\(call.name) \(argsText)"))
        let result = tools.execute(name: call.name, args: args)
        let summary = result["summary"] as? String ?? "Tool finished."
        continuation.yield(.toolEnd(output: summary, exitCode: result["error"] != nil ? 1 : 0))
        messages.append([
          "role": "tool",
          "tool_call_id": call.id.isEmpty ? "call_\(offset)" : call.id,
          "content": DashboardChatTools.compactResult(name: call.name, result: result),
        ])
      }
    }

    throw NSError(
      domain: "LocalDashboardChat", code: 901,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Qwen kept asking for more data. Try a narrower question, like one day."
      ])
  }

  private func streamLocalDashboardTurn(
    messages: [[String: Any]],
    continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
  ) async throws -> LocalChatStreamAccumulator {
    guard let url = LocalEndpointUtilities.chatCompletionsURL(baseURL: endpoint) else {
      throw NSError(
        domain: "LocalDashboardChat", code: 15,
        userInfo: [NSLocalizedDescriptionKey: "Invalid local endpoint URL"])
    }

    var body: [String: Any] = [
      "model": savedModelId,
      "messages": messages,
      "tools": DashboardChatTools.openAIToolDeclarations(),
      "tool_choice": "auto",
      "stream": true,
      "temperature": 0.3,
      "max_tokens": 1200,
    ]
    // Same rule as makeChatURLRequest: Qwen on Ollama thinks unless told not to.
    if localEngine == "ollama" || endpoint.contains(":11434") {
      body["reasoning_effort"] = "none"
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyAuthorizationHeader(to: &request)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.timeoutInterval = defaultTimeoutInterval

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      var errorBody = ""
      for try await line in bytes.lines {
        errorBody += line
        if errorBody.count > 2000 { break }
      }
      throw NSError(
        domain: "LocalDashboardChat", code: http.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey:
            "The local model returned HTTP \(http.statusCode). \(errorBody.prefix(300))"
        ])
    }

    var accumulator = LocalChatStreamAccumulator()
    for try await line in bytes.lines {
      try Task.checkCancellation()
      if let delta = try accumulator.consume(line: line) {
        continuation.yield(.textDelta(delta))
      }
      if accumulator.isDone { break }
    }
    return accumulator
  }

  static func friendlyLocalChatError(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
        NSURLErrorNetworkConnectionLost:
        return
          "Qwen isn't running. Open Ollama (Dayframe also reopens it within 2 minutes)."
      case NSURLErrorTimedOut:
        return "Qwen took too long to answer. It may be busy with the timeline; try again."
      default:
        break
      }
    }
    return error.localizedDescription
  }
}

// MARK: - Availability

enum LocalChatAvailability {
  /// True when the saved local endpoint answers and lists the saved model. Ollama is asked
  /// via /api/tags; LM Studio and custom servers via the OpenAI-style /v1/models.
  static func isReady(timeout: TimeInterval = 2) async -> Bool {
    let defaults = UserDefaults.standard
    let base =
      defaults.string(forKey: "llmLocalBaseURL")?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let endpoint = base.isEmpty ? "http://localhost:11434" : base
    let modelId = defaults.string(forKey: "llmLocalModelId") ?? ""
    let engine = defaults.string(forKey: "llmLocalEngine") ?? "ollama"
    let isOllama = engine == "ollama" || endpoint.contains(":11434")

    var root = endpoint
    while root.hasSuffix("/") { root.removeLast() }
    if root.hasSuffix("/v1") { root.removeLast(3) }
    guard let url = URL(string: root + (isOllama ? "/api/tags" : "/v1/models")) else {
      return false
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200
    else { return false }
    guard !modelId.isEmpty else { return true }

    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let names: [String]
    if isOllama {
      names = (object?["models"] as? [[String: Any]] ?? []).compactMap {
        ($0["name"] as? String) ?? ($0["model"] as? String)
      }
    } else {
      names = (object?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }
    return names.contains(modelId) || names.contains("\(modelId):latest")
  }
}
