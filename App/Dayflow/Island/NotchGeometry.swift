//
//  NotchGeometry.swift
//  Dayframe
//
//  Where the hardware notch is, in the screen's own top-left point coordinates
//  (the same space the island page draws in). Screens without a notch get a
//  zero-width "virtual notch" at the top center, so the pill becomes one capsule.
//

import AppKit

struct NotchGeometry: Equatable {
  /// The screen's frame in global AppKit coordinates (bottom-left origin).
  let screenFrame: CGRect
  /// Left edge of the notch, measured from the screen's left edge.
  let notchX: CGFloat
  let notchWidth: CGFloat
  /// Notch height, or the menu bar height on screens without a notch.
  let height: CGFloat
  let hasNotch: Bool

  /// Wings of the resting pill on each side of the notch. Web/src/island/layout.ts
  /// positions the show's last frame with the same numbers.
  static let leftWing: CGFloat = 64
  static let rightWing: CGFloat = 84

  var pillRadius: CGFloat { min(14, height / 2 - 2) }

  /// The resting pill, in screen-local top-left coordinates.
  var pillRect: CGRect {
    CGRect(
      x: notchX - Self.leftWing, y: 0, width: notchWidth + Self.leftWing + Self.rightWing, height: height)
  }

  /// The pill's frame in global AppKit coordinates, for positioning its window.
  var pillWindowFrame: CGRect {
    let p = pillRect
    return CGRect(x: screenFrame.minX + p.minX, y: screenFrame.maxY - p.height, width: p.width, height: p.height)
  }

  /// The screen the island lives on: the built-in display with a notch if there is one,
  /// otherwise the screen with the menu bar.
  static func preferredScreen() -> NSScreen? {
    NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
  }

  static func current() -> NotchGeometry? {
    preferredScreen().map(NotchGeometry.init(screen:))
  }

  init(screen: NSScreen) {
    let frame = screen.frame
    screenFrame = frame
    if screen.safeAreaInsets.top > 0,
      let left = screen.auxiliaryTopLeftArea,
      let right = screen.auxiliaryTopRightArea
    {
      hasNotch = true
      notchX = left.maxX - frame.minX
      notchWidth = max(0, right.minX - left.maxX)
      height = screen.safeAreaInsets.top
    } else {
      hasNotch = false
      notchWidth = 0
      notchX = frame.width / 2
      let menuBar = frame.maxY - screen.visibleFrame.maxY
      height = menuBar > 0 ? menuBar : 24
    }
  }

  /// For tests.
  init(screenFrame: CGRect, notchX: CGFloat, notchWidth: CGFloat, height: CGFloat, hasNotch: Bool) {
    self.screenFrame = screenFrame
    self.notchX = notchX
    self.notchWidth = notchWidth
    self.height = height
    self.hasNotch = hasNotch
  }
}
