import AppKit
import XCTest

@testable import Dayflow

/// The app icon (the welcome's ring on its tile) in every palette, and the bundled AppIcon set.
final class AppIconTests: XCTestCase {
  @MainActor
  func testIconRendersInEveryPaletteWithTransparentCorners() throws {
    for palette in DayframePalette.allCases {
      for pixels in [16, 1024] {
        let data = try XCTUnwrap(AppIconArt.png(palette: palette, pixels: CGFloat(pixels)))
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, pixels, "\(palette)")
        XCTAssertEqual(image.pixelsHigh, pixels, "\(palette)")
        // The macOS grid leaves the corners empty; the tile fills the middle.
        XCTAssertEqual(image.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(
          image.colorAt(x: pixels / 2, y: pixels / 2)?.alphaComponent ?? 0, 1, accuracy: 0.01)
      }
    }
  }

  /// Writes the bundled AppIcon (Original palette) into the asset catalog. Skipped unless asked:
  ///   TEST_RUNNER_DAYFRAME_WRITE_APP_ICON=1 xcodebuild test -project App/Dayflow.xcodeproj \
  ///     -scheme Dayflow -only-testing:DayflowTests/AppIconTests/testWriteBundledAppIcon
  @MainActor
  func testWriteBundledAppIcon() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["DAYFRAME_WRITE_APP_ICON"] == "1",
      "Set TEST_RUNNER_DAYFRAME_WRITE_APP_ICON=1 to rewrite the bundled icon.")
    let set = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Dayflow/Assets.xcassets/AppIcon.appiconset")
    for old in try FileManager.default.contentsOfDirectory(at: set, includingPropertiesForKeys: nil)
    where old.pathExtension == "png" {
      try FileManager.default.removeItem(at: old)
    }
    var images: [[String: String]] = []
    for size in [16, 32, 128, 256, 512] {
      for scale in [1, 2] {
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        let png = try XCTUnwrap(AppIconArt.png(palette: .original, pixels: CGFloat(size * scale)))
        try png.write(to: set.appendingPathComponent(name))
        images.append([
          "filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)",
        ])
      }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
      .write(to: set.appendingPathComponent("Contents.json"))
  }
}
