//
//  AIUsageSection.swift
//  Dayframe
//
//  How much AI Dayframe has used, per provider: the app's own calls (llm_calls
//  table) plus Briefing's (~/Briefing/telemetry.jsonl). The Claude / Codex CLIs
//  don't report how much of a plan is left, so this links to the official pages.
//

import Charts
import GRDB
import SwiftUI

struct AIUsageSection: View {
  @Environment(\.dayflowTheme) private var theme
  @State private var range: UsageRange = .week
  @State private var rows: [UsageRow] = []
  @State private var loaded = false

  enum UsageRange: Int, CaseIterable, Identifiable {
    case today = 1, week = 7, month = 30
    var id: Int { rawValue }
    var title: String {
      switch self {
      case .today: return "Today"
      case .week: return "7 days"
      case .month: return "30 days"
      }
    }
  }

  struct UsageRow: Identifiable {
    var id: String { "\(provider)-\(day)" }
    let provider: String
    let day: Date
    var calls: Int
    var failures: Int
    var tokensIn: Int
    var tokensOut: Int
  }

  struct Totals: Identifiable {
    var id: String { provider }
    let provider: String
    var calls = 0
    var failures = 0
    var tokensIn = 0
    var tokensOut = 0
  }

  var body: some View {
    SettingsSection(
      title: "AI usage",
      subtitle: "What Dayframe and your briefings used, by provider.",
      trailing: {
        Picker("", selection: $range) {
          ForEach(UsageRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
      }
    ) {
      VStack(alignment: .leading, spacing: 16) {
        let totals = totalsInRange
        if totals.isEmpty {
          Text(loaded ? "No AI calls in this period yet." : "Loading…")
            .font(.custom("Figtree", size: 13))
            .foregroundColor(SettingsStyle.secondary)
        } else {
          HStack(spacing: 10) {
            ForEach(totals) { t in
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                  Circle().fill(color(for: t.provider)).frame(width: 8, height: 8)
                  Text(displayName(t.provider))
                    .font(.custom("Figtree", size: 12).weight(.semibold))
                    .foregroundColor(SettingsStyle.text)
                }
                Text("\(t.calls) calls")
                  .font(.custom("InstrumentSerif-Regular", size: 24))
                  .foregroundColor(SettingsStyle.text)
                Text(tokenLine(t))
                  .font(.custom("Figtree", size: 11))
                  .foregroundColor(SettingsStyle.secondary)
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(RoundedRectangle(cornerRadius: 10).fill(theme.summaryCardFill))
              .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.summaryCardBorder, lineWidth: 1))
            }
          }

          if range != .today {
            Chart(rowsInRange) { r in
              BarMark(
                x: .value("Day", r.day, unit: .day),
                y: .value("Calls", r.calls)
              )
              .foregroundStyle(by: .value("Provider", displayName(r.provider)))
              .cornerRadius(3)
            }
            .chartForegroundStyleScale(
              domain: totals.map { displayName($0.provider) },
              range: totals.map { color(for: $0.provider) }
            )
            .frame(height: 140)
          }
        }

        HStack(spacing: 8) {
          Text("How much of your plan is left:")
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.secondary)
          Link("Claude usage", destination: URL(string: "https://claude.ai/settings/usage")!)
          Text("·").foregroundColor(SettingsStyle.secondary)
          Link("ChatGPT / Codex usage", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
        }
        .font(.custom("Figtree", size: 12))
      }
    }
    .task { await load() }
  }

  // MARK: - Data

  private var rowsInRange: [UsageRow] {
    let start = Calendar.current.date(
      byAdding: .day, value: -(range.rawValue - 1), to: Calendar.current.startOfDay(for: Date()))!
    return rows.filter { $0.day >= start }
  }

  private var totalsInRange: [Totals] {
    var byProvider: [String: Totals] = [:]
    for r in rowsInRange {
      var t = byProvider[r.provider] ?? Totals(provider: r.provider)
      t.calls += r.calls
      t.failures += r.failures
      t.tokensIn += r.tokensIn
      t.tokensOut += r.tokensOut
      byProvider[r.provider] = t
    }
    return byProvider.values.sorted { $0.calls > $1.calls }
  }

  private func load() async {
    let app = (try? Self.appRows()) ?? []
    let briefing = Self.briefingRows()
    var merged: [String: UsageRow] = [:]
    for r in app + briefing {
      if var existing = merged[r.id] {
        existing.calls += r.calls
        existing.failures += r.failures
        existing.tokensIn += r.tokensIn
        existing.tokensOut += r.tokensOut
        merged[r.id] = existing
      } else {
        merged[r.id] = r
      }
    }
    rows = merged.values.sorted { $0.day < $1.day }
    loaded = true
  }

  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  /// Dayframe's own calls (screen analysis, summaries, chat).
  private static func appRows() throws -> [UsageRow] {
    try StorageManager.shared.timedRead("ai_usage") { db in
      let sql = """
        SELECT provider,
               date(created_at, 'localtime') AS day,
               COUNT(*) AS calls,
               SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
               SUM(CASE WHEN json_valid(response_headers)
                   THEN CAST(json_extract(response_headers, '$."x-usage-input"') AS INTEGER) ELSE 0 END) AS tin,
               SUM(CASE WHEN json_valid(response_headers)
                   THEN CAST(json_extract(response_headers, '$."x-usage-output"') AS INTEGER) ELSE 0 END) AS tout
        FROM llm_calls
        WHERE created_at >= datetime('now', '-31 days')
        GROUP BY provider, day
        """
      return try Row.fetchAll(db, sql: sql).compactMap { row in
        guard let dayString: String = row["day"], let day = dayFormatter.date(from: dayString) else { return nil }
        return UsageRow(
          provider: normalize(row["provider"] ?? "local"), day: day,
          calls: row["calls"] ?? 0, failures: row["failures"] ?? 0,
          tokensIn: row["tin"] ?? 0, tokensOut: row["tout"] ?? 0)
      }
    }
  }

  /// Briefing's calls (briefings, distill, Ask) from its local telemetry log.
  private static func briefingRows() -> [UsageRow] {
    let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Briefing")
    var out: [String: UsageRow] = [:]
    let cutoff = Date().addingTimeInterval(-31 * 86400).timeIntervalSince1970
    for name in ["telemetry.jsonl.1", "telemetry.jsonl"] {
      guard let text = try? String(contentsOf: home.appendingPathComponent(name), encoding: .utf8) else { continue }
      for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          obj["kind"] as? String == "llm",
          let ts = obj["ts"] as? Double, ts >= cutoff
        else { continue }
        let provider = normalize((obj["backend"] as? String) ?? "ollama")
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: ts))
        let key = "\(provider)-\(day)"
        var r = out[key] ?? UsageRow(provider: provider, day: day, calls: 0, failures: 0, tokensIn: 0, tokensOut: 0)
        r.calls += 1
        if obj["ok"] as? Bool == false { r.failures += 1 }
        r.tokensIn += (obj["tokens_in"] as? Int) ?? 0
        r.tokensOut += (obj["tokens_out"] as? Int) ?? 0
        out[key] = r
      }
    }
    return Array(out.values)
  }

  /// One name per provider across the app and Briefing.
  private static func normalize(_ raw: String) -> String {
    switch raw.lowercased() {
    case "claude", "claude_cli", "chat_cli_claude": return "claude"
    case "chatgpt", "codex", "codex_cli", "chat_cli": return "chatgpt"
    case "ollama", "lmstudio", "custom", "local", "openai": return "local"
    default: return raw.lowercased()
    }
  }

  private func displayName(_ p: String) -> String {
    switch p {
    case "claude": return "Claude"
    case "chatgpt": return "ChatGPT"
    case "local": return "On this Mac"
    default: return p.capitalized
    }
  }

  private func color(for p: String) -> Color {
    switch p {
    case "claude": return Color(hex: "D97757")
    case "chatgpt": return Color(hex: "10A37F")
    default: return theme.accent
    }
  }

  private func tokenLine(_ t: Totals) -> String {
    let tokens = t.tokensIn + t.tokensOut
    var s = tokens > 0 ? "\(Self.compact(tokens)) tokens" : "tokens not reported"
    if t.failures > 0 { s += " · \(t.failures) failed" }
    return s
  }

  private static func compact(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6)
      : n >= 1000 ? String(format: "%.1fk", Double(n) / 1e3) : "\(n)"
  }
}
