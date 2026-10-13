//
//  WallpaperManager.swift
//  Dayframe
//
//  The Dayframe wallpaper: the palette's sky over a soft dusk horizon, with no text.
//  macOS shows the desktop picture behind the login and lock screen, so this is the
//  "background when you open the Mac". It is re-rendered when the palette, the
//  appearance or the displays change, and your previous wallpaper is restored when
//  it's turned off.
//

import AppKit
import Combine
import OSLog
import SwiftUI

private let wallpaperLog = Logger(subsystem: "local.dayframe.app", category: "wallpaper")

@MainActor
final class WallpaperManager: ObservableObject {
  static let shared = WallpaperManager()

  enum Keys {
    static let enabled = "dayframeWallpaperEnabled"
    static let previous = "dayframeWallpaperPrevious"
  }

  @Published private(set) var lastError: String?

  private var observers: [NSObjectProtocol] = []
  private var cancellables: Set<AnyCancellable> = []
  private var started = false
  private var pending: Task<Void, Never>?
  private let defaults = UserDefaults.standard

  static var enabled: Bool { UserDefaults.standard.bool(forKey: Keys.enabled) }

  static var folder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Dayframe/Wallpaper", isDirectory: true)
  }

  func start() {
    guard !started else { return }
    started = true
    DayframePaletteStore.shared.$palette
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.refreshSoon() }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .map { _ in UserDefaults.standard.string(forKey: DayflowAppearance.storageKey) }
      .removeDuplicates()
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.refreshSoon() }
      .store(in: &cancellables)
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.refreshSoon() } })
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.refreshSoon() } })
    if Self.enabled { refreshSoon() }
  }

  /// Turns the Dayframe wallpaper on or off.
  func setEnabled(_ on: Bool) {
    defaults.set(on, forKey: Keys.enabled)
    if on {
      rememberCurrentWallpaper()
      refreshSoon()
    } else {
      restore()
    }
  }

  private func refreshSoon() {
    guard Self.enabled else { return }
    pending?.cancel()
    pending = Task { [weak self] in
      // Palette changes animate; let a burst of changes settle first.
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      self?.apply()
    }
  }

  /// Renders the wallpaper for each display and sets it.
  func apply() {
    let palette = DayframePaletteStore.shared.palette
    let dark = isDark
    let stamp = Int(Date().timeIntervalSince1970)
    do {
      try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
      var written: [URL] = []
      for (index, screen) in NSScreen.screens.enumerated() {
        let size = CGSize(
          width: screen.frame.width * screen.backingScaleFactor,
          height: screen.frame.height * screen.backingScaleFactor)
        // A new name every time: macOS caches desktop pictures by path.
        let url = Self.folder.appendingPathComponent(
          "\(palette.rawValue)-\(dark ? "dark" : "light")-\(index)-\(stamp).png")
        guard let png = Self.render(palette: palette, dark: dark, pixels: size) else { continue }
        try png.write(to: url, options: .atomic)
        try NSWorkspace.shared.setDesktopImageURL(
          url, for: screen,
          options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
          ])
        written.append(url)
      }
      cleanUp(keeping: Set(written))
      lastError = nil
      wallpaperLog.notice(
        "[Wallpaper] set \(palette.rawValue, privacy: .public) \(dark ? "dark" : "light", privacy: .public) on \(written.count) display(s)"
      )
    } catch {
      lastError = error.localizedDescription
      wallpaperLog.error("[Wallpaper] failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private var isDark: Bool {
    let pref =
      DayflowAppearance(rawValue: defaults.string(forKey: DayflowAppearance.storageKey) ?? "")
      ?? .system
    return pref.colorScheme(system: SystemAppearanceObserver.currentColorScheme) == .dark
  }

  /// PNG data for the wallpaper at a pixel size.
  static func render(palette: DayframePalette, dark: Bool, pixels: CGSize) -> Data? {
    let renderer = ImageRenderer(
      content: WallpaperArt(palette: palette, dark: dark).frame(
        width: pixels.width, height: pixels.height))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }

  private func rememberCurrentWallpaper() {
    var previous: [String: String] = [:]
    for screen in NSScreen.screens {
      guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
        !url.path.hasPrefix(Self.folder.path),
        let id = screen.displayID
      else { continue }
      previous[String(id)] = url.absoluteString
    }
    // Keep an older remembered wallpaper if nothing new and real was found.
    if !previous.isEmpty { defaults.set(previous, forKey: Keys.previous) }
  }

  private func restore() {
    pending?.cancel()
    let previous = defaults.dictionary(forKey: Keys.previous) as? [String: String] ?? [:]
    var restored = 0
    for screen in NSScreen.screens {
      guard let id = screen.displayID, let string = previous[String(id)],
        let url = URL(string: string),
        FileManager.default.fileExists(atPath: url.path)
      else { continue }
      if (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])) != nil {
        restored += 1
      }
    }
    if restored == 0 {
      // A dynamic or system wallpaper can't be read back; let the user pick one.
      NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
    }
  }

  private func cleanUp(keeping: Set<URL>) {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: Self.folder, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.pathExtension == "png" && !keeping.contains(file) {
      try? FileManager.default.removeItem(at: file)
    }
  }
}

extension NSScreen {
  var displayID: CGDirectDisplayID? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
      CGDirectDisplayID($0.uint32Value)
    }
  }
}

/// The wallpaper itself: sky, a low glow where the light set, and three dune lines.
/// Deliberately no text or logo: it also sits behind the lock screen.
struct WallpaperArt: View {
  let palette: DayframePalette
  let dark: Bool

  var body: some View {
    Canvas { context, size in
      let s = palette.stops
      let accent = Color(hex: s.accent)
      let glow = Color(hex: s.accentLight)
      // Light mode: dunes are the warm horizon color, deepening toward the accent up front.
      let sand = NSColor(hex: s.light[0]) ?? .white
      let deep = NSColor(hex: s.accent) ?? .black
      func lightDune(_ t: CGFloat) -> Color {
        Color(nsColor: sand.blended(withFraction: t, of: deep) ?? sand)
      }
      let full = CGRect(origin: .zero, size: size)
      let horizon = size.height * 0.68

      // Sky: deep at the top, warming toward the horizon.
      let skyTop = dark ? scaledColor(s.dark[0], 0.42) : Color(hex: s.light[2])
      let skyMid = dark ? scaledColor(s.dark[2], 0.62) : Color(hex: s.light[1])
      let skyLow = dark ? scaledColor(s.dark[1], 0.8) : Color(hex: s.light[0])
      context.fill(
        Path(full),
        with: .linearGradient(
          Gradient(stops: [
            .init(color: skyTop, location: 0), .init(color: skyMid, location: 0.55),
            .init(color: skyLow, location: 0.7),
          ]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

      // Where the light set: a wide, low glow on the horizon, fading out on every side.
      context.fill(
        Path(full),
        with: .radialGradient(
          Gradient(stops: [
            .init(color: glow.opacity(dark ? 0.26 : 0.34), location: 0),
            .init(color: accent.opacity(dark ? 0.09 : 0.12), location: 0.45),
            .init(color: .clear, location: 1),
          ]),
          center: CGPoint(x: size.width / 2, y: horizon), startRadius: 0,
          endRadius: size.width * 0.5))

      // A faint ring sinking behind the dunes: the eclipse from the welcome, at rest.
      let r = size.height * 0.07
      let ring = Path(
        ellipseIn: CGRect(x: size.width / 2 - r, y: horizon - r * 0.55, width: r * 2, height: r * 2)
      )
      context.stroke(
        ring, with: .color(glow.opacity(dark ? 0.22 : 0.3)), lineWidth: max(1, size.height * 0.0012)
      )

      // Dunes, back to front.
      let layers: [(CGFloat, CGFloat, CGFloat, Color)] = [
        (
          horizon - size.height * 0.015, 0.035, 0.0,
          dark ? scaledColor(s.dark[2], 0.5) : lightDune(0.10)
        ),
        (
          horizon + size.height * 0.06, 0.05, 1.7,
          dark ? scaledColor(s.dark[1], 0.36) : lightDune(0.17)
        ),
        (
          horizon + size.height * 0.17, 0.045, 3.1,
          dark ? scaledColor(s.dark[0], 0.24) : lightDune(0.25)
        ),
      ]
      for (y, amp, phase, color) in layers {
        var dune = Path()
        dune.move(to: CGPoint(x: 0, y: size.height))
        let steps = 64
        for i in 0...steps {
          let t = CGFloat(i) / CGFloat(steps)
          let wave = sin(t * .pi * 1.6 + phase) * 0.6 + sin(t * .pi * 3.3 + phase * 1.7) * 0.4
          dune.addLine(to: CGPoint(x: t * size.width, y: y - wave * amp * size.height))
        }
        dune.addLine(to: CGPoint(x: size.width, y: size.height))
        dune.closeSubpath()
        context.fill(dune, with: .color(color))
      }
    }
  }

  private func scaledColor(_ hex: String, _ k: CGFloat) -> Color {
    Color(nsColor: (NSColor(hex: hex) ?? .black).scaled(k))
  }
}
