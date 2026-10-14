import Foundation

@MainActor
final class AppDeepLinkRouter {
  enum Action: String {
    case startRecording = "start-recording"
    case stopRecording = "stop-recording"
    case referral = "referral"
    /// dayframe://welcome-preview?variant=dailyWake plays a welcome preview, so its in-app frame
    /// rate can be measured from Terminal (`open …`, then `./logs.sh 5m welcome`).
    case welcomePreview = "welcome-preview"
    /// dayframe://notice?id=<id>: Briefing left a message in ~/Briefing/notices for the notch pill.
    case notice = "notice"

    init?(identifier: String) {
      switch identifier.lowercased() {
      case Self.startRecording.rawValue, "start", "resume":
        self = .startRecording
      case Self.stopRecording.rawValue, "stop", "pause":
        self = .stopRecording
      case Self.referral.rawValue, "claim", "r":
        self = .referral
      case Self.welcomePreview.rawValue:
        self = .welcomePreview
      case Self.notice.rawValue:
        self = .notice
      default:
        return nil
      }
    }
  }

  init() {}

  @discardableResult
  func handle(_ url: URL) -> Bool {
    guard let action = resolveAction(from: url) else {
      print("[DeepLink] Unsupported URL: \(url.absoluteString)")
      return false
    }

    perform(action, url: url)
    return true
  }

  private func resolveAction(from url: URL) -> Action? {
    // dayframe:// is Dayframe's own scheme. dayflow:// still works, but macOS may hand it to the
    // original Dayflow app when that is installed too, so Dayframe's own links use dayframe://.
    guard let scheme = url.scheme?.lowercased(), ["dayframe", "dayflow"].contains(scheme) else {
      return nil
    }

    var candidates: [String] = []
    if let host = url.host, !host.isEmpty {
      candidates.append(host)
    }

    let pathComponents = url.path
      .split(separator: "/")
      .map { String($0) }

    candidates.append(contentsOf: pathComponents)

    if candidates.isEmpty {
      if let actionItem = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name.lowercased() == "action" }),
        let value = actionItem.value, !value.isEmpty
      {
        candidates.append(value)
      }
    }

    guard let identifier = candidates.first else { return nil }
    return Action(identifier: identifier)
  }

  private func perform(_ action: Action, url: URL) {
    switch action {
    case .startRecording:
      startRecording()
    case .stopRecording:
      stopRecording()
    case .referral:
      saveReferralCode(from: url)
    case .welcomePreview:
      let variant = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "variant" }?.value
      WelcomeController.shared.preview(variant == "dailyWake" ? .dailyWake : .firstLaunch)
    case .notice:
      if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "id" })?.value
      {
        IslandController.shared.presentNotice(id: id)
      }
    }
  }

  private func startRecording() {
    guard RecordingControl.currentMode() != .active else {
      print("[DeepLink] Recording already active; ignoring start request")
      return
    }
    RecordingControl.start(reason: "deeplink")
  }

  private func stopRecording() {
    guard RecordingControl.currentMode() != .stopped else {
      print("[DeepLink] Recording already stopped; ignoring stop request")
      return
    }
    RecordingControl.stop(reason: "deeplink")
  }

  private func saveReferralCode(from url: URL) {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryCode = components?.queryItems?
      .first(where: { $0.name.lowercased() == "code" || $0.name.lowercased() == "ref" })?
      .value
    let pathCode = url.path
      .split(separator: "/")
      .map(String.init)
      .first(where: { $0.count >= 6 })
    guard let code = queryCode ?? pathCode else {
      print("[DeepLink] Referral link missing code")
      return
    }
    DayflowAuthManager.shared.setPendingReferralCode(code)
  }

}
