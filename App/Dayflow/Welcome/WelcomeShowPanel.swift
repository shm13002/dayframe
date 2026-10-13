//
//  WelcomeShowPanel.swift
//  Dayframe
//
//  Plays one welcome show ("System Awakening", first launch or daily wake) from the
//  bundled welcome.html, then closes. Modeled on IslandShowPanel.
//
//  Every display gets a cover in the palette's deep sky, shown at once so nothing
//  flashes behind it while the page loads. The main display also gets the page. The
//  page posts "started" on its first frame (the sound starts then and the native cover
//  hands over to the page's identical sky), "skip" when clicked, and "done" at the end.
//

import AVFoundation
import AppKit
import OSLog
import WebKit

private let welcomeLog = Logger(subsystem: "local.dayframe.app", category: "welcome")

enum WelcomeVariant: String, Encodable {
  case firstLaunch, dailyWake

  var soundName: String { self == .firstLaunch ? "first-launch" : "daily-wake" }
}

enum WelcomeSoundMix: String, CaseIterable, Identifiable {
  case off, laptop, cinematic

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off: return "Off"
    case .laptop: return "Mac speakers"
    case .cinematic: return "Headphones"
    }
  }
}

@MainActor
final class WelcomeShowPanel: NSObject, WKScriptMessageHandler {
  private struct Payload: Encodable {
    let variant: WelcomeVariant
    let palette: String
    let reducedMotion: Bool
  }

  /// Called once, when the show is over (finished, skipped, cancelled or failed).
  var onFinished: (() -> Void)?

  private let variant: WelcomeVariant
  private let mix: WelcomeSoundMix
  private let palette: DayframePalette
  private var panels: [NSPanel] = []
  private var covers: [NSView] = []
  private var webView: WKWebView?
  private var player: AVAudioPlayer?
  private var watchdog: Task<Void, Never>?
  private var finished = false

  init(variant: WelcomeVariant, mix: WelcomeSoundMix, palette: DayframePalette) {
    self.variant = variant
    self.mix = mix
    self.palette = palette
  }

  /// The show's window numbers (kept after it closes), so the recorder can leave them out.
  private(set) var windowNumbers: [Int] = []

  func present() {
    guard let url = Bundle.main.url(forResource: "welcome", withExtension: "html"),
      let main = NSScreen.main ?? NSScreen.screens.first
    else {
      welcomeLog.error("[Welcome] welcome.html is missing from the app bundle")
      finish()
      return
    }

    for screen in NSScreen.screens {
      let panel = WelcomeKeyPanel(
        contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
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
      panel.onSkip = { [weak self] in self?.skip() }

      let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
      container.autoresizingMask = [.width, .height]
      let cover = WelcomeSkyView(frame: container.bounds, palette: palette)
      cover.autoresizingMask = [.width, .height]
      container.addSubview(cover)
      covers.append(cover)

      if screen == main {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "welcome")
        let web = WKWebView(frame: container.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        container.addSubview(web)
        webView = web
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      }
      panel.contentView = container
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      panels.append(panel)
    }
    windowNumbers = panels.map(\.windowNumber)
    // The cover fades in fast; for a login the screen goes straight to the sky.
    fadePanels(to: 1, duration: variant == .firstLaunch ? 0.08 : 0.15)
    loadSound()

    // Never leave a panel over the screen.
    watchdog = Task { [weak self] in
      try? await Task.sleep(for: .seconds(12))
      guard !Task.isCancelled else { return }
      welcomeLog.error("[Welcome] watchdog closed the show")
      self?.finish()
    }
  }

  /// Ends the show at once (the screen locked again, or the feature was turned off).
  func cancel() { finish() }

  func userContentController(
    _ controller: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard message.name == "welcome", let body = message.body as? [String: Any] else { return }
    switch body["type"] as? String {
    case "ready":
      start()
    case "started":
      player?.play()
      // The page draws the same sky; hand over to it.
      for cover in covers.prefix(1) { fade(cover, to: 0, duration: 0.2) }
    case "skip":
      player?.setVolume(0, fadeDuration: 0.25)
      fadePanels(to: 0, duration: 0.3, extraScreensOnly: true)
    case "done":
      if let fps = (body["fps"] as? NSNumber)?.doubleValue {
        welcomeLog.notice(
          "[Welcome] \(self.variant.rawValue, privacy: .public) show finished at \(Int(fps.rounded()), privacy: .public) fps"
        )
      }
      finish()
    default:
      break
    }
  }

  private func skip() {
    webView?.evaluateJavaScript("window.welcome.skip()")
  }

  private func start() {
    guard let webView,
      let panel = panels.first(where: { $0.contentView?.subviews.contains(webView) == true })
    else {
      finish()
      return
    }
    let payload = Payload(
      variant: variant, palette: palette.rawValue,
      reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    guard let data = try? JSONEncoder().encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      finish()
      return
    }
    webView.evaluateJavaScript("window.welcome.play(\(json))") { [weak self] _, error in
      guard let self else { return }
      if let error {
        welcomeLog.error("[Welcome] play failed: \(error.localizedDescription, privacy: .public)")
        self.finish()
        return
      }
      panel.makeKey()
      panel.makeFirstResponder(webView)
      // Extra displays follow the page's closing dissolve.
      let total: TimeInterval =
        payload.reducedMotion ? 0.8 : (self.variant == .firstLaunch ? 5.45 : 2.0)
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(max(0, total - 0.45)))
        self?.fadePanels(to: 0, duration: 0.4, extraScreensOnly: true)
      }
    }
  }

  private func loadSound() {
    guard mix != .off,
      let url = Bundle.main.url(
        forResource: "welcome-\(variant.soundName)_\(mix.rawValue)", withExtension: "m4a")
    else { return }
    player = try? AVAudioPlayer(contentsOf: url)
    player?.prepareToPlay()
  }

  private func fadePanels(to alpha: CGFloat, duration: TimeInterval, extraScreensOnly: Bool = false)
  {
    for panel in panels
    where
      !(extraScreensOnly
      && panel.contentView?.subviews.contains(where: { $0 is WKWebView }) == true)
    {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = duration
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().alphaValue = alpha
      }
    }
  }

  private func fade(_ view: NSView, to alpha: CGFloat, duration: TimeInterval) {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = duration
      view.animator().alphaValue = alpha
    }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    watchdog?.cancel()
    player?.setVolume(0, fadeDuration: 0.2)
    let player = self.player
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(250))
      player?.stop()
    }
    webView?.configuration.userContentController.removeScriptMessageHandler(forName: "welcome")
    webView?.stopLoading()
    for panel in panels {
      panel.orderOut(nil)
      panel.contentView = nil
    }
    panels.removeAll()
    covers.removeAll()
    webView = nil
    onFinished?()
    onFinished = nil
  }
}

/// The palette's deep night sky (the same gradient the page draws behind the light).
final class WelcomeSkyView: NSView {
  init(frame: NSRect, palette: DayframePalette) {
    super.init(frame: frame)
    wantsLayer = true
    let layer = CAGradientLayer()
    layer.type = .radial
    let dark = palette.stops.dark.map { NSColor(hex: $0) ?? .black }
    layer.colors = [
      dark[1].scaled(0.22).cgColor, dark[0].scaled(0.3).cgColor, dark[2].scaled(0.3).cgColor,
    ]
    layer.locations = [0, 0.55, 1]
    layer.startPoint = CGPoint(x: 0.5, y: 0.62)
    layer.endPoint = CGPoint(x: 1.2, y: 1.3)
    self.layer = layer
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Borderless panels can't become key by default; the show needs keys to be skippable.
private final class WelcomeKeyPanel: NSPanel {
  var onSkip: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { onSkip?() }
  override func mouseDown(with event: NSEvent) { onSkip?() }
}

extension NSColor {
  /// The same color with each channel multiplied by k (k < 1 darkens).
  func scaled(_ k: CGFloat) -> NSColor {
    let c = usingColorSpace(.sRGB) ?? self
    return NSColor(
      srgbRed: c.redComponent * k, green: c.greenComponent * k, blue: c.blueComponent * k,
      alpha: c.alphaComponent)
  }
}
