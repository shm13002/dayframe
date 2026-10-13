//
//  AppIconArt.swift
//  Dayframe
//
//  The app icon is the welcome's final mark: the eclipse ring and its three locks on the
//  night-sky tile (Web/src/welcome/scene.ts, drawTile + drawEclipse), so the Dock matches
//  the animation. While Dayframe runs, the Dock icon follows the active palette
//  (AppIconManager). The bundled AppIcon is the Original palette, written by
//  AppIconTests.testWriteBundledAppIcon (see that test for the command).
//

import AppKit
import Combine
import SwiftUI

struct AppIconArt: View {
  let palette: DayframePalette

  /// Proportions from the welcome: ring radius 44 and tile half-width 74 (scene units).
  private static let ringToTile: CGFloat = 44.0 / 74.0
  /// The macOS icon grid: the body is 824 of 1024 points, with a continuous corner.
  private static let bodyToCanvas: CGFloat = 824.0 / 1024.0
  /// The three locks, as in LOCK_ANGLES (screen angles, 0 = right, clockwise).
  private static let lockAngles: [CGFloat] = [-.pi / 2, .pi / 6, 5 * .pi / 6]

  var body: some View {
    Canvas { context, size in
      let colors = Colors(palette)
      let side = min(size.width, size.height) * Self.bodyToCanvas
      let tile = CGRect(
        x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
      let center = CGPoint(x: tile.midX, y: tile.midY)
      let tilePath = Path(roundedRect: tile, cornerRadius: side * 0.225, style: .continuous)

      // The tile: the welcome's deep sky, lit a little from the top, with a faint drop shadow.
      context.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: side * 0.02, y: side * 0.012))
        layer.fill(
          tilePath,
          with: .radialGradient(
            Gradient(colors: [colors.sky[1].lighter(0.06), colors.sky[0], colors.sky[2]]),
            center: CGPoint(x: tile.midX, y: tile.minY + side * 0.38), startRadius: 0,
            endRadius: side * 0.85))
      }
      context.stroke(tilePath, with: .color(colors.glow.opacity(0.38)), lineWidth: side * 0.004)

      // Everything else stays inside the tile, so the corona's glow can't spill past its edge.
      context.clip(to: tilePath)
      let r = side / 2 * Self.ringToTile
      // Corona behind the disc, then the dark disc, then the rim from soft to sharp.
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: center.x - r * 2.1, y: center.y - r * 2.1, width: r * 4.2, height: r * 4.2)),
        with: .radialGradient(
          Gradient(colors: [colors.glow.opacity(0.5), colors.glow.opacity(0.12), .clear]),
          center: center, startRadius: r * 0.9, endRadius: r * 2.1))
      context.fill(circle(center, r * 0.97), with: .color(colors.sky[0]))
      let rim: [(Color, CGFloat, Double)] = [
        (colors.edge, 0.25, 0.16), (colors.glow, 0.114, 0.42), (colors.core, 0.055, 1),
        (.white, 0.025, 0.9),
      ]
      for (color, width, alpha) in rim {
        context.stroke(circle(center, r), with: .color(color.opacity(alpha)), lineWidth: r * width)
      }

      // The three locks, at rest.
      for angle in Self.lockAngles {
        var tick = Path()
        tick.move(
          to: CGPoint(x: center.x + cos(angle) * r * 1.07, y: center.y + sin(angle) * r * 1.07))
        tick.addLine(
          to: CGPoint(x: center.x + cos(angle) * r * 1.25, y: center.y + sin(angle) * r * 1.25))
        context.stroke(
          tick, with: .color(colors.core.opacity(0.75)),
          style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
      }
    }
  }

  private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
    Path(
      ellipseIn: CGRect(
        x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
  }

  /// The welcome's colors (welcomeColors in scene.ts), from the palette's stops.
  private struct Colors {
    let sky: [Color]
    let glow: Color
    let core: Color
    let edge: Color

    init(_ palette: DayframePalette) {
      let s = palette.stops
      let dark = s.dark.map { NSColor(hex: $0) ?? .black }
      let glow = NSColor(hex: s.accentLight) ?? .orange
      let white = NSColor(srgbRed: 1, green: 250 / 255, blue: 244 / 255, alpha: 1)
      sky = [dark[0].scaled(0.3), dark[1].scaled(0.22), dark[2].scaled(0.3)].map {
        Color(nsColor: $0)
      }
      self.glow = Color(nsColor: glow)
      core = Color(nsColor: white.blended(withFraction: 0.22, of: glow) ?? white)
      edge = Color(nsColor: NSColor(hex: s.accent) ?? glow)
    }
  }

  /// The icon as PNG data at a pixel size.
  @MainActor
  static func png(palette: DayframePalette, pixels: CGFloat) -> Data? {
    let renderer = ImageRenderer(
      content: AppIconArt(palette: palette).frame(width: pixels, height: pixels))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
}

extension Color {
  /// Mixed toward white by `amount` (0…1).
  fileprivate func lighter(_ amount: CGFloat) -> Color {
    let base = NSColor(self).usingColorSpace(.sRGB) ?? .black
    return Color(nsColor: base.blended(withFraction: amount, of: .white) ?? base)
  }
}

/// Keeps the Dock icon in the active palette while Dayframe runs.
@MainActor
final class AppIconManager {
  static let shared = AppIconManager()
  private var subscription: AnyCancellable?

  func start() {
    subscription = DayframePaletteStore.shared.$palette
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { palette in
        guard let data = AppIconArt.png(palette: palette, pixels: 512) else { return }
        NSApp.applicationIconImage = NSImage(data: data)
      }
  }
}
