//
//  BriefingNotice.swift
//  Dayframe
//
//  Briefing's messages for the notch pill: the "where you left off" briefing, a check-in or
//  session-goal question, or a short nudge. briefing.py writes ~/Briefing/notices/<id>.json and
//  opens dayframe://notice?id=<id>. Dayframe answers with <id>.ack ("I'm showing it") and, for a
//  question, <id>.answer. Without an ack within 3 s, briefing.py falls back to its old dialog.
//

import Foundation
import os.log

struct BriefingNotice: Identifiable, Equatable {
  enum Kind: String {
    /// The briefing: a quiet peek, the full card on hover or click.
    case brief
    /// A question with a one-line answer (check-in, session goal).
    case ask
    /// A one-click confirmation to reopen the last project's apps, links and files.
    case resume
    /// A short nudge or debrief line; it goes away by itself.
    case peek
  }

  let id: String
  let kind: Kind
  let title: String
  let text: String
  let prompt: String
  let defaultAnswer: String
  /// When briefing.py stops waiting for an answer (asks only).
  let expires: Date?

  var sections: BriefingSections { BriefingSections(text) }

  /// The one line shown while the pill peeks.
  var peekLine: String {
    switch kind {
    case .ask:
      return Self.firstLine(prompt)
    case .resume:
      let head = title.isEmpty ? "Resume project?" : title
      let detail = Self.firstLine(text)
      return detail.isEmpty ? head : "\(head) · \(detail)"
    case .peek:
      return title.isEmpty ? Self.firstLine(text) : "\(title): \(Self.firstLine(text))"
    case .brief:
      let left = sections.leftOff
      if !left.isEmpty { return "Left off: \(Self.firstSentence(left))" }
      return sections.nextSteps.first.map { "Next: \($0)" } ?? Self.firstLine(text)
    }
  }

  /// How long the pill peeks on arrival before tucking the notice behind its eyes.
  var peekDuration: TimeInterval {
    switch kind {
    case .peek: return 8
    case .brief, .ask, .resume: return 30
    }
  }

  static func firstSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
      return String(trimmed[...end])
    }
    return trimmed
  }

  private static func firstLine(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline).first.map {
      $0.trimmingCharacters(in: .whitespaces)
    } ?? ""
  }
}

extension BriefingNotice {
  /// Decodes briefing.py's notice file. Nil for anything malformed or of an unknown kind.
  init?(json: Data, now: Date = Date()) {
    guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
      let id = obj["id"] as? String, BriefingNoticeInbox.isValidID(id),
      let kind = (obj["kind"] as? String).flatMap(Kind.init(rawValue:))
    else { return nil }
    let string = { (key: String) in (obj[key] as? String) ?? "" }
    let wait = (obj["wait"] as? Double) ?? 0
    let created = (obj["created"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? now
    self.init(
      id: id, kind: kind, title: string("title"), text: string("text"), prompt: string("prompt"),
      defaultAnswer: string("default"),
      expires: wait > 0 ? created.addingTimeInterval(wait) : nil)
  }
}

/// The hand-off folder shared with briefing.py.
enum BriefingNoticeInbox {
  private static let log = Logger(subsystem: "local.dayframe.app", category: "notice")

  static var directory: URL {
    if let custom = ProcessInfo.processInfo.environment["BRIEFING_HOME"], !custom.isEmpty {
      return URL(fileURLWithPath: custom).appendingPathComponent("notices")
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Briefing/notices")
  }

  /// Ids are briefing.py's "<ms>-<pid>-<hex>"; anything else could point outside the folder.
  static func isValidID(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 64
      && id.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "0123456789abcdef-").contains($0)
      }
  }

  /// Reads and removes the notice, then tells briefing.py it is on screen.
  static func take(id: String, in dir: URL = directory) -> BriefingNotice? {
    guard isValidID(id) else {
      log.error("rejected notice id \(id, privacy: .public)")
      return nil
    }
    let file = dir.appendingPathComponent("\(id).json")
    guard let data = try? Data(contentsOf: file), let notice = BriefingNotice(json: data) else {
      log.notice(
        "notice \(id, privacy: .public) missing or unreadable (Briefing may have fallen back)")
      return nil
    }
    try? FileManager.default.removeItem(at: file)
    write(Data(), to: dir.appendingPathComponent("\(id).ack"))
    log.notice("showing \(notice.kind.rawValue, privacy: .public) notice \(id, privacy: .public)")
    return notice
  }

  /// The user's choice on a resume offer; false means "Not now".
  static func confirm(_ notice: BriefingNotice, resume: Bool, in dir: URL = directory) {
    let body: [String: Any] = resume ? ["resume": true] : ["skip": true]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    write(data, to: dir.appendingPathComponent("\(notice.id).answer"))
    log.notice(
      "answered resume notice \(notice.id, privacy: .public): \(resume ? "resume" : "skip", privacy: .public)"
    )
  }

  /// The user's answer to an ask; nil means they skipped it.
  static func answer(_ notice: BriefingNotice, text: String?, in dir: URL = directory) {
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let body: [String: Any] = trimmed.isEmpty ? ["skip": true] : ["text": trimmed]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    write(data, to: dir.appendingPathComponent("\(notice.id).answer"))
    log.notice(
      "answered notice \(notice.id, privacy: .public): \(trimmed.isEmpty ? "skipped" : "text", privacy: .public)"
    )
  }

  private static func write(_ data: Data, to url: URL) {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      log.error(
        "could not write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
