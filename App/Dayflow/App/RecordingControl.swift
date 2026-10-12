import Foundation
import ScreenCaptureKit

enum RecordingControlMode: Equatable {
  case active
  case pausedTimed(endTime: Date)
  case pausedIndefinite
  case stopped
}

@MainActor
enum RecordingControl {
  static func currentMode() -> RecordingControlMode {
    currentMode(appState: .shared, pauseManager: .shared)
  }

  static func currentMode(
    appState: AppState,
    pauseManager: PauseManager
  ) -> RecordingControlMode {
    if appState.isRecording && pauseManager.isPaused {
      assertionFailure("Recording cannot be active while pause metadata is still set")
      return .active
    }

    if let endTime = pauseManager.pauseEndTime {
      return .pausedTimed(endTime: endTime)
    }

    if pauseManager.isPausedIndefinitely {
      return .pausedIndefinite
    }

    return appState.isRecording ? .active : .stopped
  }

  static func start(reason: String) {
    Task { @MainActor in
      guard await hasScreenRecordingPermission() else {
        print("[RecordingControl] Screen recording permission not granted; start ignored")
        ScreenRecordingPermissionNotice.post(reason: "recording_control_start")
        // Dayframe: a click on Resume should never do nothing. Ask macOS (adds Dayframe to
        // the Screen Recording list / shows the system prompt) and open that settings page.
        if reason.hasPrefix("user") {
          _ = CGRequestScreenCaptureAccess()
          ScreenRecordingPermissionNotice.openSystemSettings()
        }
        return
      }

      PauseManager.shared.clearPauseState()
      AppState.shared.setRecording(true, analyticsReason: reason)
    }
  }

  static func stop(reason: String) {
    PauseManager.shared.clearPauseState()
    AppState.shared.setRecording(false, analyticsReason: reason)
  }

  private static func hasScreenRecordingPermission() async -> Bool {
    guard CGPreflightScreenCaptureAccess() else { return false }

    do {
      _ = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
      )
      return true
    } catch {
      return false
    }
  }
}
