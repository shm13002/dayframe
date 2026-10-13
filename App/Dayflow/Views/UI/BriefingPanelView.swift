//
//  BriefingPanelView.swift
//  Dayframe
//
//  The daily briefing, built into the app. Shows the local Briefing service
//  (~/Briefing, http://127.0.0.1:8765) inside the main panel, so briefings,
//  Ask-your-memory and the weekly report live in Dayframe instead of a browser.
//

import SwiftUI
import WebKit

struct BriefingPanelView: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var palette = DayframePaletteStore.shared
  @State private var reachable: Bool? = nil
  @State private var reloadToken = UUID()
  /// Dashboard section to open (e.g. "memory", "weekly"); nil = its home page.
  var tab: String? = nil

  private var url: URL {
    var c = URLComponents(url: BriefingService.baseURL, resolvingAgainstBaseURL: false)!
    c.path = "/"
    c.queryItems = [
      URLQueryItem(name: "embed", value: "dayframe"),
      URLQueryItem(name: "theme", value: theme.isDark ? "dark" : "light"),
      URLQueryItem(name: "palette", value: palette.palette.rawValue),
    ]
    c.fragment = tab
    return c.url!
  }

  var body: some View {
    ZStack {
      switch reachable {
      case .some(true):
        BriefingWebView(url: url)
          .id(reloadToken)
      case .some(false):
        offlineState
      case .none:
        ProgressView().controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task { await probe() }
    .onChange(of: palette.palette) { _, _ in reloadToken = UUID() }
    .onChange(of: theme.isDark) { _, _ in reloadToken = UUID() }
  }

  private var offlineState: some View {
    VStack(spacing: 14) {
      Image(systemName: "sun.horizon")
        .font(.system(size: 34, weight: .light))
        .foregroundColor(theme.accent)
      Text("Your briefing service isn't running")
        .font(.custom("InstrumentSerif-Regular", size: 28))
        .foregroundColor(theme.textPrimary)
      Text("Dayframe reads briefings from ~/Briefing. Start it, then try again.")
        .font(.custom("Figtree", size: 13))
        .foregroundColor(theme.textSecondary)
      Text("launchctl kickstart -k gui/$(id -u)/com.dayflowbriefing.dashboard")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputFill))
      Button("Try again") { Task { await probe() } }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
    }
    .padding(40)
  }

  private func probe() async {
    reachable = nil
    var req = URLRequest(url: BriefingService.baseURL.appendingPathComponent("api/context"))
    req.timeoutInterval = 3
    do {
      let (_, resp) = try await URLSession.shared.data(for: req)
      reachable = ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 500
    } catch {
      reachable = false
    }
  }
}

private struct BriefingWebView: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: config)
    web.setValue(false, forKey: "drawsBackground")  // let Dayframe's panel glass show through
    web.navigationDelegate = context.coordinator
    web.load(URLRequest(url: url))
    return web
  }

  func updateNSView(_ web: WKWebView, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, WKNavigationDelegate {
    // Keep the dashboard inside the panel; open anything external in the browser.
    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      if let u = action.request.url, u.host != "127.0.0.1", u.scheme?.hasPrefix("http") == true {
        NSWorkspace.shared.open(u)
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }
  }
}
