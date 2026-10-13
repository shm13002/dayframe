//
//  SentryHelper.swift
//  Dayframe
//
//  Crash reporting is removed in Dayframe. Same API as upstream, always off.
//

import Foundation

final class SentryHelper {
  static var isEnabled: Bool {
    get { false }
    set {}
  }
  static func setEnabled(_ enabled: Bool) {}
  static func startIfConfigured() {}
  static func addBreadcrumb(_ breadcrumb: Breadcrumb) {}
  static func configureScope(_ configure: @escaping (Scope) -> Void) {}
  static func startTransaction(name: String, operation: String) -> Span? { nil }
}
