import Foundation

extension GeminiDirectProvider {
  func describeDashboardFunctionCall(_ call: DashboardFunctionCall) -> String {
    let argsText =
      (try? JSONSerialization.data(withJSONObject: call.args))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return "\(call.name) \(argsText)"
  }

  func dashboardFunctionCallFingerprint(_ call: DashboardFunctionCall) -> String {
    let argsData = try? JSONSerialization.data(withJSONObject: call.args, options: [.sortedKeys])
    let argsString = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return "\(call.name)|\(argsString)"
  }

  func executeDashboardFunction(_ call: DashboardFunctionCall) -> [String: Any] {
    var tools = DashboardChatTools()
    tools.timelinePayloadSoftLimitBytes = Self.dashboardChatTimelinePayloadSoftLimitBytes
    return tools.execute(name: call.name, args: call.args)
  }
}
