//
//  StartOfDay.swift
//  Dayframe
//
//  What happens after the login welcome: Dayframe opens on Briefing as the hub, your
//  day's apps open quietly, windows go to their places (Layout style) and every other
//  app is hidden (never quit). With the Stage Manager style, macOS arranges windows
//  and Dayframe only opens the apps.
//

import AppKit
import ApplicationServices
import OSLog

private let startLog = Logger(subsystem: "local.dayframe.app", category: "startofday")

/// Where a window goes on its display.
enum WindowSlot: String, Codable, CaseIterable, Identifiable {
  case keep, full, center, leftHalf, rightHalf, leftTwoThirds, rightThird

  var id: String { rawValue }

  var title: String {
    switch self {
    case .keep: return "Leave as is"
    case .full: return "Full screen size"
    case .center: return "Centered"
    case .leftHalf: return "Left half"
    case .rightHalf: return "Right half"
    case .leftTwoThirds: return "Left two-thirds"
    case .rightThird: return "Right third"
    }
  }

  /// The frame in AppKit coordinates (bottom-left origin) inside a display's visible area.
  func frame(in visible: CGRect) -> CGRect? {
    let gap: CGFloat = 8
    let area = visible.insetBy(dx: gap, dy: gap)
    switch self {
    case .keep: return nil
    case .full: return area
    case .center:
      let w = min(area.width, max(900, area.width * 0.7))
      let h = min(area.height, max(640, area.height * 0.8))
      return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    case .leftHalf:
      return CGRect(x: area.minX, y: area.minY, width: (area.width - gap) / 2, height: area.height)
    case .rightHalf:
      let w = (area.width - gap) / 2
      return CGRect(x: area.maxX - w, y: area.minY, width: w, height: area.height)
    case .leftTwoThirds:
      return CGRect(
        x: area.minX, y: area.minY, width: (area.width - gap) * 2 / 3, height: area.height)
    case .rightThird:
      let w = (area.width - gap) / 3
      return CGRect(x: area.maxX - w, y: area.minY, width: w, height: area.height)
    }
  }
}

enum WindowStyle: String, CaseIterable, Identifiable {
  case layout, stageManager

  var id: String { rawValue }
  var title: String { self == .layout ? "Layout" : "Stage Manager" }
}

/// Day apps' icons as small PNG data URLs for the Briefing page, made once per app.
@MainActor
enum DayAppIcon {
  private static var cache: [String: String] = [:]

  static func dataURL(forAppAt path: String) -> String {
    if let cached = cache[path] { return cached }
    let icon = NSWorkspace.shared.icon(forFile: path)
    let size = NSSize(width: 64, height: 64)
    let image = NSImage(size: size, flipped: false) { rect in
      icon.draw(in: rect)
      return true
    }
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else { return "" }
    let url = "data:image/png;base64," + png.base64EncodedString()
    cache[path] = url
    return url
  }
}

/// What one start-of-day run did: the line under "Run now", and the log's last word.
struct StartOfDayReport: Equatable {
  var opened = 0
  var alreadyOpen = 0
  var failed = 0
  var placed = 0
  /// The Focus shortcut that ran, and whether it worked (nil when none is set).
  var focus: (name: String, error: String?)?

  static func == (a: Self, b: Self) -> Bool {
    (a.opened, a.alreadyOpen, a.failed, a.placed) == (b.opened, b.alreadyOpen, b.failed, b.placed)
      && a.focus?.name == b.focus?.name && a.focus?.error == b.focus?.error
  }

  func summary(at time: String) -> String {
    var parts = ["\(opened) opened"]
    if alreadyOpen > 0 { parts.append("\(alreadyOpen) already open") }
    if failed > 0 { parts.append("\(failed) couldn't open") }
    parts.append("\(placed) placed")
    var text = "Ran at \(time): " + parts.joined(separator: ", ") + "."
    if let focus {
      text += focus.error == nil ? " \(focus.name) is on." : " \(focus.name) didn't run."
    }
    return text
  }
}

struct DayApp: Codable, Identifiable, Hashable {
  var bundleID: String
  var name: String
  var path: String
  var slot: WindowSlot

  var id: String { bundleID }
}

@MainActor
final class StartOfDay: ObservableObject {
  static let shared = StartOfDay()

  enum Keys {
    static let enabled = "dayframeStartOfDayEnabled"
    static let hideOthers = "dayframeStartOfDayHideOthers"
    static let apps = "dayframeStartOfDayApps"
    static let dayframeSlot = "dayframeStartOfDayDayframeSlot"
    static let windowStyle = "dayframeStartOfDayWindowStyle"
    /// The Shortcut that turns the day's Focus on ("" = none).
    static let focusShortcut = "dayframeStartOfDayFocusShortcut"
  }

  @Published var apps: [DayApp] { didSet { save() } }
  @Published private(set) var isRunning = false
  @Published private(set) var lastRun: String?

  private let defaults = UserDefaults.standard

  private init() {
    defaults.register(defaults: [
      Keys.enabled: true, Keys.hideOthers: true, Keys.dayframeSlot: WindowSlot.center.rawValue,
      Keys.windowStyle: WindowStyle.layout.rawValue,
    ])
    if let data = UserDefaults.standard.data(forKey: Keys.apps),
      let saved = try? JSONDecoder().decode([DayApp].self, from: data)
    {
      apps = saved
    } else {
      apps = []
    }
  }

  var windowStyle: WindowStyle {
    WindowStyle(rawValue: defaults.string(forKey: Keys.windowStyle) ?? "") ?? .layout
  }

  private var dayframeSlot: WindowSlot {
    WindowSlot(rawValue: defaults.string(forKey: Keys.dayframeSlot) ?? "") ?? .center
  }

  static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

  /// Shows macOS's own Accessibility prompt (the user grants it in System Settings).
  static func requestAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func add(appAt url: URL) {
    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
      id != Bundle.main.bundleIdentifier, !apps.contains(where: { $0.bundleID == id })
    else { return }
    let name =
      (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? url.deletingPathExtension().lastPathComponent
    apps.append(DayApp(bundleID: id, name: name, path: url.path, slot: .keep))
  }

  private func save() {
    if let data = try? JSONEncoder().encode(apps) { defaults.set(data, forKey: Keys.apps) }
  }

  // MARK: - Run

  /// `force` runs even when the automatic start of day is off (the "Run now" button).
  func run(reason: String, force: Bool = false) {
    guard force || defaults.bool(forKey: Keys.enabled), !isRunning else { return }
    isRunning = true
    startLog.notice("[StartOfDay] run (\(reason, privacy: .public))")
    Task { @MainActor in
      defer { isRunning = false }

      // 1. Dayframe front, on Briefing.
      MainWindowController.shared.showMainWindow()
      NotificationCenter.default.post(name: .navigateToBriefing, object: nil)
      NSApp.activate(ignoringOtherApps: true)

      // 2. Your day's apps, quietly, one after another.
      var report = StartOfDayReport()
      var launched: [NSRunningApplication] = []
      for app in apps {
        if let running = NSRunningApplication.runningApplications(
          withBundleIdentifier: app.bundleID
        ).first {
          running.unhide()
          launched.append(running)
          report.alreadyOpen += 1
          startLog.notice("[StartOfDay] \(app.name, privacy: .public): already open")
          continue
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        let url =
          NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
          ?? URL(fileURLWithPath: app.path)
        do {
          launched.append(
            try await NSWorkspace.shared.openApplication(at: url, configuration: config))
          report.opened += 1
          startLog.notice("[StartOfDay] \(app.name, privacy: .public): opened")
        } catch {
          report.failed += 1
          startLog.error(
            "[StartOfDay] \(app.name, privacy: .public): couldn't open: \(error.localizedDescription, privacy: .public)"
          )
        }
        try? await Task.sleep(for: .milliseconds(500))
      }

      // 3. Everything else out of the way (hidden, not quit).
      if defaults.bool(forKey: Keys.hideOthers) { hideOthers(keeping: Set(apps.map(\.bundleID))) }

      // 4. The day's Focus, through the user's Shortcut (macOS has no API for it).
      if let name = defaults.string(forKey: Keys.focusShortcut), !name.isEmpty {
        let error = await Task.detached(priority: .userInitiated) { FocusShortcut.run(name) }.value
        report.focus = (name, error)
        if let error {
          startLog.error(
            "[StartOfDay] Focus shortcut \(name, privacy: .public) failed: \(error, privacy: .public)"
          )
        } else {
          startLog.notice("[StartOfDay] Focus shortcut \(name, privacy: .public) ran")
        }
      }

      // 5. Windows to their places (Layout style only; Stage Manager arranges its own).
      let slotted = apps.filter { $0.slot != .keep }
      if windowStyle == .layout {
        placeDayframe()
        if !Self.accessibilityTrusted, !slotted.isEmpty {
          startLog.notice(
            "[StartOfDay] \(slotted.count, privacy: .public) window(s) not placed: Accessibility isn't allowed"
          )
        } else {
          for app in slotted {
            guard let running = launched.first(where: { $0.bundleIdentifier == app.bundleID })
            else { continue }
            let placed = await AXWindowPlacer.place(pid: running.processIdentifier, slot: app.slot)
            if placed { report.placed += 1 }
            startLog.notice(
              "[StartOfDay] \(app.name, privacy: .public): \(placed ? "placed" : "no window to place", privacy: .public) (\(app.slot.rawValue, privacy: .public))"
            )
          }
        }
      }

      // 6. Back to the hub.
      MainWindowController.shared.showMainWindow()
      NSApp.activate(ignoringOtherApps: true)
      lastRun = report.summary(at: Date().formatted(date: .omitted, time: .shortened))
      startLog.notice("[StartOfDay] done: \(self.lastRun ?? "", privacy: .public)")
    }
  }

  /// Brings one of the day's apps forward, opening it if needed (Briefing's "Today's apps").
  /// Only apps on the user's list: the page can't open anything else.
  @discardableResult
  func bringForward(bundleID: String) -> Bool {
    guard let app = apps.first(where: { $0.bundleID == bundleID }) else {
      startLog.error("[StartOfDay] refused to open \(bundleID, privacy: .public): not a day app")
      return false
    }
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    {
      running.unhide()
      running.activate()
    } else {
      let url =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        ?? URL(fileURLWithPath: app.path)
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    startLog.notice("[StartOfDay] \(app.name, privacy: .public): brought forward from Briefing")
    return true
  }

  private func hideOthers(keeping: Set<String>) {
    let me = Bundle.main.bundleIdentifier
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      guard let id = app.bundleIdentifier, id != me, !keeping.contains(id) else { continue }
      app.hide()
    }
  }

  /// Dayframe's own window needs no Accessibility permission.
  private func placeDayframe() {
    guard let screen = NSScreen.main, let target = dayframeSlot.frame(in: screen.visibleFrame)
    else { return }
    guard let window = MainWindowController.shared.window else {
      return startLog.notice("[StartOfDay] Dayframe's main window isn't open; not moved")
    }
    window.setFrame(target, display: true, animate: true)
  }
}

extension Notification.Name {
  static let navigateToBriefing = Notification.Name("navigateToBriefing")
}

/// Moves another app's window through the Accessibility API.
enum AXWindowPlacer {
  /// Waits up to 8 s for the app's first window, then moves and sizes it.
  @MainActor
  static func place(pid: pid_t, slot: WindowSlot) async -> Bool {
    let app = AXUIElementCreateApplication(pid)
    for _ in 0..<32 {
      if let window = firstWindow(of: app) {
        return move(window, to: slot)
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return false
  }

  private static func firstWindow(of app: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    {
      return unsafeDowncast(value, to: AXUIElement.self)
    }
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return nil }
    return windows.first
  }

  @MainActor
  private static func move(_ window: AXUIElement, to slot: WindowSlot) -> Bool {
    guard let screen = NSScreen.main, let primary = NSScreen.screens.first,
      let frame = slot.frame(in: screen.visibleFrame)
    else { return false }
    // AX uses a top-left origin on the primary display.
    var origin = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY)
    var size = frame.size
    guard let position = AXValueCreate(.cgPoint, &origin),
      let dimensions = AXValueCreate(.cgSize, &size)
    else {
      return false
    }
    // Size, move, then size again: some apps clamp the size to the old screen position.
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    return moved == .success
  }
}
