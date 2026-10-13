//
//  IslandController.swift
//  Dayframe
//
//  Runs the notch island: the always-on pill, the startup show after time away,
//  and the small moments (a new card, focus goal reached, pause/resume, the
//  end-of-day recap). Settings live under Settings › Other › Notch island.
//

import AppKit
import Combine
import Foundation

@MainActor
final class IslandController {
  static let shared = IslandController()

  enum Keys {
    static let enabled = "islandEnabled"
    static let startupEnabled = "islandStartupEnabled"
    static let minAwayMinutes = "islandMinAwayMinutes"
    static let displayName = "islandDisplayName"
    static let momentCardBorn = "islandMomentCardBorn"
    static let momentGoal = "islandMomentGoal"
    static let momentRecording = "islandMomentRecording"
    static let momentRecap = "islandMomentRecap"
    static let lastGoalDay = "islandLastGoalDay"
  }

  static let minAwayChoices = [5, 10, 20, 30]

  private let defaults = UserDefaults.standard
  private var pill: NotchPillPanel?
  private var show: IslandShowPanel?
  private var observers: Set<AnyCancellable> = []
  private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
  private var refreshTask: Task<Void, Never>?
  private var lookTimer: Timer?
  private var awayStart: Date?
  private var lastStartupAt: Date?
  private var unlockCheck: Task<Void, Never>?
  private var stats: IslandStats = .empty
  private var started = false

  private init() {}

  // MARK: - Settings

  private func bool(_ key: String, default value: Bool = true) -> Bool {
    defaults.object(forKey: key) as? Bool ?? value
  }

  var isEnabled: Bool { bool(Keys.enabled) }
  var minAway: TimeInterval {
    TimeInterval(defaults.object(forKey: Keys.minAwayMinutes) as? Int ?? 10) * 60
  }

  /// "Shahzi": the settings override, else the first word of the Mac account's full name.
  var displayName: String {
    let custom = (defaults.string(forKey: Keys.displayName) ?? "").trimmingCharacters(
      in: .whitespaces)
    if !custom.isEmpty { return custom }
    return NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
  }

  /// Settings changed: start, stop or refresh to match.
  func applySettings() {
    if isEnabled { start() } else { stop() }
  }

  // MARK: - Lifecycle

  func start() {
    guard isEnabled, UserDefaults.standard.bool(forKey: "didOnboard") else { return }
    // Unit tests launch the app as their host; never put a second pill on screen for them.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    guard !started, let geometry = NotchGeometry.current() else { return }
    started = true

    let model = NotchPillModel(geometry: geometry)
    model.recording = AppState.shared.isRecording
    model.accentHex = DayframePaletteStore.shared.palette.accentHex
    model.onToggleRecording = { [weak self] in self?.toggleRecording() }
    model.onOpenApp = { Self.openMainWindow() }
    model.onReplay = { [weak self] in self?.playStartup(force: true) }
    model.onModeChange = { [weak self] mode in self?.pillModeChanged(mode) }
    let panel = NotchPillPanel(model: model)
    pill = panel
    panel.show(fadeIn: true)

    observeSystem()
    observeApp(model: model)
    startRefreshing()
    startLookTimer()
  }

  func stop() {
    guard started else { return }
    started = false
    show?.cancel()
    refreshTask?.cancel()
    unlockCheck?.cancel()
    lookTimer?.invalidate()
    lookTimer = nil
    observers.removeAll()
    for (center, token) in notificationTokens { center.removeObserver(token) }
    notificationTokens.removeAll()
    if let pill {
      IslandCaptureExclusion.unregister(pill.windowNumber)
      pill.hide()
    }
    pill = nil
  }

  // MARK: - Observing

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping () -> Void
  ) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { block() }
    }
    notificationTokens.append((center, token))
  }

  private func observeSystem() {
    let ws = NSWorkspace.shared.notificationCenter
    let distributed = DistributedNotificationCenter.default()
    // Leaving: remember when the time away started (first signal wins).
    for name in [
      NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ] {
      observe(ws, name) { [weak self] in self?.markAway() }
    }
    observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
      self?.markAway()
    }

    // Coming back. Unlock is the main signal; the others cover a wake without a password.
    observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
      self?.cameBack()
    }
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      observe(ws, name) { [weak self] in self?.cameBack() }
    }

    observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
      [weak self] in
      guard let self, let geometry = NotchGeometry.current() else { return }
      self.pill?.update(geometry: geometry)
    }
    observe(NotificationCenter.default, .timelineDataUpdated) { [weak self] in self?.refreshSoon() }
  }

  private func observeApp(model: NotchPillModel) {
    AppState.shared.$isRecording
      .removeDuplicates()
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self, weak model] recording in
        model?.recording = recording
        if self?.bool(Keys.momentRecording) == true {
          IslandSound.shared.play(recording ? .openEyes : .closeEyes)
        }
      }
      .store(in: &observers)

    DayframePaletteStore.shared.$palette
      .receive(on: DispatchQueue.main)
      .sink { [weak model] palette in model?.accentHex = palette.accentHex }
      .store(in: &observers)
  }

  // MARK: - Away and back

  private func markAway() {
    if awayStart == nil { awayStart = Date() }
    unlockCheck?.cancel()
    if let show {
      show.cancel()
      self.show = nil
    }
  }

  private func cameBack() {
    unlockCheck?.cancel()
    unlockCheck = Task { [weak self] in
      // Several "back" signals arrive together; wait for the screen to really be in use.
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled, let self, !RecordingWatchdog.isScreenLockedOrAsleep else { return }
      let away = self.awayStart.map { Date().timeIntervalSince($0) } ?? 0
      self.awayStart = nil
      self.refreshSoon()
      if away >= self.minAway { self.playStartup(force: false, away: away) }
    }
  }

  // MARK: - Stats

  private func startRefreshing() {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refreshStats()
        try? await Task.sleep(for: .seconds(60))
      }
    }
  }

  private func refreshSoon() {
    Task { await refreshStats() }
  }

  private func refreshStats() async {
    let categories = CategoryStore.shared.categories
    let next = await Task.detached(priority: .utility) {
      IslandStats.compute(categories: categories)
    }.value
    let previous = stats
    stats = next
    pill?.model.stats = next

    guard previous.day == next.day, !previous.day.isEmpty else { return }
    if next.cardCount > previous.cardCount, bool(Keys.momentCardBorn) {
      cardBorn()
    }
    if next.goalReached, !previous.goalReached, bool(Keys.momentGoal),
      defaults.string(forKey: Keys.lastGoalDay) != next.day
    {
      defaults.set(next.day, forKey: Keys.lastGoalDay)
      present(.goal)
    }
  }

  // MARK: - Moments

  private func cardBorn() {
    guard let model = pill?.model, show == nil else { return }
    model.dripSignal += 1
    model.blinkSignal += 1
    IslandSound.shared.play(.blink)
  }

  /// Called by DailyRecapScheduler when today's recap is ready.
  func dailyRecapReady() {
    guard started, bool(Keys.momentRecap), !RecordingWatchdog.isScreenLockedOrAsleep else { return }
    Task {
      await refreshStats()
      present(.recap)
    }
  }

  func playStartup(force: Bool, away: TimeInterval = 0) {
    guard started else { return }
    if !force {
      guard !WelcomeController.ownsUnlockWelcome else { return }
      guard bool(Keys.startupEnabled) else { return }
      if let last = lastStartupAt, Date().timeIntervalSince(last) < 120 { return }
    }
    lastStartupAt = Date()
    Task {
      await refreshStats()
      present(.startup, away: away)
    }
  }

  private func present(_ variant: IslandPayload.Variant, away: TimeInterval = 0) {
    guard started, show == nil, let pill else { return }
    Task {
      let lines = await self.lines(for: variant, away: away)
      guard self.show == nil, let geometry = NotchGeometry.current() else { return }
      let payload = IslandPayload(
        variant: variant,
        geometry: geometry,
        greeting: greeting(for: variant),
        lines: lines,
        stats: stats,
        accentHex: DayframePaletteStore.shared.palette.accentHex,
        recording: AppState.shared.isRecording,
        reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      )
      let panel = IslandShowPanel(payload: payload, geometry: geometry)
      panel.onStarted = {
        IslandCaptureExclusion.setShowOnScreen(true)
        pill.hide()
      }
      panel.onFinished = { [weak self] in
        IslandCaptureExclusion.setShowOnScreen(false)
        self?.show = nil
        if self?.started == true { pill.show(fadeIn: false) }
      }
      self.show = panel
      panel.present()
    }
  }

  private func greeting(for variant: IslandPayload.Variant) -> String {
    switch variant {
    case .goal: return "Focus goal reached"
    case .recap: return "Today, recapped"
    case .startup:
      let hour = Calendar.current.component(.hour, from: Date())
      let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
      return "\(part), \(displayName)"
    }
  }

  private func lines(for variant: IslandPayload.Variant, away: TimeInterval) async -> [IslandPayload
    .Line]
  {
    let s = stats
    let focus =
      s.focusGoalMinutes > 0
      ? "\(s.focusMinutes.islandDuration) of \(s.focusGoalMinutes.islandDuration) focus" : nil
    switch variant {
    case .goal:
      return [.init(label: "", text: "\(s.focusMinutes.islandDuration) of focus today")]
    case .recap:
      let n = s.categories.count
      return [
        .init(
          label: "",
          text:
            "\(s.trackedMinutes.islandDuration) tracked across \(n) \(n == 1 ? "category" : "categories")"
        )
      ]
    case .startup:
      var out: [IslandPayload.Line] = []
      let sections = await briefingSections()
      if let leftOff = sections?.leftOff, !leftOff.isEmpty {
        out.append(.init(label: "Left off", text: firstSentence(leftOff)))
      } else if away > 0 {
        out.append(.init(label: "Away", text: Int(away / 60).islandDuration))
      }
      if let next = sections?.nextSteps.first, !next.isEmpty {
        out.append(.init(label: "Next", text: next))
      }
      out.append(
        .init(
          label: "Today",
          text: [s.trackedMinutes.islandDuration + " tracked", focus].compactMap { $0 }.joined(
            separator: ", ")))
      return out
    }
  }

  /// The latest briefing, if the Briefing service answers within 1.5 s. Never holds up a show for long:
  /// whichever finishes first wins and the other is cancelled (the request is cancellable).
  private func briefingSections() async -> BriefingSections? {
    let service = BriefingService.shared
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await service.refresh() }
      group.addTask { try? await Task.sleep(for: .milliseconds(1500)) }
      await group.next()
      group.cancelAll()
    }
    let sections = service.sections
    return sections.isEmpty ? nil : sections
  }

  private func firstSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
      return String(trimmed[...end])
    }
    return trimmed
  }

  // MARK: - Pill actions

  private func pillModeChanged(_ mode: NotchPillModel.Mode) {
    switch mode {
    case .hover:
      IslandSound.shared.play(.hover)
    case .open:
      IslandSound.shared.play(.open)
      Task {
        let sections = await briefingSections()
        pill?.model.nextThing = sections?.nextSteps.first
      }
    case .rest:
      break
    }
  }

  private func toggleRecording() {
    if AppState.shared.isRecording {
      PauseManager.shared.pause(for: .minutes30, source: .menuBar)
    } else {
      PauseManager.shared.resume(source: .userClickedMenuBar)
    }
  }

  static func openMainWindow() {
    let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    if showDockIcon { NSApp.setActivationPolicy(.regular) }
    NSApp.unhide(nil)
    MainWindowController.shared.showMainWindow()
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - Eyes follow the pointer (a little)

  private func startLookTimer() {
    lookTimer?.invalidate()
    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateLook() }
    }
    RunLoop.main.add(timer, forMode: .common)
    lookTimer = timer
  }

  private func updateLook() {
    guard let model = pill?.model, model.recording else { return }
    let g = model.geometry
    let eyes = CGPoint(
      x: g.screenFrame.minX + g.notchX + g.notchWidth + NotchPillLayout.eyesInset,
      y: g.screenFrame.maxY - g.height / 2)
    let mouse = NSEvent.mouseLocation
    let dx = max(-1, min(1, (mouse.x - eyes.x) / 400)) * 1.5
    let dy = max(-1, min(1, (eyes.y - mouse.y) / 300)) * 1.0
    let next = CGSize(width: (dx * 4).rounded() / 4, height: (dy * 4).rounded() / 4)
    if next != model.lookOffset { model.lookOffset = next }
  }
}
