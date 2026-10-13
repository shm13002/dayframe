import AppKit
import XCTest
@testable import Dayflow

final class WelcomeEventGateTests: XCTestCase {
  // MARK: Unlock (daily wake)

  func testUnlockWithoutLockingDoesNotPlay() {
    var gate = WelcomeEventGate()
    XCTAssertFalse(gate.returnToSession(now: 1_000, accessible: true))
  }

  func testShortAbsenceDoesNotPlay() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    XCTAssertFalse(gate.returnToSession(now: 1_000 + 300, accessible: true))
  }

  func testLongAbsencePlaysOnce() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    XCTAssertTrue(gate.returnToSession(now: 1_000 + 601, accessible: true))
    // A second "back" signal for the same unlock doesn't stack another show.
    XCTAssertFalse(gate.returnToSession(now: 1_000 + 602, accessible: true))
  }

  func testLockedReturnWaitsForUnlock() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    XCTAssertFalse(gate.returnToSession(now: 2_000, accessible: false))
    XCTAssertTrue(gate.returnToSession(now: 2_001, accessible: true))
  }

  func testAwayStartsAtFirstSignal() {
    var gate = WelcomeEventGate(minAway: 600)
    gate.markAway(now: 1_000)
    gate.markAway(now: 1_500)  // screen sleep after the lock
    XCTAssertTrue(gate.returnToSession(now: 1_000 + 650, accessible: true))
  }

  func testRapidRelockCannotStackShows() {
    var gate = WelcomeEventGate(minAway: 0)
    gate.markAway(now: 100)
    XCTAssertTrue(gate.returnToSession(now: 100, accessible: true))
    gate.markAway(now: 101)
    XCTAssertFalse(gate.returnToSession(now: 103, accessible: true))
    gate.markAway(now: 104)
    XCTAssertTrue(gate.returnToSession(now: 120, accessible: true))
  }

  // MARK: Login (first launch)

  func testKeepAliveLaunchInNewSessionPlays() {
    XCTAssertTrue(
      WelcomeLoginGate.shouldPlay(
        sessionID: "B", lastWelcomedSessionID: "A", launchedAsLoginItem: false, sessionAge: 20))
  }

  func testLoginItemLaunchPlays() {
    XCTAssertTrue(
      WelcomeLoginGate.shouldPlay(
        sessionID: "B", lastWelcomedSessionID: "A", launchedAsLoginItem: true, sessionAge: nil))
  }

  func testRelaunchInSameSessionDoesNotPlay() {
    XCTAssertFalse(
      WelcomeLoginGate.shouldPlay(
        sessionID: "A", lastWelcomedSessionID: "A", launchedAsLoginItem: true, sessionAge: 5))
  }

  func testLateFirstLaunchInSessionDoesNotPlay() {
    XCTAssertFalse(
      WelcomeLoginGate.shouldPlay(
        sessionID: "B", lastWelcomedSessionID: "A", launchedAsLoginItem: false, sessionAge: 3_600))
  }

  func testUnknownSessionDoesNotPlay() {
    XCTAssertFalse(
      WelcomeLoginGate.shouldPlay(
        sessionID: nil, lastWelcomedSessionID: nil, launchedAsLoginItem: true, sessionAge: 1))
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

  @MainActor
  func testWallpaperRendersAtNativeSizeForEveryPalette() throws {
    let pixels = CGSize(width: 2560, height: 1664)
    for palette in DayframePalette.allCases {
      for dark in [true, false] {
        let data = try XCTUnwrap(WallpaperManager.render(palette: palette, dark: dark, pixels: pixels))
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 2560)
        XCTAssertEqual(image.pixelsHigh, 1664)
        try data.write(
          to: FileManager.default.temporaryDirectory.appendingPathComponent(
            "dayframe-wallpaper-\(palette.rawValue)-\(dark ? "dark" : "light").png"))
      }
    }
  }

  func testWelcomeAssetsAreBundled() {
    let bundle = Bundle(for: WelcomeController.self)
    XCTAssertNotNil(bundle.url(forResource: "welcome", withExtension: "html"))
    for name in ["first-launch", "daily-wake"] {
      for mix in ["laptop", "cinematic"] {
        XCTAssertNotNil(bundle.url(forResource: "welcome-\(name)_\(mix)", withExtension: "m4a"), "\(name) \(mix)")
      }
    }
  }
}
