import AppKit
import CoreGraphics
import Foundation

enum ScreenRecordingPermissionNotice {
  static var isGranted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  static func post(reason: String) {
    let notification = {
      NotificationCenter.default.post(
        name: .showScreenRecordingPermissionNotice,
        object: nil,
        userInfo: ["reason": reason]
      )
    }

    if Thread.isMainThread {
      notification()
    } else {
      DispatchQueue.main.async(execute: notification)
    }
  }

  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    else { return }

    NSWorkspace.shared.open(url)
  }

  /// Dayframe: macOS ties the Screen Recording grant to the app's code signature. If an older
  /// build was allowed, the switch can look "on" while macOS still denies this build. Clearing
  /// Dayframe's own entry and asking again fixes that.
  static func resetAndRequest() {
    let bundleID = Bundle.main.bundleIdentifier ?? "local.dayframe.app"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    task.arguments = ["reset", "ScreenCapture", bundleID]
    do {
      try task.run()
      task.waitUntilExit()
      print("[ScreenRecordingPermissionNotice] tccutil reset exit \(task.terminationStatus)")
    } catch {
      print("[ScreenRecordingPermissionNotice] tccutil reset failed: \(error)")
    }
    _ = CGRequestScreenCaptureAccess()
    openSystemSettings()
  }

  /// Screen Recording access only takes effect after the app restarts.
  @MainActor
  static func relaunchApp() {
    let path = Bundle.main.bundlePath
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
    try? task.run()
    AppDelegate.allowTermination = true
    NSApp.terminate(nil)
  }
}
