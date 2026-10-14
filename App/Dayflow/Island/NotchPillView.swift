//
//  NotchPillView.swift
//  Dayframe
//
//  The resting notch pill: a black capsule that hugs the notch. Left wing: the
//  focus ring and percentage. Right wing: Jarvis's eyes (open while recording,
//  closed when paused) and today's tracked time. Hover shows a one-line summary;
//  a click opens a card with the next thing and quick actions.
//
//  Briefing's messages (BriefingNotice) arrive as a quiet peek: the pill grows one
//  line below the notch, then tucks the message away and the eyes take the accent
//  colour until it is read. Hover peeks again; a click opens the full notice card.
//
//  The ring, eyes and text sit at the same offsets the island show draws its last
//  frame with (Web/src/island/layout.ts), so the hand-off is seamless.
//

import AppKit
import SwiftUI

@MainActor
final class NotchPillModel: ObservableObject {
  enum Mode: Equatable { case rest, hover, open, peek, notice }

  @Published var mode: Mode = .rest
  @Published var stats: IslandStats = .empty
  @Published var recording = true
  @Published var nextThing: String?
  @Published var accentHex = DayframePalette.original.accentHex
  /// Bumped to make the eyes blink once (a new card, a hover).
  @Published var blinkSignal = 0
  /// Bumped to drip a droplet out of the pill (a new card was saved).
  @Published var dripSignal = 0
  /// True while a drip is showing; the panel grows a little to make room for it.
  @Published var isDripping = false
  @Published var lookOffset: CGSize = .zero
  /// Briefing's current message, shown as a peek and then as the notice card.
  @Published var notice: BriefingNotice?
  /// What Jarvis is doing; the eyes open and take the accent while it listens, thinks or speaks.
  @Published var jarvis: JarvisPresence = .idle
  /// True while the pointer is over the pill (the controller never tucks a peek away under it).
  var isHovering = false

  var geometry: NotchGeometry
  var onToggleRecording: () -> Void = {}
  var onOpenApp: () -> Void = {}
  var onReplay: () -> Void = {}
  var onModeChange: (Mode) -> Void = { _ in }
  /// The notice is done: `answered` with the text (nil = skipped) for asks.
  var onNoticeDone: (BriefingNotice, _ answered: Bool, _ text: String?) -> Void = { _, _, _ in }
  var onOpenBriefing: () -> Void = {}
  /// The ask card needs the keyboard (the panel becomes key without activating Dayframe).
  var onNeedsKeyboard: (Bool) -> Void = { _ in }

  init(geometry: NotchGeometry) {
    self.geometry = geometry
  }

  func setMode(_ new: Mode) {
    guard new != mode else { return }
    mode = new
    onModeChange(new)
  }

  /// The panel's size for each mode; the pill is always anchored at its top-left.
  func contentSize(for mode: Mode) -> CGSize {
    let pill = geometry.pillRect.size
    switch mode {
    case .rest: return CGSize(width: pill.width, height: pill.height + (isDripping ? 18 : 0))
    case .hover: return CGSize(width: max(pill.width, 360), height: pill.height + 44)
    case .open:
      return CGSize(
        width: max(pill.width, NotchPillLayout.cardWidth), height: NotchPillLayout.cardHeight)
    case .peek:
      return CGSize(
        width: max(pill.width, NotchPillLayout.peekWidth),
        height: pill.height + NotchPillLayout.peekRow)
    case .notice:
      return CGSize(width: max(pill.width, NotchPillLayout.cardWidth), height: noticeHeight)
    }
  }

  /// The notice card's height, from its content (the panel must know it before SwiftUI lays out).
  var noticeHeight: CGFloat {
    guard let n = notice else { return NotchPillLayout.cardHeight }
    let layout = NotchPillLayout.self
    var parts: [CGFloat] = [geometry.pillRect.height - 4, 20]
    switch n.kind {
    case .brief:
      let s = n.sections
      if !s.leftOff.isEmpty { parts.append(layout.textHeight(s.leftOff, lines: 3)) }
      let steps = min(s.nextSteps.count, 3)
      if steps > 0 { parts.append(CGFloat(steps) * layout.stepRow + CGFloat(steps - 1) * 6) }
      if !s.question.isEmpty || !s.notes.isEmpty { parts.append(16) }
    case .ask:
      parts.append(layout.textHeight(n.prompt, lines: 4))
      parts.append(layout.fieldHeight)
    case .resume:
      parts.append(layout.textHeight(n.text, lines: 4))
    case .peek:
      parts.append(layout.textHeight(n.text, lines: 4))
    }
    parts.append(layout.buttonRow)
    return parts.reduce(0, +) + layout.cardSpacing * CGFloat(parts.count - 1) + layout.cardBottom
      + 4
  }
}

enum NotchPillLayout {
  static let badgeInset: CGFloat = 18
  static let textGap: CGFloat = 16
  static let eyesInset: CGFloat = 16
  static let timeInset: CGFloat = 30
  static let cardWidth: CGFloat = 420
  static let cardHeight: CGFloat = 214
  static let spring = Animation.spring(response: 0.42, dampingFraction: 0.74)
  static let peekWidth: CGFloat = 400
  static let peekRow: CGFloat = 34
  static let cardSpacing: CGFloat = 10
  static let cardBottom: CGFloat = 18
  static let stepRow: CGFloat = 17
  static let fieldHeight: CGFloat = 34
  static let buttonRow: CGFloat = 28
  static let bodyFont = NSFont.systemFont(ofSize: 13)

  /// Height of 13 pt body text in the card, capped at `lines`.
  static func textHeight(_ text: String, lines: Int) -> CGFloat {
    let width = cardWidth - 48
    let line = ceil(NSLayoutManager().defaultLineHeight(for: bodyFont))
    let rect = (text as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: bodyFont])
    return min(ceil(rect.height), line * CGFloat(lines))
  }
}

struct NotchPillView: View {
  @ObservedObject var model: NotchPillModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dripOffset: CGFloat = 0
  @State private var leaveTask: Task<Void, Never>?
  @State private var hoveredSinceOpen = false

  private var geo: NotchGeometry { model.geometry }
  private var pill: CGSize { geo.pillRect.size }
  private var accent: Color { Color(hex: model.accentHex) }

  /// Width/height/radius of the black shape for the current mode.
  private var shape: (w: CGFloat, h: CGFloat, r: CGFloat) {
    switch model.mode {
    case .rest, .hover: return (pill.width, pill.height, geo.pillRadius)
    case .open: return (NotchPillLayout.cardWidth, NotchPillLayout.cardHeight, 28)
    case .peek:
      return (
        max(pill.width, NotchPillLayout.peekWidth), pill.height + NotchPillLayout.peekRow, 20
      )
    case .notice: return (NotchPillLayout.cardWidth, model.noticeHeight, 28)
    }
  }

  var body: some View {
    let s = shape
    let size = model.contentSize(for: model.mode)
    ZStack(alignment: .top) {
      // Drip: a droplet slides out of the pill and is pulled back in.
      Circle()
        .fill(.black)
        .frame(width: 9, height: 9)
        .offset(y: pill.height - 6 + dripOffset)
        .opacity(dripOffset > 0.5 ? 1 : 0)

      UnevenRoundedRectangle(
        bottomLeadingRadius: s.r, bottomTrailingRadius: s.r, style: .continuous
      )
      .fill(.black)
      .frame(width: s.w, height: s.h)

      if model.mode == .open {
        card
          .frame(
            width: NotchPillLayout.cardWidth, height: NotchPillLayout.cardHeight, alignment: .top
          )
          .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      } else if model.mode == .notice, let notice = model.notice {
        NoticeCard(
          notice: notice, accent: accent, topInset: pill.height - 4,
          onDone: { answered, text in model.onNoticeDone(notice, answered, text) },
          onOpenBriefing: { model.onOpenBriefing() },
          onNeedsKeyboard: { model.onNeedsKeyboard($0) }
        )
        .id(notice.id)
        .frame(width: NotchPillLayout.cardWidth, height: model.noticeHeight, alignment: .top)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      } else {
        restContent
          .frame(width: pill.width, height: pill.height)
          .transition(.opacity)
        if model.mode == .peek, let notice = model.notice {
          peekRow(notice)
            .offset(y: pill.height)
            .transition(.opacity.combined(with: .offset(y: -6)))
        }
      }

      if model.mode == .hover {
        tooltip
          .offset(y: pill.height + 8)
          .transition(.opacity.combined(with: .offset(y: -4)))
      }
    }
    .frame(width: size.width, height: size.height, alignment: .top)
    .animation(reduceMotion ? .easeOut(duration: 0.15) : NotchPillLayout.spring, value: model.mode)
    .contentShape(Rectangle())
    .onHover(perform: hoverChanged)
    .onChange(of: model.dripSignal) { _, _ in drip() }
    .accessibilityElement(children: .contain)
  }

  // MARK: - Rest

  private var restContent: some View {
    let midY = pill.height / 2
    let notchRight = NotchGeometry.leftWing + geo.notchWidth
    return ZStack(alignment: .topLeading) {
      Color.clear
      FocusRing(fraction: model.stats.focusFraction, accent: accent)
        .frame(width: 22, height: 22)
        .position(x: NotchPillLayout.badgeInset, y: midY)
      Text("\(model.stats.focusPercent)%")
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .fixedSize()
        .position(x: NotchPillLayout.badgeInset + NotchPillLayout.textGap, y: midY)
        .offset(x: textHalfWidth("\(model.stats.focusPercent)%"))
      PillEyes(
        open: model.recording || model.jarvis != .idle, blinkSignal: model.blinkSignal,
        look: model.lookOffset,
        tint: model.notice == nil && model.jarvis == .idle ? .white : accent,
        pulsing: model.jarvis == .thinking
      )
      .position(x: notchRight + NotchPillLayout.eyesInset, y: midY)
      Text(model.stats.trackedMinutes.islandDuration)
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .fixedSize()
        .position(x: notchRight + NotchPillLayout.timeInset, y: midY)
        .offset(x: textHalfWidth(model.stats.trackedMinutes.islandDuration))
    }
    .contentShape(Rectangle())
    .onTapGesture { model.setMode(model.notice == nil ? .open : .notice) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(model.notice.map { "Briefing: \($0.peekLine)" } ?? summary)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint(model.notice == nil ? "Opens today's summary" : "Opens the message")
  }

  // MARK: - Peek

  /// One line under the notch: an accent dot, the message, a chevron that says "there's more".
  private func peekRow(_ notice: BriefingNotice) -> some View {
    HStack(spacing: 8) {
      Circle().fill(accent).frame(width: 6, height: 6)
      Text(notice.peekLine)
        .font(.system(size: 12.5))
        .foregroundStyle(PillInk.body)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 4)
      if notice.kind != .peek {
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(PillInk.muted)
      }
    }
    .padding(.horizontal, 20)
    .frame(width: max(pill.width, NotchPillLayout.peekWidth), height: NotchPillLayout.peekRow - 4)
    .contentShape(Rectangle())
    .onTapGesture { if notice.kind != .peek { model.setMode(.notice) } }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(notice.peekLine)
    .accessibilityAddTraits(.isButton)
  }

  /// `.position` centers a view; the page draws these labels left-aligned at x, so shift by half the width.
  private func textHalfWidth(_ text: String) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    return (text as NSString).size(withAttributes: [.font: font]).width / 2
  }

  private var summary: String {
    let s = model.stats
    var parts = ["\(s.trackedMinutes.islandDuration) tracked today"]
    if s.focusGoalMinutes > 0 {
      parts.insert(
        "\(s.focusMinutes.islandDuration) of \(s.focusGoalMinutes.islandDuration) focus", at: 0)
    }
    parts.append(model.recording ? "recording" : "paused")
    return parts.joined(separator: ", ")
  }

  /// One short line; the dot says whether recording is on.
  private var tooltipText: String {
    let s = model.stats
    let tracked = "\(s.trackedMinutes.islandDuration) tracked"
    guard s.focusGoalMinutes > 0 else {
      return tracked.prefix(1).uppercased() + tracked.dropFirst()
    }
    return
      "Focus \(s.focusMinutes.islandDuration) of \(s.focusGoalMinutes.islandDuration), \(tracked)"
  }

  private var tooltip: some View {
    HStack(spacing: 6) {
      Circle().fill(model.recording ? PillInk.live : PillInk.muted).frame(
        width: 6, height: 6
      )
      .accessibilityLabel(model.recording ? "Recording" : "Paused")
      Text(tooltipText)
        .lineLimit(1)
    }
    .font(.system(size: 12))
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Capsule().fill(PillInk.tooltip))
    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
    .fixedSize()
  }

  // MARK: - Card

  private var card: some View {
    let s = model.stats
    return VStack(alignment: .leading, spacing: 12) {
      Color.clear.frame(height: pill.height - 4)  // the notch row stays clear
      HStack(alignment: .firstTextBaseline) {
        Text("Your next thing")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(model.recording ? "Recording" : "Paused")
          .font(.system(size: 12))
          .foregroundStyle(PillInk.muted)
      }
      Text(model.nextThing ?? "Pick one small step and start.")
        .font(.system(size: 13))
        .foregroundStyle(PillInk.body)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      if s.focusGoalMinutes > 0 {
        VStack(alignment: .leading, spacing: 6) {
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule().fill(PillInk.track)
              Capsule().fill(accent).frame(
                width: max(6, proxy.size.width * min(s.focusFraction, 1)))
            }
          }
          .frame(height: 6)
          HStack {
            Text("\(s.focusMinutes.islandDuration) of \(s.focusGoalMinutes.islandDuration) focus")
            Spacer()
            Text("\(s.trackedMinutes.islandDuration) tracked")
          }
          .font(.system(size: 12))
          .foregroundStyle(PillInk.body)
        }
      }
      HStack(spacing: 8) {
        CardButton(title: model.recording ? "Pause 30 min" : "Resume recording") {
          model.onToggleRecording()
        }
        CardButton(title: "Open Jarvis") {
          model.setMode(.rest)
          model.onOpenApp()
        }
        Spacer()
        CardButton(title: "Replay", subtle: true) {
          model.setMode(.rest)
          model.onReplay()
        }
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 24)
    .padding(.bottom, 18)
  }

  // MARK: - Behaviour

  private func hoverChanged(_ inside: Bool) {
    leaveTask?.cancel()
    model.isHovering = inside
    if inside {
      hoveredSinceOpen = true
      if model.mode == .rest {
        model.setMode(model.notice == nil ? .hover : .peek)
        model.blinkSignal += 1
      }
      return
    }
    switch model.mode {
    case .hover:
      model.setMode(.rest)
    case .peek:
      model.setMode(.rest)
    case .notice:
      // A question stays open while you type; a briefing waits a moment for a wobbly pointer.
      guard model.notice?.kind != .ask else { return }
      leaveTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        model.setMode(.rest)
      }
    case .open:
      // Leave the card open briefly so a slightly wobbly pointer doesn't slam it shut.
      leaveTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled else { return }
        model.setMode(.rest)
      }
    case .rest:
      break
    }
  }

  private func drip() {
    guard !reduceMotion, model.mode == .rest else { return }
    model.isDripping = true
    Task { @MainActor in
      // Let the panel grow first, then the droplet slides out and is pulled back in.
      try? await Task.sleep(for: .milliseconds(30))
      withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { dripOffset = 10 }
      try? await Task.sleep(for: .milliseconds(380))
      withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dripOffset = 0 }
      try? await Task.sleep(for: .milliseconds(450))
      model.isDripping = false
    }
  }
}

/// The left-wing badge: track, accent arc from 12 o'clock, dark disc, accent dot.
private struct FocusRing: View {
  let fraction: Double
  let accent: Color

  var body: some View {
    ZStack {
      Circle().stroke(PillInk.eyeRing, lineWidth: 2.4).frame(width: 18, height: 18)
      Circle()
        .trim(from: 0, to: min(max(fraction, 0), 1))
        .stroke(accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.6), value: fraction)
      Circle().fill(PillInk.surface).frame(width: 14, height: 14)
      Circle().fill(accent).frame(width: 4.8, height: 4.8)
    }
  }
}

/// Two small capsules. Closed (a thin line) while recording is paused; blinks on its own.
private struct PillEyes: View {
  let open: Bool
  let blinkSignal: Int
  let look: CGSize
  var tint: Color = .white
  /// Jarvis is thinking: the eyes breathe.
  var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var blinking = false
  @State private var dim = false

  var body: some View {
    HStack(spacing: 4) {
      eye
      eye
    }
    .offset(look)
    .opacity(pulsing && dim ? 0.35 : 1)
    .task(id: pulsing) {
      guard pulsing, !reduceMotion else {
        dim = false
        return
      }
      while !Task.isCancelled {
        withAnimation(.easeInOut(duration: 0.6)) { dim.toggle() }
        try? await Task.sleep(for: .milliseconds(600))
      }
      dim = false
    }
    .animation(.easeOut(duration: 0.18), value: look)
    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: open)
    .task(id: open) { await blinkLoop() }
    .onChange(of: blinkSignal) { _, _ in Task { await blink() } }
  }

  private var eye: some View {
    Capsule()
      .fill(tint)
      .frame(width: 4, height: open && !blinking ? 9 : 2)
      .animation(.easeOut(duration: 0.3), value: tint)
  }

  private func blink() async {
    guard open, !reduceMotion else { return }
    withAnimation(.easeIn(duration: 0.07)) { blinking = true }
    try? await Task.sleep(for: .milliseconds(110))
    withAnimation(.easeOut(duration: 0.1)) { blinking = false }
  }

  /// A natural blink every 2.5–5.5 s while the eyes are open.
  private func blinkLoop() async {
    while !Task.isCancelled, open {
      try? await Task.sleep(for: .milliseconds(Int.random(in: 2500...5500)))
      guard !Task.isCancelled else { return }
      await blink()
    }
  }
}

/// Briefing's message, opened from the pill: the briefing in three short parts, a question with a
/// one-line answer, or a nudge. Same black card, type and buttons as the pill's own card.
private struct NoticeCard: View {
  let notice: BriefingNotice
  let accent: Color
  let topInset: CGFloat
  let onDone: (_ answered: Bool, _ text: String?) -> Void
  let onOpenBriefing: () -> Void
  let onNeedsKeyboard: (Bool) -> Void
  @State private var answer = ""
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: NotchPillLayout.cardSpacing) {
      Color.clear.frame(height: topInset)  // the notch row stays clear
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
        Spacer()
        Text(
          notice.kind == .ask
            ? "Briefing asks" : notice.kind == .resume ? "Resume workspace" : "Briefing"
        )
        .font(.system(size: 12))
        .foregroundStyle(PillInk.muted)
      }
      .frame(height: 20)
      switch notice.kind {
      case .brief: brief
      case .ask: ask
      case .resume: resumeCard
      case .peek: nudge
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 24)
    .padding(.bottom, NotchPillLayout.cardBottom)
  }

  private var title: String {
    if notice.kind == .brief, notice.title.isEmpty || notice.title == "Where you left off" {
      return "Where you left off"
    }
    return notice.title.isEmpty ? "Briefing" : notice.title
  }

  // MARK: Briefing

  @ViewBuilder private var brief: some View {
    let s = notice.sections
    if !s.leftOff.isEmpty {
      Text(s.leftOff)
        .font(.system(size: 13))
        .foregroundStyle(PillInk.body)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    let steps = Array(s.nextSteps.prefix(3))
    if !steps.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(i + 1)")
              .font(.system(size: 12, weight: .semibold))
              .monospacedDigit()
              .foregroundStyle(accent)
              .frame(width: 10, alignment: .leading)
            Text(step)
              .font(.system(size: 13))
              .foregroundStyle(.white)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .frame(height: NotchPillLayout.stepRow, alignment: .leading)
        }
      }
    }
    if let footnote = footnote(s) {
      HStack(spacing: 6) {
        Circle().fill(accent.opacity(0.8)).frame(width: 5, height: 5)
        Text(footnote).lineLimit(1)
      }
      .font(.system(size: 12))
      .foregroundStyle(PillInk.muted)
      .frame(height: 16)
    }
    HStack(spacing: 8) {
      CardButton(title: "Open Briefing") {
        onOpenBriefing()
        onDone(false, nil)
      }
      Spacer()
      CardButton(title: "Done", subtle: true) { onDone(false, nil) }
    }
    .frame(height: NotchPillLayout.buttonRow)
  }

  /// "A memory to confirm", stale facts or a suggested improvement: one quiet line, details in Briefing.
  private func footnote(_ s: BriefingSections) -> String? {
    if !s.question.isEmpty {
      let more =
        s.question.range(of: #"\(\+(\d+) more\)"#, options: .regularExpression)
        .map { s.question[$0].filter(\.isNumber) }
        .flatMap { Int($0) } ?? 0
      let n = more + 1
      return n == 1 ? "1 memory to confirm in Briefing" : "\(n) memories to confirm in Briefing"
    }
    return s.notes.first
  }

  // MARK: Question

  @ViewBuilder private var ask: some View {
    Text(notice.prompt)
      .font(.system(size: 13))
      .foregroundStyle(PillInk.body)
      .lineLimit(4)
      .fixedSize(horizontal: false, vertical: true)
    TextField(
      "", text: $answer,
      prompt: Text(notice.defaultAnswer.isEmpty ? "Type a line, then Return" : notice.defaultAnswer)
        .foregroundColor(PillInk.muted)
    )
    .textFieldStyle(.plain)
    .font(.system(size: 13))
    .foregroundStyle(.white)
    .focused($fieldFocused)
    .onSubmit(save)
    .padding(.horizontal, 12)
    .frame(height: NotchPillLayout.fieldHeight)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PillInk.surface))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(fieldFocused ? accent.opacity(0.7) : PillInk.track, lineWidth: 1)
    )
    .onAppear {
      answer = notice.defaultAnswer
      onNeedsKeyboard(true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { fieldFocused = true }
    }
    .onDisappear { onNeedsKeyboard(false) }
    HStack(spacing: 8) {
      CardButton(title: "Save", action: save)
      Spacer()
      CardButton(title: "Skip", subtle: true) { onDone(true, nil) }
    }
    .frame(height: NotchPillLayout.buttonRow)
  }

  private func save() { onDone(true, answer) }

  // MARK: Resume

  @ViewBuilder private var resumeCard: some View {
    Text(notice.text)
      .font(.system(size: 13))
      .foregroundStyle(PillInk.body)
      .lineLimit(4)
      .fixedSize(horizontal: false, vertical: true)
    HStack(spacing: 8) {
      CardButton(title: "Resume") { onDone(true, "resume") }
      Spacer()
      CardButton(title: "Not now", subtle: true) { onDone(true, nil) }
    }
    .frame(height: NotchPillLayout.buttonRow)
  }

  // MARK: Nudge

  @ViewBuilder private var nudge: some View {
    Text(notice.text)
      .font(.system(size: 13))
      .foregroundStyle(PillInk.body)
      .lineLimit(4)
      .fixedSize(horizontal: false, vertical: true)
    HStack {
      Spacer()
      CardButton(title: "Got it", subtle: true) { onDone(false, nil) }
    }
    .frame(height: NotchPillLayout.buttonRow)
  }
}

private struct CardButton: View {
  let title: String
  var subtle = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(subtle ? PillInk.muted : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          Capsule().fill((subtle ? PillInk.surface : PillInk.track).opacity(hovering ? 1 : 0.85)))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}

/// The pill's fixed neutrals. It always sits on the black notch, so only the accent follows the
/// palette; these stay put.
private enum PillInk {
  static let live = Color(hex: "#34D399")
  static let muted = Color(hex: "#8A8A8E")
  static let body = Color(hex: "#D0D0D4")
  static let tooltip = Color(hex: "#1D1D1F")
  static let track = Color(hex: "#2A2A2E")
  static let surface = Color(hex: "#1C1C1E")
  static let eyeRing = Color(hex: "#3A3A3C")
}
