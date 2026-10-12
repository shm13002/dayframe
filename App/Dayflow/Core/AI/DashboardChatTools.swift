import Foundation

/// The chat tools (fetchTimeline, fetchObservations), shared by every chat provider
/// that does its own function calling: Gemini and the local model (Qwen on Ollama).
/// Moved out of GeminiDirectProvider so Dayframe's local chat can use them too.
struct DashboardChatTools {
  /// Gemini gets very large payloads. The local model has a ~4k-token context, so it
  /// uses `compactResult(name:result:)` on top of this.
  var timelinePayloadSoftLimitBytes = 800_000

  enum DashboardToolName: String {
    case fetchTimeline
    case fetchObservations
  }

  enum DashboardToolArgError: Error, LocalizedError {
    case invalidCombination
    case invalidDate(String)
    case invalidRange

    var errorDescription: String? {
      switch self {
      case .invalidCombination:
        return "Provide either {date} OR {startDate, endDate}."
      case .invalidDate(let value):
        return "Invalid date format '\(value)'. Use YYYY-MM-DD."
      case .invalidRange:
        return "startDate must be less than or equal to endDate."
      }
    }
  }

  struct DashboardDateRange {
    let mode: String
    let date: String?
    let startDate: String?
    let endDate: String?
    let from: Date
    let to: Date
  }

  var dashboardDateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
  }

  var dashboardTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
  }

  var dashboardSingleDateDisplayFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
  }

  var dashboardRangeDateDisplayFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
  }

  func execute(name: String, args: [String: Any]) -> [String: Any] {
    guard let toolName = DashboardToolName(rawValue: name) else {
      return [
        "summary": "Unknown tool '\(name)'.",
        "error": [
          "code": "unknown_tool",
          "message": "Unknown tool '\(name)'.",
        ],
      ]
    }

    do {
      switch toolName {
      case .fetchTimeline:
        return try dashboardFetchTimeline(args: args)
      case .fetchObservations:
        return try dashboardFetchObservations(args: args)
      }
    } catch {
      return [
        "summary": error.localizedDescription,
        "error": [
          "code": "validation_error",
          "message": error.localizedDescription,
        ],
      ]
    }
  }

  func dashboardFetchTimeline(args: [String: Any]) throws -> [String: Any] {
    let includeDetailedSummary = boolArg(args["includeDetailedSummary"]) ?? true
    let requestedLimit = positiveIntArg(args["limit"])
    let dateRange = try parseDashboardDateRange(args: args)

    let cards: [TimelineCard]
    if dateRange.mode == "date", let date = dateRange.date {
      cards = StorageManager.shared.fetchTimelineCards(forDay: date)
    } else {
      cards = StorageManager.shared.fetchTimelineCardsByTimeRange(
        from: dateRange.from, to: dateRange.to)
    }

    let limitedCards: [TimelineCard]
    if let requestedLimit {
      limitedCards = Array(cards.prefix(requestedLimit))
    } else {
      limitedCards = cards
    }

    var items: [[String: Any]] = limitedCards.map { card in
      var item: [String: Any] = [
        "day": card.day,
        "startTime": card.startTimestamp,
        "endTime": card.endTimestamp,
        "title": card.title,
        "summary": card.summary,
        "category": card.category,
        "subcategory": card.subcategory,
        "distractionsCount": card.distractions?.count ?? 0,
      ]

      if let appSites = card.appSites {
        item["appSites"] = [
          "primary": jsonOptional(appSites.primary),
          "secondary": jsonOptional(appSites.secondary),
        ]
      }

      if includeDetailedSummary && !card.detailedSummary.isEmpty {
        item["detailedSummary"] = card.detailedSummary
      }

      return item
    }

    var truncated = false
    if includeDetailedSummary {
      let payloadSize = (try? JSONSerialization.data(withJSONObject: items).count) ?? 0
      if payloadSize > timelinePayloadSoftLimitBytes {
        truncated = true
        items = items.map { row in
          var updated = row
          updated.removeValue(forKey: "detailedSummary")
          return updated
        }
      }
    }

    let dateDescription = dashboardFetchDateDescription(for: dateRange)
    var summary =
      "Fetched \(items.count) timeline card\(items.count == 1 ? "" : "s") for \(dateDescription)."
    if truncated {
      summary += " Detailed summaries were omitted due to payload size."
    }

    return [
      "request": [
        "mode": dateRange.mode,
        "date": jsonOptional(dateRange.date),
        "startDate": jsonOptional(dateRange.startDate),
        "endDate": jsonOptional(dateRange.endDate),
        "includeDetailedSummary": includeDetailedSummary,
        "limit": jsonOptional(requestedLimit),
      ],
      "summary": summary,
      "itemCount": items.count,
      "truncated": truncated,
      "items": items,
    ]
  }

  func dashboardFetchObservations(args: [String: Any]) throws -> [String: Any] {
    let requestedLimit = positiveIntArg(args["limit"])
    let dateRange = try parseDashboardDateRange(args: args)

    let observations: [Observation]
    if dateRange.mode == "date", let date = dateRange.date {
      let dayBounds = try dashboardDayBounds(for: date)
      observations = StorageManager.shared.fetchObservationsByTimeRange(
        from: dayBounds.start,
        to: dayBounds.end
      )
    } else {
      observations = StorageManager.shared.fetchObservationsByTimeRange(
        from: dateRange.from,
        to: dateRange.to
      )
    }

    let limitedObservations: [Observation]
    if let requestedLimit {
      limitedObservations = Array(observations.prefix(requestedLimit))
    } else {
      limitedObservations = observations
    }

    let effectiveObservations = limitedObservations
    let items = dashboardObservationDayGroups(from: effectiveObservations)

    let itemCount = effectiveObservations.count
    let dayCount = items.count
    let dateDescription = dashboardFetchDateDescription(for: dateRange)
    var summary =
      "Fetched \(itemCount) observation\(itemCount == 1 ? "" : "s") for \(dateDescription)"
    if dayCount > 0 {
      summary += " across \(dayCount) day\(dayCount == 1 ? "" : "s")"
    }
    summary += "."

    return [
      "request": [
        "mode": dateRange.mode,
        "date": jsonOptional(dateRange.date),
        "startDate": jsonOptional(dateRange.startDate),
        "endDate": jsonOptional(dateRange.endDate),
        "limit": jsonOptional(requestedLimit),
      ],
      "summary": summary,
      "dayCount": dayCount,
      "itemCount": itemCount,
      "truncated": false,
      "items": items,
    ]
  }

  func dashboardObservationDayGroups(from observations: [Observation]) -> [[String: Any]] {
    var groups: [[String: Any]] = []
    var currentDay: String?
    var currentDayObservations: [[String: Any]] = []

    for observation in observations {
      let start = Date(timeIntervalSince1970: TimeInterval(observation.startTs))
      let end = Date(timeIntervalSince1970: TimeInterval(observation.endTs))
      let day = start.getDayInfoFor4AMBoundary().dayString
      let item: [String: Any] = [
        "startTime": dashboardTimeFormatter.string(from: start),
        "endTime": dashboardTimeFormatter.string(from: end),
        "observation": observation.observation,
      ]

      if currentDay == day {
        currentDayObservations.append(item)
        continue
      }

      if let currentDay {
        groups.append(
          [
            "day": currentDay,
            "observations": currentDayObservations,
          ])
      }

      currentDay = day
      currentDayObservations = [item]
    }

    if let currentDay {
      groups.append(
        [
          "day": currentDay,
          "observations": currentDayObservations,
        ])
    }

    return groups
  }

  func parseDashboardDateRange(args: [String: Any]) throws -> DashboardDateRange {
    let date = stringArg(args["date"])
    let startDate = stringArg(args["startDate"])
    let endDate = stringArg(args["endDate"])

    if let date {
      if startDate != nil || endDate != nil {
        throw DashboardToolArgError.invalidCombination
      }

      let bounds = try dashboardDayBounds(for: date)
      return DashboardDateRange(
        mode: "date",
        date: date,
        startDate: nil,
        endDate: nil,
        from: bounds.start,
        to: bounds.end
      )
    }

    guard let startDate, let endDate else {
      throw DashboardToolArgError.invalidCombination
    }

    let startBounds = try dashboardDayBounds(for: startDate)
    let endBounds = try dashboardDayBounds(for: endDate)

    guard startBounds.start <= endBounds.start else {
      throw DashboardToolArgError.invalidRange
    }

    return DashboardDateRange(
      mode: "range",
      date: nil,
      startDate: startDate,
      endDate: endDate,
      from: startBounds.start,
      to: endBounds.end
    )
  }

  func dashboardDayBounds(for dateString: String) throws -> (start: Date, end: Date) {
    guard let dayDate = dashboardDateFormatter.date(from: dateString) else {
      throw DashboardToolArgError.invalidDate(dateString)
    }

    let calendar = Calendar.current
    var startComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
    startComponents.hour = 4
    startComponents.minute = 0
    startComponents.second = 0
    guard let dayStart = calendar.date(from: startComponents) else {
      throw DashboardToolArgError.invalidDate(dateString)
    }

    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayDate) else {
      throw DashboardToolArgError.invalidDate(dateString)
    }
    var endComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
    endComponents.hour = 4
    endComponents.minute = 0
    endComponents.second = 0
    guard let dayEnd = calendar.date(from: endComponents) else {
      throw DashboardToolArgError.invalidDate(dateString)
    }

    return (dayStart, dayEnd)
  }

  func dashboardFetchDateDescription(for dateRange: DashboardDateRange) -> String {
    if dateRange.mode == "date", let date = dateRange.date {
      return formattedDashboardSingleDate(date) ?? date
    }

    if let startDate = dateRange.startDate, let endDate = dateRange.endDate {
      let formattedStart = formattedDashboardRangeDate(startDate) ?? startDate
      let formattedEnd = formattedDashboardRangeDate(endDate) ?? endDate
      return formattedStart == formattedEnd
        ? formattedStart : String(localized: "\(formattedStart) to \(formattedEnd)")
    }

    return String(localized: "the requested dates")
  }

  func formattedDashboardSingleDate(_ dateString: String) -> String? {
    guard let date = dashboardDateFormatter.date(from: dateString) else { return nil }
    return dashboardSingleDateDisplayFormatter.string(from: date)
  }

  func formattedDashboardRangeDate(_ dateString: String) -> String? {
    guard let date = dashboardDateFormatter.date(from: dateString) else { return nil }
    return dashboardRangeDateDisplayFormatter.string(from: date)
  }

  func stringArg(_ value: Any?) -> String? {
    guard let value else { return nil }
    if let stringValue = value as? String {
      let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }

  func boolArg(_ value: Any?) -> Bool? {
    guard let value else { return nil }
    if let boolValue = value as? Bool { return boolValue }
    if let numberValue = value as? NSNumber { return numberValue.boolValue }
    if let stringValue = value as? String {
      switch stringValue.lowercased() {
      case "true", "1", "yes":
        return true
      case "false", "0", "no":
        return false
      default:
        return nil
      }
    }
    return nil
  }

  func positiveIntArg(_ value: Any?) -> Int? {
    guard let value else { return nil }
    if let intValue = value as? Int {
      return intValue > 0 ? intValue : nil
    }
    if let numberValue = value as? NSNumber {
      let intValue = numberValue.intValue
      return intValue > 0 ? intValue : nil
    }
    if let stringValue = value as? String,
      let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    {
      return intValue > 0 ? intValue : nil
    }
    return nil
  }

  func jsonOptional(_ value: Any?) -> Any {
    value ?? NSNull()
  }
}

// MARK: - Local model (Qwen on Ollama)

extension DashboardChatTools {
  /// Ollama runs Qwen with a ~4k-token window, so a tool result has to stay small.
  static let compactResultCharacterBudget = 6_000
  static let compactSummaryCharacterLimit = 160

  /// The same two tools in OpenAI / JSON Schema form, for /v1/chat/completions.
  static func openAIToolDeclarations() -> [[String: Any]] {
    let dateProperties: [String: Any] = [
      "date": ["type": "string", "description": "One day, YYYY-MM-DD."],
      "startDate": ["type": "string", "description": "Range start, YYYY-MM-DD (use with endDate)."],
      "endDate": ["type": "string", "description": "Range end, YYYY-MM-DD (use with startDate)."],
    ]
    return [
      [
        "type": "function",
        "function": [
          "name": DashboardToolName.fetchTimeline.rawValue,
          "description":
            "The user's activity cards (time range, category, title, summary) for one day or a date range. Use for what did I do, standups, time breakdowns.",
          "parameters": ["type": "object", "properties": dateProperties],
        ],
      ],
      [
        "type": "function",
        "function": [
          "name": DashboardToolName.fetchObservations.rawValue,
          "description":
            "Raw notes of what was on screen, for detailed questions like what was I reading at 2pm. Prefer fetchTimeline.",
          "parameters": ["type": "object", "properties": dateProperties],
        ],
      ],
    ]
  }

  /// Turns a full tool result into short plain-text lines that fit the local model's
  /// context: one line per card or observation, no detailed summaries, a hard size cap.
  static func compactResult(
    name: String,
    result: [String: Any],
    budget: Int = compactResultCharacterBudget
  ) -> String {
    let summary = result["summary"] as? String ?? "Tool finished."
    if let error = result["error"] as? [String: Any] {
      return "Error: \(error["message"] as? String ?? summary)"
    }

    var lines: [String] = []
    var output = summary
    if name == DashboardToolName.fetchTimeline.rawValue {
      // A 4B model adds up times badly, so give it the minutes per card and the total.
      var totalMinutes = 0
      var currentDay: String?
      for item in result["items"] as? [[String: Any]] ?? [] {
        let day = item["day"] as? String ?? ""
        if day != currentDay {
          lines.append("[\(day)]")
          currentDay = day
        }
        let start = item["startTime"] as? String ?? ""
        let end = item["endTime"] as? String ?? ""
        let category = item["category"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        let cardSummary = truncated(
          item["summary"] as? String ?? "", limit: compactSummaryCharacterLimit)
        var line = "\(start)–\(end)"
        if let minutes = minutesBetween(start, end) {
          totalMinutes += minutes
          line += " (\(formattedDuration(minutes)))"
        }
        line += " · \(category) · \(title)"
        if !cardSummary.isEmpty { line += " — \(cardSummary)" }
        lines.append(line)
      }
      if totalMinutes > 0 {
        output += " Total time across these cards: \(formattedDuration(totalMinutes))."
      }
    } else {
      for group in result["items"] as? [[String: Any]] ?? [] {
        lines.append("[\(group["day"] as? String ?? "")]")
        for observation in group["observations"] as? [[String: Any]] ?? [] {
          let start = observation["startTime"] as? String ?? ""
          let text = truncated(
            observation["observation"] as? String ?? "", limit: compactSummaryCharacterLimit)
          lines.append("\(start) · \(text)")
        }
      }
    }

    if lines.isEmpty {
      return output + " No rows."
    }
    for (index, line) in lines.enumerated() {
      if output.count + line.count + 1 > budget {
        let remaining = lines.count - index
        output +=
          "\n… \(remaining) more line\(remaining == 1 ? "" : "s") omitted. Ask about a shorter time range for more detail."
        return output
      }
      output += "\n" + line
    }
    return output
  }

  static func minutesBetween(_ start: String, _ end: String) -> Int? {
    guard let startMinutes = parseTimeHMMA(timeString: start),
      let endMinutes = parseTimeHMMA(timeString: end)
    else { return nil }
    let minutes = endMinutes - startMinutes
    return minutes >= 0 ? minutes : minutes + 24 * 60
  }

  static func formattedDuration(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
  }

  private static func truncated(_ text: String, limit: Int) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard flat.count > limit else { return flat }
    return String(flat.prefix(limit - 1)) + "…"
  }
}
