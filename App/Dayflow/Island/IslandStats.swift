//
//  IslandStats.swift
//  Dayframe
//
//  Today's numbers for the notch island, computed exactly like the Timeline's
//  "Today's targets" (DaySummaryStats + the carried-forward day goal plan).
//

import Foundation

struct IslandStats: Equatable, Sendable {
  struct Category: Equatable, Sendable {
    let name: String
    let minutes: Int
    let colorHex: String
  }

  var day: String
  var cardCount: Int
  var trackedMinutes: Int
  var focusMinutes: Int
  var focusGoalMinutes: Int
  var categories: [Category]

  static let empty = IslandStats(
    day: "", cardCount: 0, trackedMinutes: 0, focusMinutes: 0, focusGoalMinutes: 0, categories: [])

  var focusFraction: Double {
    focusGoalMinutes > 0 ? Double(focusMinutes) / Double(focusGoalMinutes) : 0
  }

  var focusPercent: Int { Int((focusFraction * 100).rounded()) }

  var goalReached: Bool { focusGoalMinutes > 0 && focusMinutes >= focusGoalMinutes }

  /// Synchronous database reads: call off the main thread.
  static func compute(
    categories: [TimelineCategory], storage: StorageManaging = StorageManager.shared,
    now: Date = Date()
  ) -> IslandStats {
    let dayInfo = now.getDayInfoFor4AMBoundary()
    let plan = DaySummaryStats.carriedForwardGoalPlan(
      day: dayInfo.dayString, storageManager: storage, categories: categories)
    let cards = storage.fetchTimelineCards(forDay: dayInfo.dayString)
    let precomputed = DaySummaryStats.precomputeCardDurations(cards)
    let tracked = DaySummaryStats.computeTotalCapturedTime(
      from: precomputed, categories: categories)
    let focus = DaySummaryStats.computeTotalFocusTime(
      from: precomputed, snapshots: plan.focusCategories, categories: categories)
    let systemNames = Set(categories.filter(\.isSystem).map { $0.name.lowercased() })
    let byCategory = DaySummaryStats.computeCategoryDurations(
      from: precomputed, categories: categories
    )
    .filter { !systemNames.contains($0.name.lowercased()) && $0.duration >= 60 }
    .sorted { $0.duration > $1.duration }
    .map {
      Category(name: $0.name, minutes: Int(($0.duration / 60).rounded()), colorHex: $0.colorHex)
    }

    return IslandStats(
      day: dayInfo.dayString,
      cardCount: cards.count,
      trackedMinutes: Int((tracked / 60).rounded()),
      focusMinutes: Int((focus / 60).rounded()),
      focusGoalMinutes: plan.isSkipped ? 0 : plan.focusTargetMinutes,
      categories: byCategory
    )
  }
}

extension Int {
  /// "3h 7m" / "45m", matching the island page's formatMinutes.
  var islandDuration: String {
    let m = Swift.max(0, self)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
  }
}
