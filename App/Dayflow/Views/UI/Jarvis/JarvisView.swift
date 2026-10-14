//
//  JarvisView.swift
//  Jarvis
//
//  The Jarvis tab (the HQ): hosts the one long-lived Jarvis page owned by JarvisCoordinator.
//

import SwiftUI
import WebKit

struct JarvisView: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var backend = HermesBackend.shared

  var body: some View {
    JarvisWebHost()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        JarvisCoordinator.shared.start()
        JarvisCoordinator.shared.setDark(theme.isDark)
      }
      .onChange(of: theme.isDark) { _, dark in JarvisCoordinator.shared.setDark(dark) }
  }
}

private struct JarvisWebHost: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let container = NSView()
    attach(to: container)
    return container
  }

  func updateNSView(_ container: NSView, context: Context) {
    attach(to: container)
  }

  /// Moves the shared web view into this container (it may still sit in a closed window's view).
  private func attach(to container: NSView) {
    let web = JarvisCoordinator.shared.webView
    guard web.superview !== container else { return }
    web.removeFromSuperview()
    web.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(web)
    NSLayoutConstraint.activate([
      web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      web.topAnchor.constraint(equalTo: container.topAnchor),
      web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }
}
