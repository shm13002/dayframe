//
//  IslandCaptureExclusion.swift
//  Dayframe
//
//  Keeps the notch island out of Dayframe's own recordings. The island registers
//  its windows here; ScreenRecorder (on its own queue) reads them when it builds
//  each capture filter, and skips frames entirely while a full-screen show plays.
//

import CoreGraphics
import Foundation
import os

enum IslandCaptureExclusion {
  private struct State {
    var windowIDs: Set<CGWindowID> = []
    var showOnScreen = false
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())

  static var windowIDs: Set<CGWindowID> { state.withLock { $0.windowIDs } }
  static var showOnScreen: Bool { state.withLock { $0.showOnScreen } }

  static func register(_ windowNumber: Int) {
    guard windowNumber > 0 else { return }
    state.withLock { _ = $0.windowIDs.insert(CGWindowID(windowNumber)) }
  }

  static func unregister(_ windowNumber: Int) {
    state.withLock { _ = $0.windowIDs.remove(CGWindowID(windowNumber)) }
  }

  static func setShowOnScreen(_ value: Bool) {
    state.withLock { $0.showOnScreen = value }
  }
}
