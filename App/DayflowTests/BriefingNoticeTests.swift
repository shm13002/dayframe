import AppKit
import SwiftUI
import XCTest

@testable import Dayflow

/// Briefing's messages in the notch pill: the hand-off files, what the peek says, and how the
/// briefing text is split. `testRenderNoticeCards` also writes PNGs of each state for a visual check.
@MainActor
final class BriefingNoticeTests: XCTestCase {
  private var dir: URL!

  override func setUp() async throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "notices-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private let briefing = """
    WHERE YOU LEFT OFF: You just finished configuring Grok voice settings and reviewing pull requests \
    in VS Code (2026-10-12#4). Recent activity shows a shift to researching MacBook accessories.
    YOUR GOAL: Draft technical proposals for Dayframe API (memory/projects/dayframe.md).
    NEXT STEPS:
    1. Continue drafting the Dayframe API proposal in Grok chat
    2. Investigate free local AI voice alternatives
    3. Execute the planned file cleanup for VS Code and Obsidian

    Refs: memory/projects/code-review.md, memory/open-loops.md

    Question for you: Earlier memory says "Uses VS Code for debugging" (2026-10-12#23), but recent \
    activity says otherwise. Which is right? (+2 more) Resolve it in the dashboard, Memory tab.

    2 remembered fact(s) are out of date and were not used; confirm or remove them in Memory.
    """

  private func write(_ obj: [String: Any], id: String) throws {
    let data = try JSONSerialization.data(withJSONObject: obj)
    try data.write(to: dir.appendingPathComponent("\(id).json"))
  }

  // MARK: Hand-off

  func testTakeReadsAcknowledgesAndRemovesTheNotice() throws {
    let id = "1791900000000-123-abc123"
    try write(["id": id, "kind": "brief", "title": "Where you left off", "text": briefing], id: id)
    let notice = try XCTUnwrap(BriefingNoticeInbox.take(id: id, in: dir))
    XCTAssertEqual(notice.kind, .brief)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id).ack").path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id).json").path))
  }

  func testIdsThatCouldLeaveTheFolderAreRejected() {
    for id in ["../config", "abc/def", "", "UPPER", String(repeating: "a", count: 65)] {
      XCTAssertFalse(BriefingNoticeInbox.isValidID(id), id)
      XCTAssertNil(BriefingNoticeInbox.take(id: id, in: dir))
    }
    XCTAssertTrue(BriefingNoticeInbox.isValidID("1791900000000-123-abc123"))
  }

  func testUnknownKindOrMismatchedIdIsIgnored() throws {
    try write(["id": "1-1-aa", "kind": "dialog"], id: "1-1-aa")
    XCTAssertNil(BriefingNoticeInbox.take(id: "1-1-aa", in: dir))
    XCTAssertNil(BriefingNotice(json: Data(#"{"id":"../x","kind":"brief"}"#.utf8)))
  }

  func testAnswersAreWrittenForBriefingToRead() throws {
    let ask = BriefingNotice(
      id: "1-2-bb", kind: .ask, title: "Check-in", text: "", prompt: "What are you on?",
      defaultAnswer: "", expires: nil)
    BriefingNoticeInbox.answer(ask, text: "  the notch card ", in: dir)
    let saved =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: dir.appendingPathComponent("1-2-bb.answer"))) as? [String: Any]
    XCTAssertEqual(saved?["text"] as? String, "the notch card")
    BriefingNoticeInbox.answer(ask, text: "   ", in: dir)
    let skipped =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: dir.appendingPathComponent("1-2-bb.answer"))) as? [String: Any]
    XCTAssertEqual(skipped?["skip"] as? Bool, true)
  }

  func testAskExpiresWhenBriefingStopsWaiting() throws {
    let json = Data(
      #"{"id":"1-3-cc","kind":"ask","prompt":"Goal?","created":1000,"wait":600}"#.utf8)
    let notice = try XCTUnwrap(BriefingNotice(json: json))
    XCTAssertEqual(notice.expires, Date(timeIntervalSince1970: 1600))
  }

  // MARK: What it says

  func testPeekIsTheFirstSentenceOfWhereYouLeftOff() {
    let n = BriefingNotice(
      id: "1-4-dd", kind: .brief, title: "", text: briefing, prompt: "", defaultAnswer: "",
      expires: nil)
    XCTAssertEqual(
      n.peekLine,
      "Left off: You just finished configuring Grok voice settings and reviewing pull requests in VS Code."
    )
  }

  func testQuestionAndNotesAreNotNextSteps() {
    let s = BriefingSections(briefing)
    XCTAssertEqual(s.nextSteps.count, 3)
    XCTAssertTrue(s.question.hasPrefix("Earlier memory says"))
    XCTAssertEqual(s.notes.count, 1)
    XCTAssertFalse(s.leftOff.contains("2026-10-12#4"))
  }

  // MARK: Look

  func testRenderNoticeCards() throws {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("dayframe-notch")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let geometry = NotchGeometry(
      screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchX: 663, notchWidth: 186,
      height: 32, hasNotch: true)
    let busy = """
      WHERE YOU LEFT OFF: The local AI was busy, so this comes from your open loops.
      NEXT STEPS:
      1. Finalize feedback for the Jarvis HQ prototype
      2. Research Gemini's file generation for the App Audit plan
      3. Fix the Ollama timeout

      14 more open loops in Briefing.
      """
    let cases: [(String, BriefingNotice, NotchPillModel.Mode)] = [
      (
        "brief-peek",
        .init(
          id: "1", kind: .brief, title: "Where you left off", text: briefing, prompt: "",
          defaultAnswer: "", expires: nil), .peek
      ),
      (
        "brief-card",
        .init(
          id: "2", kind: .brief, title: "Where you left off", text: briefing, prompt: "",
          defaultAnswer: "", expires: nil), .notice
      ),
      (
        "ai-busy-card",
        .init(
          id: "3", kind: .brief, title: "Where you left off", text: busy, prompt: "",
          defaultAnswer: "", expires: nil), .notice
      ),
      (
        "checkin-card",
        .init(
          id: "4", kind: .ask, title: "Check-in", text: "",
          prompt: "What are you working on, and any blockers?\n(Session goal: ship the notch card)",
          defaultAnswer: "", expires: nil), .notice
      ),
      (
        "nudge-peek",
        .init(
          id: "5", kind: .peek, title: "Gentle nudge",
          text: "25 min on YouTube this hour. Back to the API proposal?", prompt: "",
          defaultAnswer: "", expires: nil), .peek
      ),
      (
        "rest-unread",
        .init(
          id: "6", kind: .brief, title: "", text: briefing, prompt: "", defaultAnswer: "",
          expires: nil), .rest
      ),
    ]
    for (name, notice, mode) in cases {
      let model = NotchPillModel(geometry: geometry)
      model.stats = .empty
      model.accentHex = DayframePalette.original.accentHex
      model.notice = notice
      model.mode = mode
      let size = model.contentSize(for: mode)
      XCTAssertGreaterThan(size.height, geometry.height - 1, name)
      let view = ZStack(alignment: .top) {
        Color(white: 0.93)
        NotchPillView(model: model)
      }
      .frame(width: max(size.width, 460) + 40, height: size.height + 40, alignment: .top)
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      let image = try XCTUnwrap(renderer.nsImage, name)
      let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
      try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        .write(to: out.appendingPathComponent("\(name).png"))
    }
    print("notch snapshots: \(out.path)")
  }
}
