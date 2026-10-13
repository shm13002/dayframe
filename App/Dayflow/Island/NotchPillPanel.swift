//
//  NotchPillPanel.swift
//  Dayframe
//
//  The always-on window around the notch that hosts NotchPillView. It is resized
//  to fit the pill's current mode (rest, hover, open): immediately when growing,
//  and after the collapse animation when shrinking, so nothing gets clipped.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPillPanel {
  let model: NotchPillModel
  private let panel: NSPanel
  private var observers: Set<AnyCancellable> = []
  private var shrinkWork: DispatchWorkItem?

  var windowNumber: Int { panel.windowNumber }
  var isVisible: Bool { panel.isVisible }

  init(model: NotchPillModel) {
    self.model = model
    panel = NSPanel(
      contentRect: model.geometry.pillWindowFrame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
    ]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.becomesKeyOnlyIfNeeded = true

    let root = NotchPillView(model: model)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    let host = FirstMouseHostingView(rootView: root)
    host.sizingOptions = []
    panel.contentView = host

    model.$mode.combineLatest(model.$isDripping)
      .removeDuplicates { $0 == $1 }
      .sink { [weak self] _ in self?.resizeForCurrentMode() }
      .store(in: &observers)
  }

  func show(fadeIn: Bool) {
    resizeForCurrentMode(immediately: true)
    if panel.isVisible { return }
    panel.alphaValue = fadeIn ? 0 : 1
    panel.orderFrontRegardless()
    IslandCaptureExclusion.register(panel.windowNumber)
    if fadeIn {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        panel.animator().alphaValue = 1
      }
    }
  }

  func hide() {
    model.setMode(.rest)
    panel.orderOut(nil)
  }

  /// The notch moved (display change): re-anchor.
  func update(geometry: NotchGeometry) {
    model.geometry = geometry
    resizeForCurrentMode(immediately: true)
  }

  private func frame(for size: CGSize) -> CGRect {
    let g = model.geometry
    let pill = g.pillRect
    return CGRect(
      x: g.screenFrame.minX + pill.midX - size.width / 2,
      y: g.screenFrame.maxY - size.height,
      width: size.width,
      height: size.height)
  }

  private func resizeForCurrentMode(immediately: Bool = false) {
    shrinkWork?.cancel()
    let target = frame(for: model.contentSize(for: model.mode))
    let current = panel.frame
    let shrinking = target.width < current.width || target.height < current.height
    if shrinking && !immediately && panel.isVisible {
      // Grow now if any dimension increases, shrink after the spring has settled.
      let union = target.union(current)
      if union != current { panel.setFrame(union, display: true) }
      let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(target, display: true) }
      shrinkWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    } else {
      panel.setFrame(target, display: true)
    }
  }
}

/// Lets the first click on the pill act immediately instead of only focusing the panel.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
