//
//  WelcomeController.swift
//  Dayframe
//
//  Decides when the welcome plays and runs the start of the day afterwards.
//
//  - Login: the full "first launch" show once per login session, then StartOfDay
//    (Dayframe front on Briefing, your day's apps, layout, others hidden).
//  - Unlock after time away: the short "daily wake" show. Windows are left alone.
//
//  Login is detected per macOS login session (its unique session ID), not from how
//  the app was launched: the keep-alive agent also opens Dayframe at login, and
//  whichever launch wins must still play. A relaunch in the same session never does.
//

import AppKit
import SwiftUI

/// Pure event gate for unlocks. Times are wall-clock seconds, so sleep counts as away.
struct WelcomeEventGate {
  var awaySince: TimeInterval?
  var lastPlayback = -Double.infinity
  var minAway: TimeInterval = 600

  mutating func markAway(now: TimeInterval) {
    if awaySince == nil { awaySince = now }
  }

  /// True when an unlock should play the daily wake.
  mutating func returnToSession(now: TimeInterval, accessible: Bool) -> Bool {
    guard accessible, let since = awaySince else { return false }
    awaySince = nil
    guard now - since >= minAway, now - lastPlayback > 8 else { return false }
    lastPlayback = now
    return true
  }
}

/// Pure login decision: once per login session, and only soon after the session began.
struct WelcomeLoginGate {
  /// How long after login the full welcome may still play (covers slow logins).
  static let window: TimeInterval = 240

  static func shouldPlay(
    sessionID: String?, lastWelcomedSessionID: String?, launchedAsLoginItem: Bool,
    sessionAge: TimeInterval?
  ) -> Bool {
    guard let sessionID, sessionID != lastWelcomedSessionID else { return false }
    if launchedAsLoginItem { return true }
    guard let sessionAge else { return false }
    return sessionAge < window
  }
}

@MainActor
final class WelcomeController: ObservableObject {
  static let shared = WelcomeController()

  enum Keys {
    static let enabled = "dayframeWelcomeEnabled"
    static let login = "dayframeWelcomeLogin"
    static let unlock = "dayframeWelcomeUnlock"
    static let soundMix = "dayframeWelcomeSoundMix"
    static let minAwayMinutes = "dayframeWelcomeMinAwayMinutes"
    static let previewed = "dayframeWelcomePreviewed"
    static let lastSession = "dayframeWelcomeLastSession"
  }

  static let minAwayChoices = [5, 10, 20, 30]

  @Published private(set) var previewed = UserDefaults.standard.bool(forKey: Keys.previewed)
  @Published private(set) var message: String?
  @Published private(set) var isPlaying = false

  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var pending: Task<Void, Never>?
  private var show: WelcomeShowPanel?
  private var gate = WelcomeEventGate()
  private var launchedAsLoginItem = false
  private let defaults = UserDefaults.standard

  static var enabled: Bool { UserDefaults.standard.bool(forKey: Keys.enabled) }
  static var ownsUnlockWelcome: Bool {
    enabled && UserDefaults.standard.object(forKey: Keys.unlock) as? Bool != false
  }

  private var soundMix: WelcomeSoundMix {
    WelcomeSoundMix(rawValue: defaults.string(forKey: Keys.soundMix) ?? "") ?? .laptop
  }

  func start() {
    defaults.register(defaults: [
      Keys.login: true, Keys.unlock: true, Keys.soundMix: WelcomeSoundMix.laptop.rawValue,
      Keys.minAwayMinutes: 10,
    ])
    let event = NSAppleEventManager.shared().currentAppleEvent
    launchedAsLoginItem =
      event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        == keyAELaunchedAsLogInItem
    applySettings()
    WallpaperManager.shared.start()

    guard Self.enabled, defaults.bool(forKey: Keys.login) else { return }
    let session = Self.sessionID
    let play = WelcomeLoginGate.shouldPlay(
      sessionID: session, lastWelcomedSessionID: defaults.string(forKey: Keys.lastSession),
      launchedAsLoginItem: launchedAsLoginItem, sessionAge: Self.sessionAge)
    // Whatever happens, this session has now been seen: a later relaunch never plays.
    defaults.set(session, forKey: Keys.lastSession)
    guard play else { return }
    pending = Task { [weak self] in
      // Wait (up to 10 s) until the desktop is really in use.
      for _ in 0..<40 {
        if Self.desktopAccessible { break }
        try? await Task.sleep(for: .milliseconds(250))
      }
      guard !Task.isCancelled, let self, Self.desktopAccessible else { return }
      self.play(.firstLaunch, preview: false)
    }
  }

  func applySettings() {
    for (center, token) in observers { center.removeObserver(token) }
    observers.removeAll()
    gate.minAway = TimeInterval(defaults.integer(forKey: Keys.minAwayMinutes)) * 60
    guard Self.enabled else {
      pending?.cancel()
      show?.cancel()
      return
    }
    // Remember this session when the welcome is first turned on, so enabling it (or the
    // next rebuild) doesn't play a "login" welcome in the middle of the day.
    if defaults.string(forKey: Keys.lastSession) == nil {
      defaults.set(Self.sessionID, forKey: Keys.lastSession)
    }
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ] {
      observe(workspace, name) { $0.markAway() }
    }
    // The same distributed notifications Dayframe's recorder and island use. They are
    // implementation-dependent, so the session dictionary is checked before playing.
    observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked")) {
      $0.markAway()
    }
    observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked")) {
      $0.returned()
    }
    observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.returned() }
    observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.returned() }
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name,
    action: @escaping @MainActor (WelcomeController) -> Void
  ) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        action(self)
      }
    }
    observers.append((center, token))
  }

  private func markAway() {
    gate.markAway(now: Date().timeIntervalSince1970)
    pending?.cancel()
    show?.cancel()
  }

  private func returned() {
    pending?.cancel()
    pending = Task { [weak self] in
      // Several "back" signals arrive together; wait for the screen to really be in use.
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled, let self, Self.enabled, Self.desktopAccessible,
        self.defaults.bool(forKey: Keys.unlock),
        self.gate.returnToSession(now: Date().timeIntervalSince1970, accessible: true)
      else { return }
      self.play(.dailyWake, preview: false)
    }
  }

  // MARK: - Session

  static var desktopAccessible: Bool { !RecordingWatchdog.isScreenLockedOrAsleep }

  /// This login session's unique ID (changes at every login).
  static var sessionID: String? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    if let id = session["CGSSessionUniqueSessionUUID"] as? String { return id }
    return (session[kCGSessionUserIDKey as String] as? Int).map { "uid-\($0)-\(bootTime)" }
  }

  /// Seconds since the Dock started: it launches once the user's session is up.
  static var sessionAge: TimeInterval? {
    guard
      let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        .first?
        .processIdentifier
    else { return nil }
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let start = info.kp_proc.p_starttime
    let started = TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    return Date().timeIntervalSince1970 - started
  }

  private static var bootTime: Int {
    var tv = timeval()
    var size = MemoryLayout<timeval>.stride
    var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
    return sysctl(&mib, 2, &tv, &size, nil, 0) == 0 ? tv.tv_sec : 0
  }

  // MARK: - Playing

  func preview(_ variant: WelcomeVariant) { play(variant, preview: true) }

  private func play(_ variant: WelcomeVariant, preview: Bool) {
    guard show == nil else { return }
    guard Self.desktopAccessible else {
      message = "The welcome plays while your desktop is unlocked."
      return
    }
    message = nil
    isPlaying = true
    let panel = WelcomeShowPanel(
      variant: variant, mix: soundMix, palette: DayframePaletteStore.shared.palette)
    show = panel
    panel.onFinished = { [weak self] in
      for number in panel.windowNumbers { IslandCaptureExclusion.unregister(number) }
      IslandCaptureExclusion.setShowOnScreen(false)
      guard let self else { return }
      self.show = nil
      self.isPlaying = false
      if preview {
        self.previewed = true
        self.defaults.set(true, forKey: Keys.previewed)
        self.message = "Preview complete."
      } else if variant == .firstLaunch, Self.desktopAccessible {
        StartOfDay.shared.run(reason: "login")
      }
    }
    // Keep the show out of Dayframe's own recordings.
    IslandCaptureExclusion.setShowOnScreen(true)
    panel.present()
    for number in panel.windowNumbers { IslandCaptureExclusion.register(number) }
  }
}
