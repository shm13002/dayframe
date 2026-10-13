import XCTest

@testable import Dayflow

/// Dayframe: the notch island and the React Briefing bridge.
final class NotchIslandTests: XCTestCase {

  private let notched = NotchGeometry(
    screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956), notchX: 637, notchWidth: 196, height: 32,
    hasNotch: true)

  // MARK: - Geometry

  func testPillWrapsTheNotchWithBothWings() {
    let pill = notched.pillRect
    XCTAssertEqual(pill.minX, 637 - NotchGeometry.leftWing)
    XCTAssertEqual(pill.width, 196 + NotchGeometry.leftWing + NotchGeometry.rightWing)
    XCTAssertEqual(pill.height, 32)
    XCTAssertEqual(pill.minY, 0)
  }

  func testPillWindowSitsFlushWithTheTopOfTheScreen() {
    let frame = notched.pillWindowFrame
    XCTAssertEqual(frame.maxY, 956)
    XCTAssertEqual(frame.minX, 637 - NotchGeometry.leftWing)
  }

  func testPillRadiusNeverExceedsHalfTheHeight() {
    XCTAssertLessThanOrEqual(notched.pillRadius, notched.height / 2)
    let thin = NotchGeometry(
      screenFrame: .init(x: 0, y: 0, width: 800, height: 600), notchX: 400, notchWidth: 0, height: 20, hasNotch: false)
    XCTAssertEqual(thin.pillRadius, 8)
    XCTAssertEqual(thin.pillRect.width, NotchGeometry.leftWing + NotchGeometry.rightWing)
  }

  // MARK: - Payload contract (must match Web/src/island/types.ts)

  func testPayloadEncodesTheKeysThePageReads() throws {
    let stats = IslandStats(
      day: "2026-10-12", cardCount: 3, trackedMinutes: 187, focusMinutes: 108, focusGoalMinutes: 270,
      categories: [.init(name: "Studying", minutes: 118, colorHex: "#7B83FF")])
    let payload = IslandPayload(
      variant: .startup, geometry: notched, greeting: "Good evening, Shahzi",
      lines: [.init(label: "Next", text: "Ship it")], stats: stats, accentHex: "#F3854B", recording: true,
      reducedMotion: false)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])

    XCTAssertEqual(
      Set(json.keys),
      [
        "variant", "screen", "notch", "pill", "greeting", "lines", "focus", "trackedMinutes", "categories",
        "accent", "recording", "reducedMotion",
      ])
    XCTAssertEqual(json["variant"] as? String, "startup")
    let notch = try XCTUnwrap(json["notch"] as? [String: Double])
    XCTAssertEqual(notch, ["x": 637, "width": 196, "height": 32])
    let pill = try XCTUnwrap(json["pill"] as? [String: Double])
    XCTAssertEqual(Set(pill.keys), ["leftWing", "rightWing", "height", "radius"])
    XCTAssertEqual(json["focus"] as? [String: Int], ["minutes": 108, "goalMinutes": 270])
    let category = try XCTUnwrap((json["categories"] as? [[String: Any]])?.first)
    XCTAssertEqual(category["color"] as? String, "#7B83FF")
    XCTAssertEqual((json["lines"] as? [[String: String]])?.first, ["label": "Next", "text": "Ship it"])
  }

  func testEveryCueThePageCanSendHasASound() {
    // Web/src/island/types.ts `Cue`
    let pageCues = [
      "drip", "pop", "grain", "bloop", "eyes", "ping1", "ping2", "ping3", "streamStart", "count", "swoosh",
      "finale", "settle",
    ]
    for cue in pageCues { XCTAssertNotNil(IslandCue(rawValue: cue), cue) }
  }

  // MARK: - Stats

  func testFocusPercentAndGoal() {
    var stats = IslandStats.empty
    XCTAssertEqual(stats.focusPercent, 0)
    XCTAssertFalse(stats.goalReached)
    stats.focusGoalMinutes = 270
    stats.focusMinutes = 108
    XCTAssertEqual(stats.focusPercent, 40)
    XCTAssertFalse(stats.goalReached)
    stats.focusMinutes = 270
    XCTAssertTrue(stats.goalReached)
  }

  func testDurationFormatMatchesThePage() {
    XCTAssertEqual(0.islandDuration, "0m")
    XCTAssertEqual(45.islandDuration, "45m")
    XCTAssertEqual(60.islandDuration, "1h 0m")
    XCTAssertEqual(187.islandDuration, "3h 7m")
    XCTAssertEqual((-5).islandDuration, "0m")
  }

  // MARK: - Briefing page bridge

  func testBriefingPageMessages() {
    XCTAssertEqual(BriefingPageMessage(body: ["type": "ready"]), .ready)
    XCTAssertEqual(BriefingPageMessage(body: ["type": "showTimeline"]), .showTimeline)
    XCTAssertEqual(BriefingPageMessage(body: ["type": "openMore", "page": "memory"]), .openMore("memory"))
    XCTAssertNil(BriefingPageMessage(body: ["type": "openMore"]))
    XCTAssertNil(BriefingPageMessage(body: ["type": "rm -rf"]))
    XCTAssertNil(BriefingPageMessage(body: "ready"))
  }

  func testBriefingContextEncodesCategoryColors() throws {
    let context = BriefingPageContext(
      palette: "lagoon", dark: true, categories: [.init(name: "Studying", color: "#7B83FF")])
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
    XCTAssertEqual(json["palette"] as? String, "lagoon")
    XCTAssertEqual(json["dark"] as? Bool, true)
    XCTAssertEqual((json["categories"] as? [[String: String]])?.first?["color"], "#7B83FF")
  }

  // MARK: - Capture exclusion

  func testCaptureExclusionRegistry() {
    IslandCaptureExclusion.register(4242)
    XCTAssertTrue(IslandCaptureExclusion.windowIDs.contains(4242))
    IslandCaptureExclusion.unregister(4242)
    XCTAssertFalse(IslandCaptureExclusion.windowIDs.contains(4242))
    IslandCaptureExclusion.register(0)
    XCTAssertFalse(IslandCaptureExclusion.windowIDs.contains(0))
    IslandCaptureExclusion.setShowOnScreen(true)
    XCTAssertTrue(IslandCaptureExclusion.showOnScreen)
    IslandCaptureExclusion.setShowOnScreen(false)
    XCTAssertFalse(IslandCaptureExclusion.showOnScreen)
  }
}
