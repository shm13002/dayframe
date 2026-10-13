//
//  StartOfDaySettingsView.swift
//  Dayframe
//
//  Settings › Start of day: the opening animation, the Dayframe wallpaper, your day's
//  apps and how their windows are arranged after you log in.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StartOfDaySettingsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
      OpeningSection()
      WallpaperSection()
      DayAppsSection()
      WindowStyleSection()
    }
  }
}

// MARK: - Opening animation

private struct OpeningSection: View {
  @ObservedObject private var controller = WelcomeController.shared
  @ObservedObject private var loginManager = LaunchAtLoginManager.shared
  @AppStorage(WelcomeController.Keys.enabled) private var enabled = false
  @AppStorage(WelcomeController.Keys.login) private var login = true
  @AppStorage(WelcomeController.Keys.unlock) private var unlock = true
  @AppStorage(WelcomeController.Keys.minAwayMinutes) private var minAwayMinutes = 10
  @AppStorage(WelcomeController.Keys.soundMix) private var soundMix = WelcomeSoundMix.laptop.rawValue

  var body: some View {
    SettingsSection(
      title: "Opening",
      subtitle: "The System Awakening in your Dayframe colors: a spark, an orbit, ignition, then your day."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(label: "Preview", subtitle: "Click or press any key to skip.") {
          HStack(spacing: 8) {
            SettingsSecondaryButton(title: "First launch", systemImage: "play.fill", isDisabled: controller.isPlaying) {
              controller.preview(.firstLaunch)
            }
            SettingsSecondaryButton(title: "Daily wake", systemImage: "play.fill", isDisabled: controller.isPlaying) {
              controller.preview(.dailyWake)
            }
          }
        }
        SettingsRow(
          label: "Play automatically",
          subtitle: controller.previewed || enabled
            ? "After you log in, and when you come back to your Mac."
            : "Preview it once before turning it on."
        ) {
          SettingsToggle(isOn: $enabled)
            .disabled(!controller.previewed && !enabled)
            .onChange(of: enabled) {
              if enabled && login { loginManager.setEnabled(true) }
              controller.applySettings()
            }
        }
        if enabled {
          SettingsRow(
            label: "After login",
            subtitle: "The full five seconds, then Dayframe opens your day. Once per login."
          ) {
            SettingsToggle(isOn: $login)
              .onChange(of: login) {
                if login { loginManager.setEnabled(true) }
                controller.applySettings()
              }
          }
          if login && !loginManager.isEnabled {
            Text("Allow Dayframe in System Settings › General › Login Items so it can open at login.")
              .font(.custom("Figtree", size: 11))
              .foregroundColor(SettingsStyle.secondary)
              .padding(.vertical, 8)
          }
          SettingsRow(
            label: "After unlock",
            subtitle: "A two-second daily wake when you've been away. Replaces the notch's welcome back."
          ) {
            HStack(spacing: 10) {
              Picker("After", selection: $minAwayMinutes) {
                ForEach(WelcomeController.minAwayChoices, id: \.self) { minutes in
                  Text("After \(minutes) min away").tag(minutes)
                }
              }
              .pickerStyle(.menu)
              .labelsHidden()
              .frame(width: 170)
              .disabled(!unlock)
              .onChange(of: minAwayMinutes) { controller.applySettings() }
              SettingsToggle(isOn: $unlock)
                .onChange(of: unlock) { controller.applySettings() }
            }
          }
        }
        SettingsRow(
          label: "Sound",
          subtitle: "Machine wakes, ignition, three locks, then \"online\". Follows your Mac's volume and mute.",
          showsDivider: false
        ) {
          Picker("Sound", selection: $soundMix) {
            ForEach(WelcomeSoundMix.allCases) { mix in
              Text(mix.title).tag(mix.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .frame(width: 150)
        }
        if let message = controller.message {
          Text(message)
            .font(.custom("Figtree", size: 11))
            .foregroundColor(SettingsStyle.secondary)
            .padding(.top, 8)
        }
      }
    }
  }
}

// MARK: - Wallpaper

private struct WallpaperSection: View {
  @ObservedObject private var manager = WallpaperManager.shared
  @ObservedObject private var palette = DayframePaletteStore.shared
  @AppStorage(WallpaperManager.Keys.enabled) private var enabled = false
  @AppStorage(DayflowAppearance.storageKey) private var appearance: DayflowAppearance = .system
  @StateObject private var system = SystemAppearanceObserver()

  var body: some View {
    SettingsSection(
      title: "Wallpaper",
      subtitle: "Your palette's sky over a quiet horizon. It's also what you see behind the password screen. No text, no logo."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 16) {
          WallpaperArt(palette: palette.palette, dark: appearance.colorScheme(system: system.colorScheme) == .dark)
            .frame(width: 192, height: 125)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(SettingsStyle.divider, lineWidth: 1))
          Text("Follows your palette and Light/Dark mode. Turning it off puts your previous wallpaper back.")
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        SettingsRow(label: "Use the Dayframe wallpaper", showsDivider: false) {
          SettingsToggle(isOn: $enabled)
            .onChange(of: enabled) { manager.setEnabled(enabled) }
        }
        if let error = manager.lastError {
          Text("Couldn't set the wallpaper: \(error)")
            .font(.custom("Figtree", size: 11))
            .foregroundColor(SettingsStyle.secondary)
            .padding(.top, 6)
        }
      }
    }
  }
}

// MARK: - Your day's apps

private struct DayAppsSection: View {
  @ObservedObject private var startOfDay = StartOfDay.shared
  @AppStorage(StartOfDay.Keys.enabled) private var enabled = true
  @AppStorage(StartOfDay.Keys.hideOthers) private var hideOthers = true
  @AppStorage(StartOfDay.Keys.dayframeSlot) private var dayframeSlot = WindowSlot.center.rawValue
  @AppStorage(StartOfDay.Keys.windowStyle) private var windowStyle = WindowStyle.layout.rawValue

  private var usesLayout: Bool { windowStyle == WindowStyle.layout.rawValue }

  var body: some View {
    SettingsSection(
      title: "Your day",
      subtitle: "After the login welcome, Dayframe opens on Briefing and sets up the rest."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(label: "Set up my day after login", subtitle: "Runs once, right after the opening animation.") {
          SettingsToggle(isOn: $enabled)
        }
        SettingsRow(label: "Hide other apps", subtitle: "Apps that reopened at login are hidden, not quit. Click their Dock icon to bring them back.") {
          SettingsToggle(isOn: $hideOthers)
        }
        if usesLayout {
          SettingsRow(label: "Dayframe window") {
            slotPicker(selection: $dayframeSlot)
          }
        }

        Text("Apps to open")
          .font(.custom("Figtree", size: 13))
          .fontWeight(.semibold)
          .foregroundColor(SettingsStyle.text)
          .padding(.top, 14)
          .padding(.bottom, 6)

        if startOfDay.apps.isEmpty {
          Text("None yet. Add the apps you use every day.")
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.secondary)
            .padding(.vertical, 6)
        }
        ForEach($startOfDay.apps) { $app in
          HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
              .resizable()
              .frame(width: 22, height: 22)
            Text(app.name)
              .font(.custom("Figtree", size: 13))
              .foregroundColor(SettingsStyle.text)
            Spacer()
            if usesLayout {
              Picker("Place", selection: $app.slot) {
                ForEach(WindowSlot.allCases) { Text($0.title).tag($0) }
              }
              .pickerStyle(.menu)
              .labelsHidden()
              .frame(width: 160)
            }
            Button {
              startOfDay.apps.removeAll { $0.id == app.id }
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(SettingsStyle.secondary)
            .help("Remove")
          }
          .padding(.vertical, 5)
        }

        HStack(spacing: 8) {
          SettingsSecondaryButton(title: "Add app…", systemImage: "plus") { pickApps() }
          SettingsSecondaryButton(title: "Run now", systemImage: "sunrise", isDisabled: startOfDay.isRunning) {
            startOfDay.run(reason: "settings", force: true)
          }
        }
        .padding(.top, 10)

        if let lastRun = startOfDay.lastRun {
          Text(lastRun)
            .font(.custom("Figtree", size: 11))
            .foregroundColor(SettingsStyle.secondary)
            .padding(.top, 6)
        }
        Text("Tip: in System Settings, uncheck \"Reopen windows when logging back in\" on the Shut Down dialog for the cleanest start.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(SettingsStyle.meta)
          .padding(.top, 10)
      }
    }
  }

  private func slotPicker(selection: Binding<String>) -> some View {
    Picker("Place", selection: selection) {
      ForEach(WindowSlot.allCases) { Text($0.title).tag($0.rawValue) }
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .frame(width: 160)
  }

  private func pickApps() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.prompt = "Add"
    guard panel.runModal() == .OK else { return }
    for url in panel.urls { startOfDay.add(appAt: url) }
  }
}

// MARK: - Window style

private struct WindowStyleSection: View {
  @AppStorage(StartOfDay.Keys.windowStyle) private var windowStyle = WindowStyle.layout.rawValue
  @State private var trusted = StartOfDay.accessibilityTrusted
  private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var body: some View {
    SettingsSection(
      title: "Window style",
      subtitle: "Layout puts each window in its place. Stage Manager lets macOS keep recent apps at the side."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(label: "Style") {
          Picker("Style", selection: $windowStyle) {
            ForEach(WindowStyle.allCases) { Text($0.title).tag($0.rawValue) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 220)
        }
        if windowStyle == WindowStyle.layout.rawValue {
          SettingsRow(
            label: "Accessibility",
            subtitle: trusted
              ? "Allowed. Dayframe can move your apps' windows."
              : "Needed to move other apps' windows. You allow it in System Settings › Privacy & Security › Accessibility.",
            showsDivider: false
          ) {
            if trusted {
              SettingsStatusDot(state: .good, label: "Allowed")
            } else {
              SettingsSecondaryButton(title: "Allow…", systemImage: "lock.open") {
                StartOfDay.requestAccessibility()
              }
            }
          }
        } else {
          SettingsRow(
            label: "Stage Manager",
            subtitle: "Turn it on in Desktop & Dock, with \"Recent applications\" shown. macOS picks which apps appear at the side.",
            showsDivider: false
          ) {
            SettingsSecondaryButton(title: "Open settings", systemImage: "arrow.up.right") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
            }
          }
        }
      }
    }
    .onReceive(poll) { _ in trusted = StartOfDay.accessibilityTrusted }
  }
}
