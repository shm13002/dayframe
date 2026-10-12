//
//  RecordingWatchdog.swift
//  Dayframe
//
//  Keeps recording on. Every 30 s, and right after wake / unlock, it:
//  - restarts capture if it stopped (a timed pause you chose is respected until
//    it ends; "pause indefinitely" is overridden);
//  - restarts capture if it claims to be on but no frame was saved for 3 minutes
//    while you're at the Mac (a silent stall);
//  - if macOS blocks Screen Recording, shows the in-app notice and a Mac
//    notification (at most every 10 minutes / every hour) so it never fails quietly.
//

import AppKit
import CoreGraphics

@MainActor
final class RecordingWatchdog {
  static let shared = RecordingWatchdog()

  private var timer: Timer?
  private var lastNotice = Date.distantPast
  private var lastSystemNotification = Date.distantPast
  private var lastStallRestart = Date.distantPast

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
      Task { @MainActor in RecordingWatchdog.shared.check(reason: "watchdog") }
    }
    let ws = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      ws.addObserver(forName: name, object: nil, queue: .main) { _ in
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 3_000_000_000)
          RecordingWatchdog.shared.check(reason: "wake")
        }
      }
    }
    DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
    ) { _ in
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        RecordingWatchdog.shared.check(reason: "unlock")
      }
    }
  }

  func check(reason: String) {
    guard UserDefaults.standard.bool(forKey: "didOnboard") else { return }
    let granted = CGPreflightScreenCaptureAccess()
    if granted { NotificationService.shared.clearRecordingBlockedNotification() }

    if AppState.shared.isRecording {
      restartIfStalled()
      return
    }
    let pause = PauseManager.shared
    if pause.isPaused && !pause.isPausedIndefinitely { return }  // honor a timed pause
    if granted {
      RecordingControl.start(reason: reason)
      return
    }
    if Date().timeIntervalSince(lastNotice) > 600 {
      lastNotice = Date()
      ScreenRecordingPermissionNotice.post(reason: "watchdog_missing_permission")
    }
    if Date().timeIntervalSince(lastSystemNotification) > 3600 {
      lastSystemNotification = Date()
      NotificationService.shared.notifyRecordingBlocked()
    }
  }

  /// Recording is "on" but nothing has been saved lately: restart the capture pipeline.
  private func restartIfStalled() {
    guard !Self.isScreenLockedOrAsleep else { return }
    // Away from the Mac (screensaver likely): the recorder pauses itself; don't fight it.
    if let idle = InputIdleSnapshot.currentIdleSeconds(), idle > 600 { return }
    guard let newest = StorageManager.shared.newestScreenshotCapturedAt() else { return }
    let age = Date().timeIntervalSince1970 - TimeInterval(newest)
    let limit = max(180, ScreenshotConfig.interval * 6)
    guard age > limit, Date().timeIntervalSince(lastStallRestart) > 300 else { return }
    lastStallRestart = Date()
    print("[RecordingWatchdog] No frame for \(Int(age)) s while recording; restarting capture")
    AppState.shared.setRecording(false, analyticsReason: "watchdog_stall", persistPreference: false)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      RecordingControl.start(reason: "watchdog_stall")
    }
  }

  private static var isScreenLockedOrAsleep: Bool {
    if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return true }
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (session["CGSSessionScreenIsLocked"] as? Bool) == true
      || (session["CGSSessionOnConsoleKey"] as? Bool) == false
  }
}
