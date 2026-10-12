//
//  TelemetryStubs.swift
//  Dayframe
//
//  Dayframe ships without PostHog (analytics) or Sentry (crash reporting).
//  These no-op stand-ins keep the upstream call sites compiling while
//  guaranteeing nothing is collected or sent anywhere.
//

import Foundation

// MARK: - PostHog stand-in

final class PostHogConfig {
  var captureApplicationLifecycleEvents = false
  var optOut = true
  var preloadFeatureFlags = false
  var remoteConfig = false
  init(apiKey: String, host: String) {}
}

final class PostHogSDK {
  static let shared = PostHogSDK()
  private let localID = UUID().uuidString
  func setup(_ config: PostHogConfig) {}
  func getDistinctId() -> String { localID }
  func identify(_ distinctId: String) {}
  func alias(_ alias: String) {}
  func register(_ properties: [String: Any]) {}
  func capture(_ event: String, properties: [String: Any]? = nil) {}
  func flush() {}
  func optIn() {}
  func optOut() {}
  func getFeatureFlag(_ key: String) -> Any? { nil }
}

// MARK: - Sentry stand-in

enum SentryLevel { case debug, info, warning, error, fatal }

enum SentrySpanStatus { case ok, internalError, cancelled, deadlineExceeded, unknown }

final class Breadcrumb {
  var level: SentryLevel
  var category: String
  var message: String?
  var type: String?
  var data: [String: Any]?
  init(level: SentryLevel = .info, category: String = "") {
    self.level = level
    self.category = category
  }
}

final class Span {
  func setData(value: Any?, key: String) {}
  func finish() {}
  func finish(status: SentrySpanStatus) {}
}

final class Attachment {
  init(path: String, filename: String, contentType: String? = nil) {}
}

final class SentryMessage {
  init(formatted: String) {}
}

final class Event {
  var message: SentryMessage?
  init(level: SentryLevel) {}
}

final class Scope {
  func setContext(value: [String: Any], key: String) {}
  func setTag(value: String, key: String) {}
  func setExtra(value: Any?, key: String) {}
  func addAttachment(_ attachment: Attachment) {}
}

enum SentrySDK {
  static var crashedLastRun: Bool { false }
  static func start(_ configure: (AnyObject) -> Void) {}
  static func close() {}
  static func flush(timeout: TimeInterval) {}
  static func addBreadcrumb(_ crumb: Breadcrumb) {}
  static func configureScope(_ configure: @escaping (Scope) -> Void) {}
  static func capture(message: String) {}
  static func capture(event: Event, block: ((Scope) -> Void)? = nil) {}
  static func startTransaction(name: String, operation: String) -> Span { Span() }
}
