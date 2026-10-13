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
      return CGRect(x: area.minX, y: area.minY, width: (area.width - gap) * 2 / 3, height: area.height)
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
      var launched: [NSRunningApplication] = []
      for app in apps {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
          running.unhide()
          launched.append(running)
          continue
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        let url =
          NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
          ?? URL(fileURLWithPath: app.path)
        if let running = try? await NSWorkspace.shared.openApplication(at: url, configuration: config) {
          launched.append(running)
        }
        try? await Task.sleep(for: .milliseconds(500))
      }

      // 3. Everything else out of the way (hidden, not quit).
      if defaults.bool(forKey: Keys.hideOthers) { hideOthers(keeping: Set(apps.map(\.bundleID))) }

      // 4. Windows to their places (Layout style only; Stage Manager arranges its own).
      var placed = 0
      if windowStyle == .layout {
        placeDayframe()
        if Self.accessibilityTrusted {
          for app in apps where app.slot != .keep {
            guard let running = launched.first(where: { $0.bundleIdentifier == app.bundleID }) else { continue }
            if await AXWindowPlacer.place(pid: running.processIdentifier, slot: app.slot) { placed += 1 }
          }
        }
      }

      // 5. Back to the hub.
      MainWindowController.shared.showMainWindow()
      NSApp.activate(ignoringOtherApps: true)
      let time = Date().formatted(date: .omitted, time: .shortened)
      lastRun = "Ran at \(time): \(launched.count) app(s) opened, \(placed) placed."
      startLog.notice("[StartOfDay] done: \(launched.count) app(s), \(placed) placed")
    }
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
    guard let screen = NSScreen.main, let target = dayframeSlot.frame(in: screen.visibleFrame) else { return }
    let window = NSApp.windows.first { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
    window?.setFrame(target, display: true, animate: true)
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
    if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success, let value {
      return (value as! AXUIElement)
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
    guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else {
      return false
    }
    // Size, move, then size again: some apps clamp the size to the old screen position.
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    return moved == .success
  }
}
