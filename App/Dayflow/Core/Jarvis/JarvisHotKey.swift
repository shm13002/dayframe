//
//  JarvisHotKey.swift
//  Jarvis
//
//  ⌥Space from any app: talk to Jarvis. A Carbon hot key, which needs no Accessibility
//  permission. If another app already owns ⌥Space (the ChatGPT app does by default),
//  registration fails, that is logged, and the mic button in the Jarvis tab still works.
//

import Carbon.HIToolbox
import Foundation
import os.log

final class JarvisHotKey {
  static let shared = JarvisHotKey()

  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var action: (() -> Void)?
  private let logger = Logger(subsystem: "local.dayframe.app", category: "jarvis")

  /// Registers ⌥Space. Returns false when another app has it.
  @discardableResult
  func register(_ action: @escaping () -> Void) -> Bool {
    unregister()
    self.action = action
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        let me = Unmanaged<JarvisHotKey>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async { me.action?() }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    let id = EventHotKeyID(signature: OSType(0x4A52_5653), id: 1)  // "JRVS"
    let status = RegisterEventHotKey(
      UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    if status != noErr {
      logger.error(
        "⌥Space is taken by another app (status \(status)); use the mic button in Jarvis")
      return false
    }
    logger.info("⌥Space talks to Jarvis")
    return true
  }

  func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
    hotKey = nil
    handler = nil
  }
}
