//
//  HermesBackend.swift
//  Jarvis
//
//  Starts and watches the Hermes Agent backend Jarvis talks to: `hermes serve` on 127.0.0.1
//  with a random port and a per-launch session token. A Swift port of Herald OS's
//  electron/backend (resolve.ts, manager.ts, ready.ts; MIT, Luke The Dev).
//
//  The bridge plugin (system tools) only serves sessions when the backend runs with HERALD_OS=1
//  and the session's source is "herald_os", so both stay set here and in the Jarvis page.
//

import Foundation
import os.log

/// Where Hermes is installed, and how to run it. Pure, so the ladder is unit-tested.
enum HermesLocator {
  struct Launch: Equatable {
    /// The executable, then its leading arguments (`-m hermes_cli.main` for the old layout).
    var command: [String]
    /// The checkout, used as the working directory; nil for a `hermes` found on PATH.
    var root: String?
    var label: String
  }

  /// The ladder Herald uses: an explicit root, the managed install in $HERMES_HOME, then PATH.
  static func locate(
    environment: [String: String],
    home: String,
    isFile: (String) -> Bool,
    isExecutable: (String) -> Bool
  ) -> Launch? {
    if let root = environment["JARVIS_HERMES_ROOT"] ?? environment["HERALD_OS_HERMES_ROOT"],
      !root.isEmpty,
      let launch = checkout(root, label: "override", isFile: isFile, isExecutable: isExecutable)
    {
      return launch
    }
    let managedRoot = hermesHome(environment: environment, home: home) + "/hermes-agent"
    if let launch = checkout(
      managedRoot, label: "managed install", isFile: isFile, isExecutable: isExecutable)
    {
      return launch
    }
    let pathDirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
    for dir in pathDirs + [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
      let candidate = dir + "/hermes"
      if isExecutable(candidate) {
        return Launch(command: [candidate], root: nil, label: "hermes on PATH (\(candidate))")
      }
    }
    return nil
  }

  static func hermesHome(environment: [String: String], home: String) -> String {
    if let custom = environment["HERMES_HOME"], !custom.isEmpty { return custom }
    return home + "/.hermes"
  }

  /// A checkout counts only with the `serve` subcommand and one of the two install layouts.
  private static func checkout(
    _ root: String, label: String, isFile: (String) -> Bool, isExecutable: (String) -> Bool
  ) -> Launch? {
    guard isFile(root + "/hermes_cli/subcommands/dashboard.py") else { return nil }
    let launcher = root + "/.hermes/bin/hermes"
    if isExecutable(launcher) { return Launch(command: [launcher], root: root, label: label) }
    let python = root + "/venv/bin/python"
    if isExecutable(python) {
      return Launch(command: [python, "-m", "hermes_cli.main"], root: root, label: label)
    }
    return nil
  }
}

/// The line `hermes serve` prints once it listens: `HERMES_BACKEND_READY port=8123`.
enum HermesReadyLine {
  static func port(in line: String) -> Int? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["HERMES_BACKEND_READY port=", "HERMES_DASHBOARD_READY port="]
    where trimmed.hasPrefix(prefix) {
      guard let port = Int(trimmed.dropFirst(prefix.count)), (1..<65536).contains(port) else {
        return nil
      }
      return port
    }
    return nil
  }
}

/// Restarts after an unexpected exit: 1, 3, 7, then 15 s, then give up until asked again.
enum HermesRestartPolicy {
  static let delays: [Duration] = [.seconds(1), .seconds(3), .seconds(7), .seconds(15)]

  static func delay(afterFailures failures: Int) -> Duration? {
    failures < delays.count ? delays[failures] : nil
  }
}

/// Splits a byte stream into lines, keeping the unfinished tail.
struct LineBuffer {
  private var rest = ""

  mutating func push(_ chunk: String) -> [String] {
    rest += chunk
    var parts = rest.components(separatedBy: "\n")
    rest = parts.removeLast()
    return parts.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
  }
}

/// The pipe's handler runs on one background queue at a time, so a lock-free box is enough.
private final class LineBufferBox: @unchecked Sendable {
  private var buffer = LineBuffer()
  func push(_ chunk: String) -> [String] { buffer.push(chunk) }
}

@MainActor
final class HermesBackend: ObservableObject {
  static let shared = HermesBackend()

  enum Phase: Equatable {
    case idle
    case notInstalled
    case starting
    case ready(port: Int)
    case failed(String)
  }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var launchLabel: String?

  /// Sent as HERMES_DASHBOARD_SESSION_TOKEN; REST calls and the WebSocket must carry it.
  let token: String = HermesBackend.makeToken()

  private let logger = Logger(subsystem: "local.dayframe.app", category: "jarvis")
  private var process: Process?
  private var failures = 0
  private var stopping = false
  private var readyTimeout: Task<Void, Never>?

  private init() {}

  var port: Int? {
    if case .ready(let port) = phase { return port }
    return nil
  }

  var baseURL: URL? { port.map { URL(string: "http://127.0.0.1:\($0)")! } }

  /// Starts the backend if it isn't running. Safe to call repeatedly.
  func start() {
    guard process == nil else { return }
    stopping = false
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let environment = ProcessInfo.processInfo.environment
    guard
      let launch = HermesLocator.locate(
        environment: environment, home: home,
        isFile: { FileManager.default.fileExists(atPath: $0) },
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    else {
      logger.info("Hermes is not installed; Jarvis waits for it")
      phase = .notInstalled
      return
    }
    launchLabel = launch.label
    phase = .starting
    let hermesHome = HermesLocator.hermesHome(environment: environment, home: home)
    Task.detached { [token] in
      let path = Self.loginShellPath()
      await MainActor.run {
        self.spawn(launch, hermesHome: hermesHome, home: home, path: path, token: token)
      }
    }
  }

  /// Stops the backend this app started (SIGTERM, then SIGKILL after 4 s).
  func stop() {
    stopping = true
    readyTimeout?.cancel()
    guard let process, process.isRunning else {
      self.process = nil
      return
    }
    logger.info("stopping Hermes (pid \(process.processIdentifier))")
    process.terminate()
    let pid = process.processIdentifier
    DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
      if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }
    self.process = nil
    phase = .idle
  }

  /// Asked again after giving up (Settings › Jarvis › Restart).
  func restart() {
    stop()
    failures = 0
    start()
  }

  private func spawn(
    _ launch: HermesLocator.Launch, hermesHome: String, home: String, path: String, token: String
  ) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launch.command[0])
    process.arguments =
      Array(launch.command.dropFirst()) + ["serve", "--host", "127.0.0.1", "--port", "0"]
    process.currentDirectoryURL = URL(fileURLWithPath: launch.root ?? home)

    var env = ProcessInfo.processInfo.environment.filter { key, _ in
      !key.hasPrefix("HERMES_SESSION_") && key != "HERMES_PARENT_START_MARKER"
        && key != "HERMES_PARENT_START_NONCE" && key != "HERMES_SPAWN"
    }
    env["HERMES_DASHBOARD_SESSION_TOKEN"] = token
    env["HERMES_HOME"] = hermesHome
    env["HERMES_DESKTOP"] = "1"
    env["HERALD_OS"] = "1"
    env["HERMES_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
    env["PYTHONUNBUFFERED"] = "1"
    env["TERMINAL_CWD"] = home
    env["PATH"] = path
    process.environment = env

    let out = Pipe()
    process.standardOutput = out
    process.standardError = out
    process.standardInput = FileHandle.nullDevice
    let lines = LineBufferBox()
    out.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      for line in lines.push(String(decoding: data, as: UTF8.self)) {
        if line.contains("Traceback") || line.contains("ERROR") {
          Logger(subsystem: "local.dayframe.app", category: "jarvis").error(
            "hermes: \(line, privacy: .public)")
        }
        if let port = HermesReadyLine.port(in: line) {
          Task { @MainActor in await self?.becameReady(port: port) }
        }
      }
    }
    process.terminationHandler = { [weak self] ended in
      let status = ended.terminationStatus
      Task { @MainActor in self?.exited(ended, status: status) }
    }

    do {
      try process.run()
    } catch {
      logger.error("Hermes failed to launch: \(error.localizedDescription, privacy: .public)")
      phase = .failed(error.localizedDescription)
      return
    }
    self.process = process
    logger.info(
      "Hermes started (\(launch.label, privacy: .public), pid \(process.processIdentifier))")
    readyTimeout?.cancel()
    readyTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(90))
      guard !Task.isCancelled, let self, self.phase == .starting else { return }
      self.logger.error("Hermes didn't report ready within 90 s")
      self.process?.terminate()
    }
  }

  private func becameReady(port: Int) async {
    readyTimeout?.cancel()
    let healthy = await Self.probe(port: port, token: token)
    guard process != nil else { return }
    if healthy {
      failures = 0
      phase = .ready(port: port)
      logger.info("Hermes ready on port \(port)")
    } else {
      logger.error("Hermes said ready on \(port) but /api/status never answered")
      process?.terminate()
    }
  }

  private func exited(_ ended: Process, status: Int32) {
    guard ended === process || process == nil else { return }
    process = nil
    readyTimeout?.cancel()
    guard !stopping else { return }
    logger.error("Hermes exited with status \(status)")
    guard let delay = HermesRestartPolicy.delay(afterFailures: failures) else {
      phase = .failed("Hermes stopped \(failures) times in a row (status \(status)).")
      return
    }
    failures += 1
    phase = .starting
    Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard let self, !self.stopping else { return }
      self.start()
    }
  }

  /// Polls GET /api/status for up to 60 s.
  private static func probe(port: Int, token: String) async -> Bool {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/status")!)
    request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
    request.timeoutInterval = 3
    for _ in 0..<120 {
      if let response = try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse,
        response.statusCode == 200
      {
        return true
      }
      try? await Task.sleep(for: .milliseconds(500))
    }
    return false
  }

  /// A GUI app inherits a bare PATH; Hermes's tools need the user's (Homebrew, ~/.local/bin).
  nonisolated private static func loginShellPath() -> String {
    let result = LoginShellRunner.run("printf '%s' \"$PATH\"", timeout: 10)
    let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.exitCode == 0 && !path.isEmpty
      ? path : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  }

  private static func makeToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
