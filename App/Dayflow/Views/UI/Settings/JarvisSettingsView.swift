//
//  JarvisSettingsView.swift
//  Jarvis
//
//  Settings › Jarvis: the Hermes backend, the brain new conversations start with, the voice,
//  ⌥Space, and what Jarvis did on this Mac (the system tools' audit log).
//

import AppKit
import SwiftUI

struct JarvisSettingsView: View {
  @ObservedObject private var backend = HermesBackend.shared
  @ObservedObject private var coordinator = JarvisCoordinator.shared
  @ObservedObject private var voice = JarvisVoice.shared
  @AppStorage(JarvisVoice.Keys.enabled) private var voiceEnabled = true
  @AppStorage(JarvisCoordinator.Keys.brain) private var brain = "grok"
  @State private var audit: [JarvisAuditEntry] = []

  private static let brains: [(id: String, label: String, signIn: String)] = [
    ("grok", "Grok", "hermes auth add xai-oauth (needs SuperGrok or X Premium+)"),
    ("chatgpt", "ChatGPT", "hermes auth add openai-codex"),
    ("claude", "Claude", "hermes auth add anthropic --type oauth"),
    ("qwen", "Qwen (offline)", "hermes model → Custom endpoint → http://localhost:11434/v1"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      SettingsSection(
        title: "Hermes",
        subtitle:
          "Jarvis thinks and acts through Hermes Agent (Nous Research, open source), which runs on this Mac only while Jarvis is open."
      ) {
        VStack(alignment: .leading, spacing: 0) {
          SettingsRow(label: "Status", subtitle: backend.launchLabel) {
            HStack(spacing: 10) {
              Text(statusText)
                .font(.custom("Figtree", size: 13))
                .foregroundStyle(.secondary)
              SettingsSecondaryButton(title: "Restart", systemImage: "arrow.clockwise") {
                backend.restart()
              }
            }
          }
          SettingsRow(
            label: "Shortcut",
            subtitle: coordinator.hotKeyAvailable
              ? "⌥Space talks to Jarvis from any app. Press again to stop early."
              : "⌥Space belongs to another app (often ChatGPT). Use the mic button in Jarvis, or free the shortcut there.",
            showsDivider: false
          ) {
            Text(coordinator.hotKeyAvailable ? "⌥Space" : "Taken")
              .font(.custom("Figtree", size: 13).weight(.semibold))
          }
        }
      }

      SettingsSection(
        title: "Brain",
        subtitle:
          "The model new conversations start with. Grok is the quick default; Qwen is the offline fallback with a small memory, so tools may not work on it."
      ) {
        VStack(alignment: .leading, spacing: 0) {
          SettingsRow(label: "Default brain", subtitle: signInHint) {
            Picker("Brain", selection: $brain) {
              ForEach(Self.brains, id: \.id) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
            .onChange(of: brain) { _, _ in coordinator.pushContext() }
          }
        }
      }

      SettingsSection(
        title: "Voice",
        subtitle:
          "Spoken answers use your Jarvis voice (the voice server in ~/jarvis-voice). If it isn't running, the Mac's own voice reads them."
      ) {
        VStack(alignment: .leading, spacing: 0) {
          SettingsRow(label: "Speak answers to voice requests", subtitle: voiceSourceText) {
            HStack(spacing: 10) {
              SettingsSecondaryButton(title: "Test", systemImage: "speaker.wave.2") {
                voice.speak("Good \(Self.partOfDay), Shahzeb. Jarvis is online and ready.")
              }
              .disabled(!voiceEnabled)
              SettingsToggle(isOn: $voiceEnabled)
            }
          }
        }
      }

      SettingsSection(
        title: "What Jarvis did",
        subtitle:
          "Every system action is logged. Reading runs straight away; changing something asks you first; deleting or stopping things asks every time. Keychains, SSH keys and system folders are always off limits."
      ) {
        VStack(alignment: .leading, spacing: 8) {
          if audit.isEmpty {
            Text("Nothing yet.")
              .font(.custom("Figtree", size: 13))
              .foregroundStyle(.secondary)
          }
          ForEach(audit) { entry in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(entry.time)
                .font(.custom("Figtree", size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
              Text(entry.line)
                .font(.custom("Figtree", size: 13))
                .lineLimit(2)
              Spacer(minLength: 0)
              Text(entry.decision)
                .font(.custom("Figtree", size: 12).weight(.semibold))
                .foregroundStyle(entry.ok ? Color.secondary : Color.red)
            }
          }
          HStack(spacing: 10) {
            SettingsLinkButton(title: "Open the log folder") {
              NSWorkspace.shared.open(JarvisAuditEntry.folder)
            }
            SettingsLinkButton(title: "Refresh", systemImage: "arrow.clockwise") {
              audit = JarvisAuditEntry.recent()
            }
          }
          .padding(.top, 6)
        }
      }
    }
    .task { audit = JarvisAuditEntry.recent() }
  }

  private var statusText: String {
    switch backend.phase {
    case .idle: return "Not started"
    case .notInstalled: return "Not installed"
    case .starting: return "Starting…"
    case .ready(let port): return "Running (port \(port))"
    case .failed: return "Stopped"
    }
  }

  private var signInHint: String {
    let entry = Self.brains.first { $0.id == brain } ?? Self.brains[0]
    return "Sign in once in Terminal: \(entry.signIn)"
  }

  private var voiceSourceText: String {
    switch voice.lastSource {
    case .jarvisVoice: return "Last answer: the Jarvis voice."
    case .systemVoice:
      return "Last answer: the Mac's voice (the Jarvis voice server didn't answer)."
    case nil: return "Answers to typed questions stay silent."
    }
  }

  private static var partOfDay: String {
    let hour = Calendar.current.component(.hour, from: Date())
    return hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
  }
}

/// One line of ~/.hermes/herald-os/audit.jsonl (written by the bridge plugin).
struct JarvisAuditEntry: Identifiable, Equatable {
  let id: Int
  let time: String
  let line: String
  let decision: String
  let ok: Bool

  static let folder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".hermes/herald-os", isDirectory: true)

  static func recent(limit: Int = 12) -> [JarvisAuditEntry] {
    guard
      let text = try? String(
        contentsOf: folder.appendingPathComponent("audit.jsonl"), encoding: .utf8)
    else { return [] }
    return parse(text, limit: limit)
  }

  /// Newest first. Pure, unit-tested.
  static func parse(_ text: String, limit: Int) -> [JarvisAuditEntry] {
    let lines = text.split(whereSeparator: \.isNewline).suffix(limit).reversed()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plainISO = ISO8601DateFormatter()
    let display = DateFormatter()
    display.dateFormat = "MMM d HH:mm"
    return lines.enumerated().compactMap { index, raw in
      guard let data = raw.data(using: .utf8),
        let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return nil }
      let tool = row["tool"] as? String ?? "tool"
      let summary = row["summary"] as? String ?? (row["action"] as? String ?? "")
      var time = ""
      if let ts = row["ts"] as? String, let date = iso.date(from: ts) ?? plainISO.date(from: ts) {
        time = display.string(from: date)
      } else if let ts = row["ts"] as? Double {
        time = display.string(from: Date(timeIntervalSince1970: ts))
      }
      return JarvisAuditEntry(
        id: index, time: time, line: summary.isEmpty ? tool : "\(tool): \(summary)",
        decision: row["decision"] as? String ?? "", ok: row["ok"] as? Bool ?? true)
    }
  }
}
