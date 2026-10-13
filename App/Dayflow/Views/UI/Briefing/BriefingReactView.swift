//
//  BriefingReactView.swift
//  Dayframe
//
//  The Briefing tab, drawn by the React app that briefing.py serves at /app/
//  (source in Web/src/briefing). The page follows the app's palette, dark mode and
//  category colors through window.dayframe.setContext, without reloading.
//  If the page isn't installed or doesn't come up, the native BriefingView is shown.
//

import AppKit
import SwiftUI
import WebKit

struct BriefingReactView: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var palette = DayframePaletteStore.shared
  @ObservedObject private var categoryStore = CategoryStore.shared
  @State private var phase: Phase = .probing
  @State private var pageReady = false
  @State private var morePage: BriefingMorePage?

  private enum Phase { case probing, web, native }

  /// How long the page gets to report "ready" before the native screen takes over.
  private static let readyTimeout: Duration = .seconds(4)

  var body: some View {
    ZStack {
      switch phase {
      case .probing:
        Color.clear
      case .native:
        BriefingView()
      case .web:
        BriefingWebHost(url: pageURL, context: context, onMessage: handle)
          .opacity(pageReady ? 1 : 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeOut(duration: 0.2), value: pageReady)
    .task { await probe() }
    .task(id: phase) {
      guard phase == .web else { return }
      try? await Task.sleep(for: Self.readyTimeout)
      if !Task.isCancelled, !pageReady { phase = .native }
    }
    .sheet(item: $morePage) { BriefingMoreSheet(page: $0) }
  }

  private var pageURL: URL {
    var components = URLComponents(url: BriefingService.baseURL, resolvingAgainstBaseURL: false)!
    components.path = "/app/"
    components.queryItems = [
      URLQueryItem(name: "embed", value: "dayframe"),
      URLQueryItem(name: "theme", value: theme.isDark ? "dark" : "light"),
      URLQueryItem(name: "palette", value: palette.palette.rawValue),
    ]
    return components.url!
  }

  private var context: BriefingPageContext {
    BriefingPageContext(
      palette: palette.palette.rawValue,
      dark: theme.isDark,
      categories: categoryStore.categories.map {
        .init(name: $0.name, color: $0.colorHex.hasPrefix("#") ? $0.colorHex : "#\($0.colorHex)")
      }
    )
  }

  /// Uses the React page only when briefing.py actually serves it.
  private func probe() async {
    var request = URLRequest(url: pageURL)
    request.timeoutInterval = 2
    let status = try? await (URLSession.shared.data(for: request).1 as? HTTPURLResponse)?.statusCode
    phase = status == 200 ? .web : .native
  }

  private func handle(_ message: BriefingPageMessage) {
    switch message {
    case .ready:
      pageReady = true
    case .failed:
      if !pageReady { phase = .native }
    case .openMore(let page):
      morePage = BriefingMorePage(rawValue: page)
    case .showTimeline:
      NotificationCenter.default.post(name: .navigateToTimeline, object: nil)
    }
  }
}

/// What the page needs from the app; sent as JSON to window.dayframe.setContext.
struct BriefingPageContext: Encodable, Equatable {
  struct Category: Encodable, Equatable {
    let name: String
    let color: String
  }
  let palette: String
  let dark: Bool
  let categories: [Category]
}

enum BriefingPageMessage: Equatable {
  case ready
  case failed
  case openMore(String)
  case showTimeline

  init?(body: Any) {
    guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
    switch type {
    case "ready": self = .ready
    case "showTimeline": self = .showTimeline
    case "openMore":
      guard let page = dict["page"] as? String else { return nil }
      self = .openMore(page)
    default: return nil
    }
  }
}

private struct BriefingWebHost: NSViewRepresentable {
  let url: URL
  let context: BriefingPageContext
  let onMessage: (BriefingPageMessage) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage) }

  func makeNSView(context ctx: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController.add(WeakScriptMessageHandler(ctx.coordinator), name: "dayframe")
    let web = WKWebView(frame: .zero, configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    web.navigationDelegate = ctx.coordinator
    web.uiDelegate = ctx.coordinator
    ctx.coordinator.webView = web
    ctx.coordinator.context = context
    ctx.coordinator.allowedOrigin = (url.host, url.port)
    web.load(URLRequest(url: url))
    return web
  }

  func updateNSView(_ web: WKWebView, context ctx: Context) {
    ctx.coordinator.onMessage = onMessage
    if ctx.coordinator.context != context {
      ctx.coordinator.context = context
      ctx.coordinator.pushContext()
    }
  }

  static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
    web.configuration.userContentController.removeScriptMessageHandler(forName: "dayframe")
    web.navigationDelegate = nil
    web.uiDelegate = nil
  }

  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var onMessage: (BriefingPageMessage) -> Void
    weak var webView: WKWebView?
    var context: BriefingPageContext?
    var allowedOrigin: (host: String?, port: Int?) = (nil, nil)
    private var pageIsListening = false

    init(onMessage: @escaping (BriefingPageMessage) -> Void) {
      self.onMessage = onMessage
    }

    /// Sends the current context once the page has said it is listening.
    func pushContext() {
      guard pageIsListening, let webView, let context,
        let data = try? JSONEncoder().encode(context),
        let json = String(data: data, encoding: .utf8)
      else { return }
      webView.evaluateJavaScript("window.dayframe && window.dayframe.setContext(\(json))")
    }

    func userContentController(
      _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard message.name == "dayframe", let parsed = BriefingPageMessage(body: message.body) else {
        return
      }
      if parsed == .ready {
        pageIsListening = true
        pushContext()
      }
      onMessage(parsed)
    }

    private func isAppURL(_ url: URL) -> Bool {
      url.host == allowedOrigin.host && url.port == allowedOrigin.port
    }

    private func openExternally(_ url: URL) {
      guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return
      }
      NSWorkspace.shared.open(url)
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = action.request.url else { return decisionHandler(.cancel) }
      if isAppURL(url) || url.scheme == "about" { return decisionHandler(.allow) }
      openExternally(url)
      decisionHandler(.cancel)
    }

    /// window.open(...) from the page: open in the default browser, never in a new web view.
    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if let url = action.request.url { openExternally(url) }
      return nil
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      onMessage(.failed)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      onMessage(.failed)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      pageIsListening = false
      webView.reload()
    }
  }
}
