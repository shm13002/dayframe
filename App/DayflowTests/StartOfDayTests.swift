import AppKit
import XCTest

@testable import Dayflow

/// Start of day: when the welcome plays, where windows go, the wallpaper, and the bundled show.
final class StartOfDayTests: XCTestCase {
  // MARK: Unlock (daily wake)

  func testUnlockWithoutLockingDoesNotPlay() {
    var gate = WelcomeEventGate()
    XCTAssertFalse(gate.returnToSession(now: 1_000, accessible: true).play)
  }

  func testShortAbsenceDoesNotPlayAndSaysWhy() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    XCTAssertEqual(
      gate.returnToSession(now: 1_000 + 300, accessible: true),
      .skip("away 5.0 min, needs 10.0 min"))
  }

  func testLongAbsencePlaysOnce() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    XCTAssertTrue(gate.returnToSession(now: 1_000 + 601, accessible: true).play)
    // A second "back" signal for the same unlock doesn't stack another show.
    XCTAssertFalse(gate.returnToSession(now: 1_000 + 602, accessible: true).play)
  }

  func testLockedReturnWaitsForUnlock() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    XCTAssertFalse(gate.returnToSession(now: 2_000, accessible: false).play)
    XCTAssertTrue(gate.returnToSession(now: 2_001, accessible: true).play)
  }

  func testAwayStartsAtFirstSignal() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    gate.markAway(now: 1_500)  // screen sleep after the lock
    XCTAssertTrue(gate.returnToSession(now: 1_000 + 650, accessible: true).play)
  }

  func testRapidRelockCannotStackShows() {
    var gate = WelcomeEventGate(minAway: 0)
    gate.markAway(now: 100)
    XCTAssertTrue(gate.returnToSession(now: 100, accessible: true).play)
    gate.markAway(now: 101)
    XCTAssertFalse(gate.returnToSession(now: 103, accessible: true).play)
    gate.markAway(now: 104)
    XCTAssertTrue(gate.returnToSession(now: 120, accessible: true).play)
  }

  // MARK: Login (first launch)

  func testKeepAliveLaunchInNewSessionPlays() {
    XCTAssertTrue(
      WelcomeLoginGate.decide(
        sessionID: "B", lastWelcomedSessionID: "A", launchedAsLoginItem: false, sessionAge: 20
      ).play)
  }

  func testLoginItemLaunchPlays() {
    XCTAssertTrue(
      WelcomeLoginGate.decide(
        sessionID: "B", lastWelcomedSessionID: "A", launchedAsLoginItem: true, sessionAge: nil
      ).play)
  }

  func testRelaunchInSameSessionDoesNotPlayAndSaysWhy() {
    XCTAssertEqual(
      WelcomeLoginGate.decide(
        sessionID: "A", lastWelcomedSessionID: "A", launchedAsLoginItem: true, sessionAge: 5),
      .skip("this login session was already welcomed"))
  }

  func testLateFirstLaunchInSessionDoesNotPlay() {
    XCTAssertFalse(
      WelcomeLoginGate.decide(
        sessionID: "B", lastWelcomedSessionID: "A", launchedAsLoginItem: false, sessionAge: 3_600
      ).play)
  }

  func testUnknownSessionDoesNotPlay() {
    XCTAssertFalse(
      WelcomeLoginGate.decide(
        sessionID: nil, lastWelcomedSessionID: nil, launchedAsLoginItem: true, sessionAge: 1
      ).play)
  }

  // MARK: Layout and wallpaper

  func testWindowSlotsStayInsideTheScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1470, height: 919)
    for slot in WindowSlot.allCases {
      guard let frame = slot.frame(in: visible) else { continue }
      XCTAssertTrue(visible.contains(frame), "\(slot) leaves the screen")
    }
    XCTAssertNil(WindowSlot.keep.frame(in: visible))
    let left = WindowSlot.leftTwoThirds.frame(in: visible)!
    let right = WindowSlot.rightThird.frame(in: visible)!
    XCTAssertLessThanOrEqual(left.maxX, right.minX)
  }

  func testRunSummarySaysWhatHappenedToEachApp() {
    let quiet = StartOfDayReport(opened: 2, placed: 2)
    XCTAssertEqual(quiet.summary(at: "9:01 AM"), "Ran at 9:01 AM: 2 opened, 2 placed.")
    let busy = StartOfDayReport(opened: 1, alreadyOpen: 2, failed: 1, placed: 0)
    XCTAssertEqual(
      busy.summary(at: "9:01 AM"),
      "Ran at 9:01 AM: 1 opened, 2 already open, 1 couldn't open, 0 placed.")
  }

  func testRunSummarySaysWhetherTheFocusShortcutRan() {
    var report = StartOfDayReport(opened: 1, placed: 1)
    report.focus = ("Work Focus", nil)
    XCTAssertEqual(
      report.summary(at: "9:01 AM"), "Ran at 9:01 AM: 1 opened, 1 placed. Work Focus is on.")
    report.focus = ("Work Focus", "The shortcut couldn't be found.")
    XCTAssertTrue(report.summary(at: "9:01 AM").hasSuffix("Work Focus didn't run."))
  }

  func testFocusShortcutNamesComeFromTheShortcutsList() {
    XCTAssertEqual(
      FocusShortcut.names(fromList: "Work Focus\n  Morning Music \n\nSet Up Desk\n"),
      ["Work Focus", "Morning Music", "Set Up Desk"])
    XCTAssertEqual(FocusShortcut.names(fromList: ""), [])
  }

  @MainActor
  func testWallpaperRendersAtNativeSizeForEveryPalette() throws {
    let pixels = CGSize(width: 2560, height: 1664)
    for palette in DayframePalette.allCases {
      for dark in [true, false] {
        let data = try XCTUnwrap(
          WallpaperManager.render(palette: palette, dark: dark, pixels: pixels))
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 2560)
        XCTAssertEqual(image.pixelsHigh, 1664)
        // To look at them: TEST_RUNNER_DAYFRAME_DUMP_WALLPAPERS=1 xcodebuild test … writes each
        // one to the test's temp folder (xcodebuild passes TEST_RUNNER_-prefixed variables on).
        if ProcessInfo.processInfo.environment["DAYFRAME_DUMP_WALLPAPERS"] == "1" {
          try data.write(
            to: FileManager.default.temporaryDirectory.appendingPathComponent(
              "dayframe-wallpaper-\(palette.rawValue)-\(dark ? "dark" : "light").png"))
        }
      }
    }
  }

  func testWelcomeAssetsAreBundled() {
    let bundle = Bundle(for: WelcomeController.self)
    XCTAssertNotNil(bundle.url(forResource: "welcome", withExtension: "html"))
    for name in ["first-launch", "daily-wake"] {
      for mix in ["laptop", "cinematic"] {
        XCTAssertNotNil(
          bundle.url(forResource: "welcome-\(name)_\(mix)", withExtension: "m4a"), "\(name) \(mix)")
      }
    }
  }
}
