//
//  NotchPillView.swift
//  Dayframe
//
//  The resting notch pill: a black capsule that hugs the notch. Left wing: the
//  focus ring and percentage. Right wing: Jarvis's eyes (open while recording,
//  closed when paused) and today's tracked time. Hover shows a one-line summary;
//  a click opens a card with the next thing and quick actions.
//
//  The ring, eyes and text sit at the same offsets the island show draws its last
//  frame with (Web/src/island/layout.ts), so the hand-off is seamless.
//

import AppKit
import SwiftUI

@MainActor
final class NotchPillModel: ObservableObject {
  enum Mode: Equatable { case rest, hover, open }

  @Published var mode: Mode = .rest
  @Published var stats: IslandStats = .empty
  @Published var recording = true
  @Published var nextThing: String?
  @Published var accentHex = "#F3854B"
  /// Bumped to make the eyes blink once (a new card, a hover).
  @Published var blinkSignal = 0
  /// Bumped to drip a droplet out of the pill (a new card was saved).
  @Published var dripSignal = 0
  /// True while a drip is showing; the panel grows a little to make room for it.
  @Published var isDripping = false
  @Published var lookOffset: CGSize = .zero

  var geometry: NotchGeometry
  var onToggleRecording: () -> Void = {}
  var onOpenApp: () -> Void = {}
  var onReplay: () -> Void = {}
  var onModeChange: (Mode) -> Void = { _ in }

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
    }
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
      } else {
        restContent
          .frame(width: pill.width, height: pill.height)
          .transition(.opacity)
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
      PillEyes(open: model.recording, blinkSignal: model.blinkSignal, look: model.lookOffset)
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
    .onTapGesture { model.setMode(.open) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Opens today's summary")
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
      Circle().fill(model.recording ? Color(hex: "#34D399") : Color(hex: "#8A8A8E")).frame(
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
    .background(Capsule().fill(Color(hex: "#1D1D1F")))
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
          .foregroundStyle(Color(hex: "#8A8A8E"))
      }
      Text(model.nextThing ?? "Pick one small step and start.")
        .font(.system(size: 13))
        .foregroundStyle(Color(hex: "#D0D0D4"))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      if s.focusGoalMinutes > 0 {
        VStack(alignment: .leading, spacing: 6) {
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule().fill(Color(hex: "#2A2A2E"))
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
          .foregroundStyle(Color(hex: "#D0D0D4"))
        }
      }
      HStack(spacing: 8) {
        CardButton(title: model.recording ? "Pause 30 min" : "Resume recording") {
          model.onToggleRecording()
        }
        CardButton(title: "Open Dayframe") {
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
    if inside {
      hoveredSinceOpen = true
      if model.mode == .rest {
        model.setMode(.hover)
        model.blinkSignal += 1
      }
      return
    }
    switch model.mode {
    case .hover:
      model.setMode(.rest)
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
      Circle().stroke(Color(hex: "#3A3A3C"), lineWidth: 2.4).frame(width: 18, height: 18)
      Circle()
        .trim(from: 0, to: min(max(fraction, 0), 1))
        .stroke(accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.6), value: fraction)
      Circle().fill(Color(hex: "#1C1C1E")).frame(width: 14, height: 14)
      Circle().fill(accent).frame(width: 4.8, height: 4.8)
    }
  }
}

/// Two small capsules. Closed (a thin line) while recording is paused; blinks on its own.
private struct PillEyes: View {
  let open: Bool
  let blinkSignal: Int
  let look: CGSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var blinking = false

  var body: some View {
    HStack(spacing: 4) {
      eye
      eye
    }
    .offset(look)
    .animation(.easeOut(duration: 0.18), value: look)
    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: open)
    .task(id: open) { await blinkLoop() }
    .onChange(of: blinkSignal) { _, _ in Task { await blink() } }
  }

  private var eye: some View {
    Capsule()
      .fill(.white)
      .frame(width: 4, height: open && !blinking ? 9 : 2)
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

private struct CardButton: View {
  let title: String
  var subtle = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(subtle ? Color(hex: "#8A8A8E") : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          Capsule().fill(Color(hex: subtle ? "#1C1C1E" : "#2A2A2E").opacity(hovering ? 1 : 0.85)))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
