//
//  JarvisCoordinator.swift
//  Jarvis
//
//  Ties Jarvis together: the Hermes backend, the one Jarvis page (a WKWebView that lives for the
//  whole app run, so the conversation and its WebSocket survive tab switches and ⌥Space works
//  from anywhere), the voice, the listener and the notch eyes.
//
//  The page is Web/src/jarvis, built into Jarvis/Resources/jarvis.html and loaded from disk:
//  Hermes trusts WebSocket connections from non-web origins and checks the session token.
//

import AppKit
import Combine
import Foundation
import WebKit
import os.log

/// What Jarvis is doing, for the notch eyes.
enum JarvisPresence: Equatable {
  case idle
  case listening
  case thinking
  case speaking
}

@MainActor
final class JarvisCoordinator: NSObject, ObservableObject {
  static let shared = JarvisCoordinator()

  enum Keys {
    static let brain = "dayframeJarvisBrain"
    static let enabled = "dayframeJarvisEnabled"
  }

  @Published private(set) var presence: JarvisPresence = .idle
  @Published private(set) var pageBusy = false
  @Published private(set) var hotKeyAvailable = false

  private(set) lazy var webView: WKWebView = makeWebView()
  private let logger = Logger(subsystem: "local.dayframe.app", category: "jarvis")
  private var started = false
  private var pageReady = false
  private var cancellables: Set<AnyCancellable> = []
  /// The app's own light/dark choice, sent by the tab (DayflowTheme), not the system's.
  private var dark: Bool?

  var isEnabled: Bool {
    UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
  }

  var brain: String {
    get { UserDefaults.standard.string(forKey: Keys.brain) ?? "grok" }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.brain)
      pushContext()
    }
  }

  func start() {
    // Unit tests launch the app as their host; they must not start Hermes or grab ⌥Space.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    guard !started, isEnabled else { return }
    started = true
    HermesBackend.shared.start()
    hotKeyAvailable = JarvisHotKey.shared.register { [weak self] in self?.listen() }

    HermesBackend.shared.$phase
      .sink { [weak self] _ in Task { @MainActor in self?.pushContext() } }
      .store(in: &cancellables)
    DayframePaletteStore.shared.objectWillChange
      .sink { [weak self] _ in Task { @MainActor in self?.pushContext() } }
      .store(in: &cancellables)
    Publishers.CombineLatest3(
      JarvisListener.shared.$state, JarvisVoice.shared.$isSpeaking, $pageBusy
    )
    .map { listening, speaking, busy -> JarvisPresence in
      if listening != .idle { return .listening }
      if speaking { return .speaking }
      return busy ? .thinking : .idle
    }
    .removeDuplicates()
    .sink { [weak self] presence in
      self?.presence = presence
      IslandController.shared.setJarvis(presence)
    }
    .store(in: &cancellables)
    _ = webView
  }

  func stop() {
    JarvisHotKey.shared.unregister()
    JarvisVoice.shared.stop()
    JarvisListener.shared.cancel()
    HermesBackend.shared.stop()
  }

  /// ⌥Space or the mic button: listen, then hand the words to the page as a voice turn.
  func listen() {
    JarvisVoice.shared.stop()
    JarvisListener.shared.toggle { [weak self] text in self?.ask(text, surface: "voice") }
  }

  func ask(_ text: String, surface: String = "chat") {
    guard pageReady, let json = Self.jsonString(text) else {
      logger.error("Jarvis page isn't ready; dropped a request")
      return
    }
    webView.evaluateJavaScript("window.jarvis && window.jarvis.ask(\(json), '\(surface)')")
  }

  func setDark(_ value: Bool) {
    guard dark != value else { return }
    dark = value
    pushContext()
  }

  // MARK: - Page

  private func makeWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController.add(WeakScriptMessageHandler(self), name: "dayframe")
    let web = WKWebView(frame: .zero, configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    web.navigationDelegate = self
    web.uiDelegate = self
    if let page = Bundle.main.url(forResource: "jarvis", withExtension: "html") {
      var components = URLComponents(url: page, resolvingAgainstBaseURL: false)!
      components.queryItems = [
        URLQueryItem(name: "palette", value: DayframePaletteStore.shared.palette.rawValue),
        URLQueryItem(name: "theme", value: NSApp.effectiveAppearance.isDark ? "dark" : "light"),
      ]
      web.loadFileURL(components.url!, allowingReadAccessTo: page.deletingLastPathComponent())
    } else {
      logger.error("jarvis.html is missing from the app bundle")
    }
    return web
  }

  /// The page's whole world: theme, the backend to dial, and the default brain.
  func pushContext() {
    guard pageReady else { return }
    let backend = HermesBackend.shared
    var context: [String: Any] = [
      "palette": DayframePaletteStore.shared.palette.rawValue,
      "dark": dark ?? NSApp.effectiveAppearance.isDark,
      "brain": brain,
    ]
    switch backend.phase {
    case .ready(let port):
      context["port"] = port
      context["token"] = backend.token
      context["backendNote"] = NSNull()
    case .notInstalled:
      context["port"] = NSNull()
      context["backendNote"] = "Hermes Agent isn't installed yet. Settings › Jarvis shows how."
    case .failed(let reason):
      context["port"] = NSNull()
      context["backendNote"] = "Hermes stopped: \(reason) Restart it in Settings › Jarvis."
    case .idle, .starting:
      context["port"] = NSNull()
      context["backendNote"] = NSNull()
    }
    guard let data = try? JSONSerialization.data(withJSONObject: context),
      let json = String(data: data, encoding: .utf8)
    else { return }
    webView.evaluateJavaScript("window.jarvis && window.jarvis.setContext(\(json))")
  }

  private static func jsonString(_ text: String) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: [text]),
      let array = String(data: data, encoding: .utf8)
    else { return nil }
    return String(array.dropFirst().dropLast())
  }

  fileprivate func handle(_ body: Any) {
    guard let message = body as? [String: Any], let type = message["type"] as? String else {
      return
    }
    switch type {
    case "ready":
      pageReady = true
      pushContext()
    case "speak":
      if let text = message["text"] as? String { JarvisVoice.shared.speak(text) }
    case "stopSpeaking":
      JarvisVoice.shared.stop()
    case "busy":
      pageBusy = message["busy"] as? Bool ?? false
    case "listen":
      listen()
    case "openSettings":
      NotificationCenter.default.post(name: .navigateToJarvisSettings, object: nil)
    default:
      break
    }
  }
}

extension JarvisCoordinator: WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
  nonisolated func userContentController(
    _ controller: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    let body = message.body
    Task { @MainActor in self.handle(body) }
  }

  /// Only the bundled page itself loads here; http(s) links open in the browser.
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = action.request.url else { return decisionHandler(.cancel) }
    if url.isFileURL || url.scheme == "about" { return decisionHandler(.allow) }
    if url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
    decisionHandler(.cancel)
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for action: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if let url = action.request.url, url.scheme == "http" || url.scheme == "https" {
      NSWorkspace.shared.open(url)
    }
    return nil
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    pageReady = false
    webView.reload()
  }
}

extension Notification.Name {
  static let navigateToJarvis = Notification.Name("navigateToJarvis")
  static let navigateToJarvisSettings = Notification.Name("navigateToJarvisSettings")
}

extension NSAppearance {
  fileprivate var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
