//
//  DayframePalette.swift
//  Dayframe
//
//  Color palettes layered on top of the upstream light/dark themes.
//  "Original" is Dayflow's own peach-and-sky look and stays the default;
//  the others recolor the background glow, accent, glass controls and buttons.
//

import AppKit
import SwiftUI

enum DayframePalette: String, CaseIterable, Identifiable {
  case original
  case lagoon
  case lavender
  case matcha
  case rose
  case ember

  static let storageKey = "dayframePalette"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .original: return "Original"
    case .lagoon: return "Lagoon"
    case .lavender: return "Lavender"
    case .matcha: return "Matcha"
    case .rose: return "Rose"
    case .ember: return "Ember"
    }
  }

  /// Two colors used for the picker orb.
  var swatch: [Color] {
    switch self {
    case .original: return [Color(hex: "FFD2B9"), Color(hex: "D6E8FF")]
    case .lagoon: return [Color(hex: "9FE7DC"), Color(hex: "BFD9FF")]
    case .lavender: return [Color(hex: "D9C7FF"), Color(hex: "FFD3E6")]
    case .matcha: return [Color(hex: "CFE8B4"), Color(hex: "F3E9C6")]
    case .rose: return [Color(hex: "FFC2CC"), Color(hex: "FFE0C7")]
    case .ember: return [Color(hex: "FFB27A"), Color(hex: "5A3B74")]
    }
  }

  fileprivate struct Spec {
    let lightBG: [String]
    let darkBG: [String]
    let accent: String
    let accentTextLight: String
    let accentTextDark: String
    let controlFill: String
    let controlBorder: String
    let controlGlow: String
    let buttonLight: String
    let buttonDark: String
    let softFill: String
  }

  fileprivate var spec: Spec? {
    switch self {
    case .original:
      return nil
    case .lagoon:
      return Spec(
        lightBG: ["C9F2EA", "DDEFFF", "E4E2FF"], darkBG: ["1E4A57", "233548", "2C2F55"],
        accent: "1C9E94", accentTextLight: "45BDB2", accentTextDark: "6ED8CC",
        controlFill: "B6EAE2", controlBorder: "C6E2DD", controlGlow: "E3F8F4",
        buttonLight: "2BB3A7", buttonDark: "1C8C83", softFill: "E8F8F5")
    case .lavender:
      return Spec(
        lightBG: ["E6D9FF", "FFE1EE", "D9E6FF"], darkBG: ["3B2F66", "33304F", "4A2A55"],
        accent: "8A63F2", accentTextLight: "A98BFF", accentTextDark: "C2A9FF",
        controlFill: "DCCBFF", controlBorder: "DCD2EE", controlGlow: "F1EAFF",
        buttonLight: "9874F5", buttonDark: "6F4FD1", softFill: "F3EEFF")
    case .matcha:
      return Spec(
        lightBG: ["DDEFC8", "F4EED6", "D6ECE2"], darkBG: ["2D4A33", "2E3B35", "3D3A2C"],
        accent: "5C9A3B", accentTextLight: "7DB85A", accentTextDark: "A2D67F",
        controlFill: "D2E9BD", controlBorder: "D8E3CB", controlGlow: "EEF7E4",
        buttonLight: "6DAA49", buttonDark: "4F8A33", softFill: "F1F8E9")
    case .rose:
      return Spec(
        lightBG: ["FFD6DD", "FFE8D8", "EEDDF7"], darkBG: ["5A2D40", "432F45", "4D3242"],
        accent: "E0557A", accentTextLight: "F27C9B", accentTextDark: "FF9DB7",
        controlFill: "FFC9D3", controlBorder: "F0D3D9", controlGlow: "FFEAEE",
        buttonLight: "EC6B8D", buttonDark: "C24767", softFill: "FFF0F3")
    case .ember:
      return Spec(
        lightBG: ["FFD0A8", "FFC7B8", "E3D2F5"], darkBG: ["5C3420", "4A2B3E", "35285A"],
        accent: "F06A1F", accentTextLight: "FF8F4F", accentTextDark: "FFA36B",
        controlFill: "FFC39C", controlBorder: "EFCDB8", controlGlow: "FFE6D6",
        buttonLight: "F57A33", buttonDark: "C9551A", softFill: "FFF0E5")
    }
  }

  /// Applies this palette to a resolved upstream theme.
  func apply(to base: DayflowTheme) -> DayflowTheme {
    guard let s = spec else { return base }
    var t = base
    let bg = (base.isDark ? s.darkBG : s.lightBG).map { Color(hex: $0) }
    if base.isDark {
      t.windowBackground = AnyShapeStyle(
        LinearGradient(
          stops: [
            .init(color: bg[0], location: 0.21),
            .init(color: bg[1], location: 0.53),
            .init(color: bg[2], location: 1.05),
          ],
          startPoint: UnitPoint(x: 0, y: 0.63),
          endPoint: UnitPoint(x: 1, y: 0.37)))
      t.accentText = Color(hex: s.accentTextDark)
      t.controlFill = Color(hex: s.accent).opacity(0.4)
      t.controlBorder = Color(hex: s.accent).opacity(0.7)
      t.controlInnerGlow = Color(hex: s.accentTextDark).opacity(0.5)
      t.primaryButtonFill = Color(hex: s.buttonDark)
      t.primaryButtonBorder = Color(hex: s.accentTextDark)
      t.primaryButtonInnerGlow = Color(hex: s.accentTextDark).opacity(0.9)
      t.chatSoftAccentFill = Color(hex: s.accent).opacity(0.18)
      t.chatSoftAccentBorder = Color(hex: s.accentTextDark).opacity(0.4)
    } else {
      t.windowBackground = AnyShapeStyle(
        RadialGradient(
          stops: [
            .init(color: bg[0], location: 0.17),
            .init(color: bg[1], location: 0.33),
            .init(color: bg[2], location: 1),
          ],
          center: UnitPoint(x: 0.64, y: 1.0), startRadius: 0, endRadius: 1250))
      t.accentText = Color(hex: s.accentTextLight)
      t.controlFill = Color(hex: s.controlFill)
      t.controlBorder = Color(hex: s.controlBorder)
      t.controlInnerGlow = Color(hex: s.controlGlow)
      t.primaryButtonFill = Color(hex: s.buttonLight)
      t.primaryButtonBorder = Color(hex: s.controlBorder)
      t.primaryButtonInnerGlow = Color(hex: s.controlGlow).opacity(0.9)
      t.chatSoftAccentFill = Color(hex: s.softFill)
      t.chatSoftAccentBorder = Color(hex: s.accent).opacity(0.25)
    }
    t.accent = Color(hex: s.accent)
    return t
  }
}

// MARK: - Store + animated switching

/// Holds the active palette and drives the "ink spread" transition: the old
/// window is frozen as a snapshot, then a growing circle from the click point
/// reveals the new colors underneath.
@MainActor
final class DayframePaletteStore: ObservableObject {
  static let shared = DayframePaletteStore()

  @Published private(set) var palette: DayframePalette
  @Published var transition: PaletteTransition?

  struct PaletteTransition: Identifiable {
    let id = UUID()
    let snapshot: NSImage
    let origin: CGPoint  // in window content coordinates, top-left origin
    var progress: CGFloat = 0
  }

  private init() {
    palette =
      DayframePalette(rawValue: UserDefaults.standard.string(forKey: DayframePalette.storageKey) ?? "")
      ?? .original
  }

  /// Switch palettes. `origin` is where the user clicked, in window coordinates
  /// (top-left origin); pass nil to spread from the center.
  func select(_ next: DayframePalette, from origin: CGPoint? = nil, in window: NSWindow? = nil) {
    guard next != palette else { return }
    let win = window ?? NSApp.keyWindow
    if let win, let view = win.contentView,
      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    {
      view.cacheDisplay(in: view.bounds, to: rep)
      let image = NSImage(size: view.bounds.size)
      image.addRepresentation(rep)
      let point = origin ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
      transition = PaletteTransition(snapshot: image, origin: point)
    }
    palette = next
    UserDefaults.standard.set(next.rawValue, forKey: DayframePalette.storageKey)
  }

  func finishTransition() { transition = nil }
}

/// Overlay that plays the reveal. Attach once at the window root, above content.
struct PaletteRevealOverlay: View {
  @ObservedObject var store = DayframePaletteStore.shared
  @State private var grown = false

  var body: some View {
    GeometryReader { geo in
      if let t = store.transition {
        let maxR = hypot(
          max(t.origin.x, geo.size.width - t.origin.x),
          max(t.origin.y, geo.size.height - t.origin.y))
        Image(nsImage: t.snapshot)
          .resizable()
          .frame(width: geo.size.width, height: geo.size.height)
          .mask(
            // Everything except the growing hole shows the old snapshot.
            Rectangle()
              .overlay(
                Circle()
                  .frame(width: grown ? maxR * 2.1 : 1, height: grown ? maxR * 2.1 : 1)
                  .position(t.origin)
                  .blendMode(.destinationOut)
              )
              .compositingGroup()
          )
          .allowsHitTesting(false)
          .id(t.id)
          .onAppear {
            grown = false
            withAnimation(.easeInOut(duration: 0.75)) { grown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
              store.finishTransition()
              grown = false
            }
          }
      }
    }
    .allowsHitTesting(false)
  }
}

/// A row of glossy color orbs. Clicking one spreads the new palette from the orb.
struct PalettePicker: View {
  @ObservedObject private var store = DayframePaletteStore.shared
  @Environment(\.dayflowTheme) private var theme
  var orbSize: CGFloat = 30

  var body: some View {
    HStack(spacing: 14) {
      ForEach(DayframePalette.allCases) { p in
        PaletteOrb(palette: p, selected: store.palette == p, size: orbSize)
      }
    }
  }
}

private struct PaletteOrb: View {
  let palette: DayframePalette
  let selected: Bool
  let size: CGFloat
  @State private var hovering = false

  var body: some View {
    VStack(spacing: 6) {
      GeometryReader { geo in
        Button {
          guard let window = NSApp.keyWindow, let content = window.contentView else {
            DayframePaletteStore.shared.select(palette)
            return
          }
          // Orb center in window content coordinates (top-left origin).
          let frame = geo.frame(in: .global)
          let point = CGPoint(x: frame.midX, y: frame.midY)
          _ = content
          DayframePaletteStore.shared.select(palette, from: point, in: window)
        } label: {
          ZStack {
            Circle()
              .fill(
                AngularGradient(
                  colors: palette.swatch + [palette.swatch[0]], center: .center,
                  angle: .degrees(hovering ? 140 : 0)))
            Circle()
              .fill(
                RadialGradient(
                  colors: [Color.white.opacity(0.75), .clear], center: UnitPoint(x: 0.3, y: 0.25),
                  startRadius: 0, endRadius: size * 0.55))
            Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
          }
          .frame(width: size, height: size)
          .overlay(
            Circle()
              .strokeBorder(Color.primary.opacity(selected ? 0.55 : 0), lineWidth: 2)
              .padding(-4)
          )
          .scaleEffect(hovering ? 1.12 : 1)
          .shadow(color: palette.swatch[0].opacity(hovering ? 0.8 : 0.35), radius: hovering ? 8 : 3)
          .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(palette.title)
      }
      .frame(width: size, height: size)
      Text(palette.title)
        .font(.custom("Figtree", size: 11))
        .foregroundColor(.secondary)
    }
  }
}
