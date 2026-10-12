//
//  UpdaterManager.swift
//  Dayframe
//
//  Dayframe is built locally and never auto-updates (Sparkle removed).
//  Keeps the small surface the UI uses so Settings and the menu still compile.
//

import Foundation

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
  static let shared = UpdaterManager()

  @Published var isChecking = false
  @Published var statusText: String = "Updates are managed by you (local build)"
  @Published var updateAvailable = false
  @Published var latestVersionString: String? = nil

  private override init() { super.init() }

  func checkForUpdates(showUI: Bool = false) {
    statusText = "Dayframe is a local build: pull and rebuild to update"
  }
}
