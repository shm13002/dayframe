//
//  IslandShowPanel.swift
//  Dayframe
//
//  A transparent, screen-sized panel that plays one island show (startup, goal
//  reached, recap) from the bundled island.html, then closes. The page names
//  sound cues and IslandSound plays them; the page says "collapse" when the dimmed
//  glass should fade out and "done" when the native pill can take over.
//

import AppKit
import OSLog
import WebKit

private let islandLog = Logger(subsystem: "local.dayframe.app", category: "island")

/// Everything the island page needs; encoded to JSON for window.island.play(...).
struct IslandPayload: Encodable {
  enum Variant: String, Encodable { case startup, goal, recap }
  struct Screen: Encodable { let width, height: CGFloat }
  struct Notch: Encodable { let x, width, height: CGFloat }
  struct Pill: Encodable { let leftWing, rightWing, height, radius: CGFloat }
  struct Line: Encodable { let label, text: String }
  struct Focus: Encodable { let minutes, goalMinutes: Int }
  struct Category: Encodable {
    let name: String
    let minutes: Int
    let color: String
  }

  let variant: Variant
  let screen: Screen
  let notch: Notch
  let pill: Pill
  let greeting: String
  let lines: [Line]
  let focus: Focus
  let trackedMinutes: Int
  let categories: [Category]
  let accent: String
  let recording: Bool
  let reducedMotion: Bool

  init(
    variant: Variant, geometry: NotchGeometry, greeting: String, lines: [Line], stats: IslandStats,
    accentHex: String, recording: Bool, reducedMotion: Bool
  ) {
    self.variant = variant
    screen = Screen(width: geometry.screenFrame.width, height: geometry.screenFrame.height)
    notch = Notch(x: geometry.notchX, width: geometry.notchWidth, height: geometry.height)
    pill = Pill(
      leftWing: NotchGeometry.leftWing, rightWing: NotchGeometry.rightWing, height: geometry.height,
      radius: geometry.pillRadius)
    self.greeting = greeting
    self.lines = lines
    focus = Focus(minutes: stats.focusMinutes, goalMinutes: stats.focusGoalMinutes)
    trackedMinutes = stats.trackedMinutes
    categories = stats.categories.map {
      Category(name: $0.name, minutes: $0.minutes, color: $0.colorHex)
    }
    accent = accentHex
    self.recording = recording
    self.reducedMotion = reducedMotion
  }
}

@MainActor
final class IslandShowPanel: NSObject, WKScriptMessageHandler {
  /// Called once the pill should be visible again (on "done", or if the show fails).
  var onFinished: (() -> Void)?
  /// Called when the page has drawn its first frame (the native pill can hide).
  var onStarted: (() -> Void)?

  private let payload: IslandPayload
  private let geometry: NotchGeometry
  private var panel: NSPanel?
  private var webView: WKWebView?
  private var dimView: NSView?
  private var watchdog: Task<Void, Never>?
  private var finished = false

  /// Window number of the panel while it's on screen, so the recorder can leave it out.
  var windowNumber: Int? { panel?.windowNumber }

  init(payload: IslandPayload, geometry: NotchGeometry) {
    self.payload = payload
    self.geometry = geometry
  }

  func present() {
    guard let url = Bundle.main.url(forResource: "island", withExtension: "html") else {
      islandLog.error("[Island] island.html is missing from the app bundle")
      finish()
      return
    }

    let panel = IslandKeyPanel(
      contentRect: geometry.screenFrame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .screenSaver
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none

    let container = NSView(frame: CGRect(origin: .zero, size: geometry.screenFrame.size))
    container.autoresizingMask = [.width, .height]

    // The "dimmed glass" behind the island: a blur of the desktop plus a soft darkening.
    let glass = NSVisualEffectView(frame: container.bounds)
    glass.autoresizingMask = [.width, .height]
    glass.material = .fullScreenUI
    glass.blendingMode = .behindWindow
    glass.state = .active
    let shade = NSView(frame: container.bounds)
    shade.autoresizingMask = [.width, .height]
    shade.wantsLayer = true
    shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
    let dim = NSView(frame: container.bounds)
    dim.autoresizingMask = [.width, .height]
    dim.addSubview(glass)
    dim.addSubview(shade)
    dim.alphaValue = 0
    container.addSubview(dim)

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController.add(WeakScriptMessageHandler(self), name: "island")
    let web = WKWebView(frame: container.bounds, configuration: config)
    web.autoresizingMask = [.width, .height]
    web.setValue(false, forKey: "drawsBackground")
    container.addSubview(web)

    panel.contentView = container
    self.panel = panel
    self.webView = web
    self.dimView = dim
    web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())

    // Never leave a panel over the screen: give up if the page doesn't finish in time.
    watchdog = Task { [weak self] in
      try? await Task.sleep(for: .seconds(14))
      guard !Task.isCancelled else { return }
      self?.finish()
    }
  }

  /// Ends the show early (e.g. the screen locked again).
  func cancel() {
    finish()
  }

  func userContentController(
    _ controller: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard message.name == "island", let body = message.body as? [String: Any] else { return }
    // WebKit hands JS numbers over as NSNumber; read it that way so integer values aren't dropped.
    if body["type"] as? String == "done", let fps = (body["fps"] as? NSNumber)?.doubleValue {
      islandLog.notice(
        "[Island] \(self.payload.variant.rawValue, privacy: .public) show finished at \(Int(fps.rounded()), privacy: .public) fps"
      )
    }
    handle(
      type: body["type"] as? String, cueName: body["name"] as? String,
      value: body["value"] as? Double)
  }

  private func handle(type: String?, cueName: String?, value: Double?) {
    switch type {
    case "ready":
      start()
    case "cue":
      if let cueName, let cue = IslandCue(rawValue: cueName) {
        IslandSound.shared.play(cue, value: value ?? 0)
      }
    case "collapse":
      fadeDim(to: 0, duration: 0.45)
    case "done":
      finish()
    default:
      break
    }
  }

  private func start() {
    guard let panel, let webView,
      let data = try? JSONEncoder().encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      islandLog.error("[Island] show skipped: no panel, or the payload didn't encode")
      finish()
      return
    }
    webView.evaluateJavaScript("window.island.play(\(json))") { [weak self] _, error in
      guard let self else { return }
      if let error {
        islandLog.error("[Island] play failed: \(error.localizedDescription, privacy: .public)")
        self.finish()
        return
      }
      panel.orderFrontRegardless()
      panel.makeKey()
      panel.makeFirstResponder(webView)
      self.onStarted?()
      // The startup gets the full dimmed glass; goal and recap only a lighter veil.
      self.fadeDim(to: self.payload.variant == .startup ? 1 : 0.6, duration: 0.5)
    }
  }

  private func fadeDim(to alpha: CGFloat, duration: TimeInterval) {
    guard let dimView else { return }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = duration
      ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      dimView.animator().alphaValue = alpha
    }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    watchdog?.cancel()
    onFinished?()
    // Give the native pill one frame to appear under the panel before it goes away.
    DispatchQueue.main.async { [self] in
      webView?.configuration.userContentController.removeScriptMessageHandler(forName: "island")
      webView?.stopLoading()
      panel?.orderOut(nil)
      panel?.contentView = nil
      panel = nil
      webView = nil
      dimView = nil
    }
  }
}

/// Borderless panels can't become key by default; the show needs keys to be skippable.
private final class IslandKeyPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
