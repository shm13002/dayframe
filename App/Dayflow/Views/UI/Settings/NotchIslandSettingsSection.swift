//
//  NotchIslandSettingsSection.swift
//  Dayframe
//
//  Settings › Other › Notch island: the pill, the startup show, its sounds and moments.
//

import SwiftUI

struct NotchIslandSettingsSection: View {
  @AppStorage(IslandController.Keys.enabled) private var enabled = true
  @AppStorage(IslandController.Keys.startupEnabled) private var startupEnabled = true
  @AppStorage(IslandController.Keys.minAwayMinutes) private var minAwayMinutes = 10
  @AppStorage(IslandController.Keys.displayName) private var displayName = ""
  @AppStorage(IslandSound.enabledKey) private var soundEnabled = true
  @AppStorage(IslandSound.volumeKey) private var soundVolume = 0.8
  @AppStorage(IslandController.Keys.momentCardBorn) private var momentCardBorn = true
  @AppStorage(IslandController.Keys.momentGoal) private var momentGoal = true
  @AppStorage(IslandController.Keys.momentRecording) private var momentRecording = true
  @AppStorage(IslandController.Keys.momentRecap) private var momentRecap = true

  var body: some View {
    SettingsSection(
      title: "Notch island",
      subtitle:
        "A small pill beside the notch with today's focus and time. Its eyes close while recording is paused."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(
          label: "Show the notch island", subtitle: "Hidden from Jarvis's own recordings."
        ) {
          SettingsToggle(isOn: $enabled)
            .onChange(of: enabled) { IslandController.shared.applySettings() }
        }

        if enabled {
          SettingsRow(
            label: "Welcome back",
            subtitle:
              "Plays when you unlock after time away: your greeting, where you left off and what's next."
          ) {
            HStack(spacing: 10) {
              Picker("After", selection: $minAwayMinutes) {
                ForEach(IslandController.minAwayChoices, id: \.self) { minutes in
                  Text("After \(minutes) min away").tag(minutes)
                }
              }
              .pickerStyle(.menu)
              .labelsHidden()
              .frame(width: 170)
              .disabled(!startupEnabled)
              SettingsToggle(isOn: $startupEnabled)
            }
          }

          SettingsRow(
            label: "Your name",
            subtitle: "Used in the greeting. Leave empty to use your Mac account name."
          ) {
            TextField(IslandController.shared.displayName, text: $displayName)
              .textFieldStyle(.roundedBorder)
              .frame(width: 170)
          }

          SettingsRow(
            label: "Sounds",
            subtitle: "Short, soft chimes made on this Mac. They follow your Mac's volume."
          ) {
            HStack(spacing: 10) {
              Slider(value: $soundVolume, in: 0...1)
                .frame(width: 120)
                .disabled(!soundEnabled)
                .accessibilityLabel("Sound volume")
              SettingsToggle(isOn: $soundEnabled)
            }
          }

          SettingsRow(
            label: "When a new card arrives", subtitle: "A drip from the notch and a blink."
          ) {
            SettingsToggle(isOn: $momentCardBorn)
          }
          SettingsRow(
            label: "When you reach your focus goal", subtitle: "A short celebration, once a day."
          ) {
            SettingsToggle(isOn: $momentGoal)
          }
          SettingsRow(
            label: "When recording pauses or resumes",
            subtitle: "A soft sound as the eyes close or open."
          ) {
            SettingsToggle(isOn: $momentRecording)
          }
          SettingsRow(
            label: "When your daily recap is ready",
            subtitle: "Each category streams into its own ring."
          ) {
            SettingsToggle(isOn: $momentRecap)
          }

          SettingsRow(
            label: "Preview", subtitle: "Play the welcome back show now.", showsDivider: false
          ) {
            SettingsSecondaryButton(title: "Play now", systemImage: "play.fill") {
              IslandController.shared.playStartup(force: true)
            }
          }
        }
      }
    }
  }
}
