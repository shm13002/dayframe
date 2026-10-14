//
//  BriefingView.swift
//  Dayframe
//
//  The Briefing tab, built from the same parts as Daily and Timeline:
//  Instrument Serif headings, Figtree text, glass standup cards, theme tokens
//  (so every palette and dark mode just works).
//

import MarkdownUI
import SwiftUI

struct BriefingView: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var service = BriefingService.shared
  @ObservedObject private var categoryStore = CategoryStore.shared
  @ObservedObject private var startOfDay = StartOfDay.shared
  @State private var question = ""
  @State private var newTodo = ""
  @State private var morePage: BriefingMorePage?
  @State private var thumbsGiven: Bool?

  var body: some View {
    Group {
      switch service.phase {
      case .loading:
        ProgressView().controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .offline:
        BriefingPanelView()  // has the "service isn't running" help
      case .ready:
        content
      }
    }
    .onAppear { service.startAutoRefresh() }
    .onDisappear { service.stopAutoRefresh() }
    .sheet(item: $morePage) { page in
      BriefingMoreSheet(page: page)
    }
  }

  // MARK: - Layout

  private var content: some View {
    GeometryReader { geo in
      let wide = geo.size.width > 900
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          header
          if let error = service.lastError { errorNotice(error) }
          if !startOfDay.apps.isEmpty { todaysApps }
          if wide {
            HStack(alignment: .top, spacing: 18) {
              VStack(spacing: 18) {
                heroCard
                todayStrip
              }
              .frame(maxWidth: .infinity)
              VStack(spacing: 18) {
                nextThingCard
                loopsCard
                focusCard
              }
              .frame(width: min(360, geo.size.width * 0.34))
            }
          } else {
            heroCard
            nextThingCard
            loopsCard
            todayStrip
            focusCard
          }
          askCard
        }
        .padding(.horizontal, wide ? 44 : 24)
        .padding(.top, 28)
        .padding(.bottom, 40)
      }
      .scrollIndicators(.never)
    }
  }

  // MARK: - Errors

  private func errorNotice(_ message: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(theme.textSecondary)
      Text(message)
        .font(.custom("Figtree", size: 13))
        .foregroundStyle(theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button("Dismiss") { service.lastError = nil }
        .buttonStyle(.borderless)
        .font(.custom("Figtree", size: 13).weight(.medium))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.textPrimary.opacity(0.06)))
  }

  // MARK: - Today's apps

  /// The apps from Settings › Start of day: click one to bring it forward.
  private var todaysApps: some View {
    HStack(spacing: 14) {
      Text("Today's apps")
        .font(.custom("InstrumentSerif-Regular", size: 20))
        .foregroundColor(theme.textPrimary)
      HStack(spacing: 10) {
        ForEach(startOfDay.apps) { app in
          Button {
            startOfDay.bringForward(bundleID: app.bundleID)
          } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
              .resizable()
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
          .help("Open \(app.name)")
          .accessibilityLabel("Open \(app.name)")
        }
      }
      Button {
        startOfDay.run(reason: "briefing", force: true)
      } label: {
        Label("Set up my day", systemImage: "sunrise")
          .font(.custom("Figtree", size: 13).weight(.medium))
      }
      .buttonStyle(.bordered)
      .disabled(startOfDay.isRunning)
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
          .font(.custom("InstrumentSerif-Regular", size: 30))
          .foregroundStyle(theme.textPrimary)
        Text(subtitle)
          .font(.custom("Figtree", size: 13))
          .foregroundStyle(theme.textSecondary)
      }
      Spacer(minLength: 12)
      BriefingPill(
        title: service.isBriefing ? "Writing…" : "New briefing",
        systemImage: "sparkles",
        prominent: true,
        busy: service.isBriefing
      ) {
        Task { await service.newBriefing() }
      }
      .disabled(service.isBriefing)
      moreMenu
    }
  }

  private var subtitle: String {
    let hour = Calendar.current.component(.hour, from: Date())
    let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    var parts = [greeting]
    if let at = service.state?.briefingAt {
      parts.append(
        "briefing from "
          + Date(timeIntervalSince1970: at).formatted(date: .omitted, time: .shortened))
    }
    parts.append("written by " + writerName(service.writer))
    return parts.joined(separator: " · ")
  }

  private func writerName(_ backend: String) -> String {
    switch backend {
    case "claude_cli": return "Claude"
    case "codex_cli": return "ChatGPT"
    case "grok_cli": return "Grok"
    case "openai": return "LM Studio"
    default: return "Qwen (on this Mac)"
    }
  }

  private var moreMenu: some View {
    Menu {
      Section("Open") {
        ForEach(BriefingMorePage.allCases) { page in
          Button {
            morePage = page
          } label: {
            Label(page.title, systemImage: page.icon)
          }
        }
      }
      Section("Briefings are written by") {
        ForEach(["ollama", "claude_cli", "codex_cli", "grok_cli"], id: \.self) { backend in
          Button {
            Task { await service.setWriter(backend) }
          } label: {
            if service.writer == backend {
              Label(writerName(backend), systemImage: "checkmark")
            } else {
              Text(writerName(backend))
            }
          }
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(theme.controlText)
        .frame(width: 34, height: 34)
        .background(Circle().fill(theme.controlFill))
        .overlay(Circle().strokeBorder(theme.controlBorder, lineWidth: 1))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More")
  }

  // MARK: - Hero: where you left off

  private var heroCard: some View {
    let s = service.sections
    return BriefingCardShell {
      VStack(alignment: .leading, spacing: 16) {
        BriefingCardTitle("Where you left off")
        if s.isEmpty {
          Text(
            "No briefing yet. Tap New briefing, or keep working and one appears when you come back."
          )
          .font(.custom("Figtree", size: 15))
          .foregroundStyle(theme.textSecondary)
        } else {
          Text(s.leftOff)
            .font(.custom("Figtree", size: 17))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(theme.textPrimary)
            .textSelection(.enabled)
          if s.nextSteps.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
              Text("Then")
                .font(.custom("Figtree", size: 12).weight(.semibold))
                .foregroundStyle(theme.textMuted)
                .textCase(.uppercase)
              ForEach(Array(s.nextSteps.dropFirst().enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                  Text("\(i + 2)")
                    .font(.custom("Figtree", size: 12).weight(.bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(theme.chatSoftAccentFill))
                  Text(step)
                    .font(.custom("Figtree", size: 14))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
              }
            }
          }
          HStack(spacing: 10) {
            BriefingPill(title: "Resume my apps", systemImage: "arrow.uturn.forward") {
              Task { await service.resume() }
            }
            Spacer()
            thumbs
          }
        }
      }
    }
  }

  private var thumbs: some View {
    HStack(spacing: 6) {
      Text(thumbsGiven == nil ? "Useful?" : "Thanks")
        .font(.custom("Figtree", size: 12))
        .foregroundStyle(theme.textMuted)
      ForEach([true, false], id: \.self) { up in
        Button {
          thumbsGiven = up
          Task { await service.feedback(up: up) }
        } label: {
          Image(systemName: up ? "hand.thumbsup" : "hand.thumbsdown")
            .symbolVariant(thumbsGiven == up ? .fill : .none)
            .foregroundStyle(thumbsGiven == up ? theme.accent : theme.textMuted)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }
    }
  }

  // MARK: - Next thing + goal

  private var nextThingCard: some View {
    let s = service.sections
    return BriefingCardShell(tint: true) {
      VStack(alignment: .leading, spacing: 14) {
        BriefingCardTitle("Your next thing")
        Text(s.nextSteps.first ?? "Pick one small step and start.")
          .font(.custom("InstrumentSerif-Regular", size: 24))
          .foregroundStyle(theme.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        if let goal = (service.state?.sessionGoal).flatMap({ $0.isEmpty ? nil : $0 })
          ?? (s.goal.isEmpty ? nil : s.goal)
        {
          HStack(spacing: 8) {
            Image(systemName: "scope")
            Text(goal).lineLimit(2)
          }
          .font(.custom("Figtree", size: 13).weight(.medium))
          .foregroundStyle(theme.controlText)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(Capsule().fill(theme.controlFill))
          .overlay(Capsule().strokeBorder(theme.controlBorder, lineWidth: 1))
          .overlay(InnerGlow(shape: Capsule(), color: theme.controlInnerGlow, radius: 2))
        }
      }
    }
  }

  // MARK: - Open loops

  private var loopsCard: some View {
    let todos = (service.state?.todos ?? []).filter { !$0.done }
    return BriefingCardShell {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          BriefingCardTitle("Open loops")
          Spacer()
          if !todos.isEmpty {
            Text("\(todos.count)")
              .font(.custom("Figtree", size: 12).weight(.bold))
              .foregroundStyle(theme.accent)
          }
        }
        if todos.isEmpty {
          Text("All clear. Nothing open right now.")
            .font(.custom("Figtree", size: 14))
            .foregroundStyle(theme.textMuted)
        }
        ForEach(todos.prefix(6)) { todo in
          BriefingTodoRow(todo: todo) {
            Task { await service.setTodo(todo, done: true) }
          }
        }
        HStack(spacing: 8) {
          Image(systemName: "plus")
            .foregroundStyle(theme.textMuted)
          TextField("Add a loop…", text: $newTodo)
            .textFieldStyle(.plain)
            .font(.custom("Figtree", size: 14))
            .onSubmit {
              let t = newTodo
              newTodo = ""
              Task { await service.addTodo(t) }
            }
        }
        .padding(.top, 2)
      }
    }
  }

  // MARK: - Today strip

  private var todayStrip: some View {
    let cards = (service.state?.timeline ?? []).filter { ($0.type ?? "card") == "card" }
    return BriefingCardShell {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          BriefingCardTitle("Today so far")
          Spacer()
          Text("\(cards.count) \(cards.count == 1 ? "activity" : "activities")")
            .font(.custom("Figtree", size: 12))
            .foregroundStyle(theme.textMuted)
        }
        if cards.isEmpty {
          Text("Activity shows up here as Jarvis records your day.")
            .font(.custom("Figtree", size: 14))
            .foregroundStyle(theme.textMuted)
        } else {
          ScrollView(.horizontal) {
            HStack(spacing: 10) {
              ForEach(cards.reversed()) { card in
                BriefingActivityChip(card: card, color: color(for: card.category))
              }
            }
            .padding(.vertical, 2)
          }
          .scrollIndicators(.never)
        }
      }
    }
  }

  private func color(for category: String?) -> Color {
    guard let category,
      let match = categoryStore.categories.first(where: {
        $0.name.caseInsensitiveCompare(category) == .orderedSame
      })
    else { return theme.accent }
    return Color(hex: match.colorHex)
  }

  // MARK: - Focus

  private var focusCard: some View {
    let stats = service.state?.stats
    let minutes = stats?.totalMinutes ?? 0
    let top = stats?.byCategory?.max(by: { $0.value < $1.value })
    let best = (stats?.bestHours ?? []).prefix(2).map(hourLabel).joined(separator: ", ")
    return BriefingCardShell {
      VStack(alignment: .leading, spacing: 12) {
        BriefingCardTitle("This week")
        HStack(spacing: 10) {
          BriefingStat(value: durationLabel(minutes), label: "tracked")
          BriefingStat(value: best.isEmpty ? "–" : best, label: "best hours")
        }
        if let top {
          HStack(spacing: 8) {
            Circle().fill(color(for: top.key)).frame(width: 8, height: 8)
            Text("Most time: \(top.key) · \(durationLabel(top.value))")
              .font(.custom("Figtree", size: 13))
              .foregroundStyle(theme.textSecondary)
          }
        }
      }
    }
  }

  private func durationLabel(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }

  private func hourLabel(_ h: Int) -> String {
    let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
    return d.formatted(.dateTime.hour())
  }

  // MARK: - Ask

  private var askCard: some View {
    BriefingCardShell {
      VStack(alignment: .leading, spacing: 12) {
        BriefingCardTitle("Ask your past")
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(theme.textMuted)
          TextField("What was I doing yesterday afternoon?", text: $question)
            .textFieldStyle(.plain)
            .font(.custom("Figtree", size: 15))
            .onSubmit(submitAsk)
          if service.isAsking {
            ProgressView().controlSize(.small)
          } else if !question.isEmpty {
            BriefingPill(title: "Ask", systemImage: "arrow.up", prominent: true, action: submitAsk)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.inputFill))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
            theme.inputBorder, lineWidth: 1))

        if let answer = service.askAnswer {
          VStack(alignment: .leading, spacing: 8) {
            Markdown(BriefingSections.stripCitations(answer))
              .markdownTextStyle {
                FontFamily(.custom("Figtree"))
                FontSize(14)
                ForegroundColor(theme.textPrimary)
              }
              .textSelection(.enabled)
            Button("Clear") { service.clearAnswer() }
              .buttonStyle(.plain)
              .font(.custom("Figtree", size: 12))
              .foregroundStyle(theme.textMuted)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.chatSoftAccentFill)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
              theme.chatSoftAccentBorder, lineWidth: 1)
          )
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .animation(.easeOut(duration: 0.25), value: service.askAnswer)
    }
  }

  private func submitAsk() {
    let q = question
    Task { await service.ask(q) }
  }
}

// MARK: - Building blocks (styled like Daily's standup cards)

struct BriefingCardShell<Content: View>: View {
  @Environment(\.dayflowTheme) private var theme
  var tint = false
  @ViewBuilder let content: () -> Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    content()
      .padding(22)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(shape.fill(theme.standupCardGradient))
      .background(shape.fill(tint ? theme.chatSoftAccentFill : .clear))
      .overlay(
        shape.strokeBorder(
          theme.isDark ? theme.standupCardBorder : StandupStyle.strokeColor, lineWidth: 1)
      )
      .overlay(
        InnerGlow(shape: shape, color: theme.isDark ? .clear : theme.cardInnerGlow, radius: 3)
      )
      .shadow(
        color: theme.isDark ? .black.opacity(0.12) : StandupStyle.shadowColor, radius: 8, x: 0, y: 4
      )
  }
}

struct BriefingCardTitle: View {
  @Environment(\.dayflowTheme) private var theme
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.custom("InstrumentSerif-Regular", size: 22))
      .foregroundStyle(theme.isDark ? theme.textSecondary : StandupStyle.headingColor)
  }
}

struct BriefingPill: View {
  @Environment(\.dayflowTheme) private var theme
  let title: String
  let systemImage: String
  var prominent = false
  var busy = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if busy {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
        }
        Text(title).font(.custom("Figtree", size: 13).weight(.semibold))
      }
      .foregroundStyle(prominent ? theme.primaryButtonText : theme.controlText)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Capsule().fill(prominent ? theme.primaryButtonFill : theme.controlFill))
      .overlay(
        Capsule().strokeBorder(
          prominent ? theme.primaryButtonBorder : theme.controlBorder, lineWidth: 1)
      )
      .overlay(
        InnerGlow(
          shape: Capsule(),
          color: prominent ? theme.primaryButtonInnerGlow : theme.controlInnerGlow, radius: 2)
      )
      .scaleEffect(hovering ? 1.03 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .pointingHandCursor()
  }
}

private struct BriefingTodoRow: View {
  @Environment(\.dayflowTheme) private var theme
  let todo: BriefingTodo
  let onDone: () -> Void
  @State private var checked = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Button {
        withAnimation(.easeOut(duration: 0.2)) { checked = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: onDone)
      } label: {
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 15))
          .foregroundStyle(checked ? theme.accent : theme.textMuted)
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      Text(BriefingSections.stripCitations(todo.text))
        .font(.custom("Figtree", size: 14))
        .foregroundStyle(checked ? theme.textMuted : theme.textPrimary)
        .strikethrough(checked)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct BriefingActivityChip: View {
  @Environment(\.dayflowTheme) private var theme
  let card: BriefingCard
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Circle().fill(color).frame(width: 7, height: 7)
        Text(timeRange)
          .font(.custom("Figtree", size: 11).weight(.medium))
          .foregroundStyle(theme.cardTime)
      }
      Text(card.title ?? "Activity")
        .font(.custom("Figtree", size: 13).weight(.semibold))
        .foregroundStyle(theme.cardTitle)
        .lineLimit(2)
      if let cat = card.category, !cat.isEmpty {
        Text(cat)
          .font(.custom("Figtree", size: 11))
          .foregroundStyle(theme.textMuted)
      }
    }
    .padding(12)
    .frame(width: 170, alignment: .leading)
    .frame(minHeight: 84, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.cardFill))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(color.opacity(0.45), lineWidth: 1)
    )
    .help(card.summary ?? "")
  }

  private var timeRange: String {
    let start = Date(timeIntervalSince1970: TimeInterval(card.startTs))
    let f = Date.FormatStyle.dateTime.hour().minute()
    if let e = card.endTs {
      return "\(start.formatted(f)) – \(Date(timeIntervalSince1970: TimeInterval(e)).formatted(f))"
    }
    return start.formatted(f)
  }
}

private struct BriefingStat: View {
  @Environment(\.dayflowTheme) private var theme
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.custom("InstrumentSerif-Regular", size: 26))
        .foregroundStyle(theme.summaryValue)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(label)
        .font(.custom("Figtree", size: 12))
        .foregroundStyle(theme.textMuted)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.summaryCardFill))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
        theme.summaryCardBorder, lineWidth: 1))
  }
}

// MARK: - "More" pages (the advanced web dashboard, in a sheet)

enum BriefingMorePage: String, CaseIterable, Identifiable {
  case memory, projects, weekly, automations, improve, privacy, settings
  var id: String { rawValue }
  var title: String {
    switch self {
    case .memory: return "Memory"
    case .projects: return "Projects"
    case .weekly: return "Weekly report"
    case .automations: return "Automations"
    case .improve: return "Evolution Center"
    case .privacy: return "Privacy & cleanup"
    case .settings: return "Briefing settings"
    }
  }
  var icon: String {
    switch self {
    case .memory: return "brain"
    case .projects: return "folder"
    case .weekly: return "calendar"
    case .automations: return "bolt"
    case .improve: return "chart.line.uptrend.xyaxis"
    case .privacy: return "hand.raised"
    case .settings: return "slider.horizontal.3"
    }
  }
}

struct BriefingMoreSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dayflowTheme) private var theme
  let page: BriefingMorePage

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(page.title)
          .font(.custom("InstrumentSerif-Regular", size: 22))
          .foregroundStyle(theme.textPrimary)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      Divider()
      BriefingPanelView(tab: page.rawValue)
    }
    .frame(minWidth: 860, minHeight: 620)
  }
}
