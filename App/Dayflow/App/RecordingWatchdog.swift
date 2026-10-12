//
//  RecordingWatchdog.swift
//  Dayframe
//
//  Keeps recording on. Every 30 s, and right after wake / unlock, it restarts
//  capture if it stopped. A timed pause you chose (15 min, 1 h…) is respected
//  until it ends; "pause indefinitely" is overridden. If macOS has revoked the
//  Screen Recording permission it can't record, so it shows the permission
//  notice (at most every 10 minutes) instead.
//

import AppKit
import CoreGraphics

@MainActor
final class RecordingWatchdog {
  static let shared = RecordingWatchdog()

  private var timer: Timer?
  private var lastNotice = Date.distantPast

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
    guard !AppState.shared.isRecording else { return }
    let pause = PauseManager.shared
    if pause.isPaused && !pause.isPausedIndefinitely { return }  // honor a timed pause
    if CGPreflightScreenCaptureAccess() {
      RecordingControl.start(reason: reason)
    } else if Date().timeIntervalSince(lastNotice) > 600 {
      lastNotice = Date()
      ScreenRecordingPermissionNotice.post(reason: "watchdog_missing_permission")
    }
  }
}
