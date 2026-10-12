// BriefingCompanion: an anticipatory, Clicky-style helper for macOS. Local only: it talks to the Briefing
// service on 127.0.0.1 (Ollama underneath). No keys, no cloud.
//
// What it does
//   • Watches behavioural signals only (dwell, scroll reversals, re-reads, switches to search/AI tools, idle-but-present,
//     typing *rate*, never keystroke contents) and asks the local service whether you look stuck.
//   • Only then reads the focused window's text via Accessibility (fallback: on-device Vision OCR of that window),
//     and the service predicts 1–3 questions you're about to ask, tuned to the activity mode (study, coding, writing…).
//   • Shows a small glowing orb that trails your cursor and gently pulses when it has a guess. No popups.
//     Hover it or hold ⌃⌥ to open a frosted card: question chips, an input prefilled with ghost text (Tab accepts),
//     push-to-talk (on-device speech), streamed answers (hint ladder when studying), and an animated pointer.
//   • Reports which guess you chose/edited/ignored so the service learns your question style per mode and app.
//
// Build: swiftc -O Companion.swift -o BriefingCompanion -framework Cocoa -framework Vision \
//          -framework ScreenCaptureKit -framework Speech -framework AVFoundation
// Permissions: Accessibility (window text, ⌃⌥ hold), Screen Recording (OCR fallback, optional), Speech + Mic (optional).
import Cocoa
import Vision
import ScreenCaptureKit
import Speech
import AVFoundation

let apiBase = URL(string: "http://127.0.0.1:\(ProcessInfo.processInfo.environment["BRIEFING_PORT"] ?? "8765")")!
let reduceMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

// MARK: - API models
struct Question: Codable { let text: String; let kind: String?; let anchor: String? }
struct Anticipation: Codable {
    let stuck: Bool?; let need_text: Bool?; let ocr_allowed: Bool?; let id: String?
    let mode: String?; let subject: String?; let score: Double?; let reasons: [String]?
    let questions: [Question]?; let best: String?; let answer_mode: String?; let pointer: Bool?; let gated: String?
}
struct AnswerEvent: Codable {
    let start: Bool?; let delta: String?; let anchor: String?; let done: Bool?; let more: Bool?; let level: Int?; let error: String?
}
struct TextItem { let text: String; let rect: CGRect }   // rect in global, top-left-origin coordinates

enum API {
    static func post(_ path: String, _ body: [String: Any]) async -> Data? {
        var r = URLRequest(url: apiBase.appendingPathComponent(path))
        r.httpMethod = "POST"; r.timeoutInterval = 180
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try? await URLSession.shared.data(for: r).0
    }
    static func stream(_ path: String, _ body: [String: Any], onEvent: @escaping (AnswerEvent) -> Void) async {
        var r = URLRequest(url: apiBase.appendingPathComponent(path))
        r.httpMethod = "POST"; r.timeoutInterval = 300
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (bytes, _) = try? await URLSession.shared.bytes(for: r) else {
            onEvent(AnswerEvent(start: nil, delta: nil, anchor: nil, done: true, more: false, level: nil, error: "Briefing service not reachable"))
            return
        }
        do {
            for try await line in bytes.lines {
                if let d = line.data(using: .utf8), let ev = try? JSONDecoder().decode(AnswerEvent.self, from: d) { onEvent(ev) }
            }
        } catch {}
    }
}

// MARK: - Behavioural signals (counters only)
final class SignalTracker {
    var app = "", title = "", url = "", pid: pid_t = 0
    var windowSince = Date(), taskSince = Date()
    var scrollReversals = 0, rereads = 0, keyCount = 0
    var lastScrollSign = 0, scrollRun: CGFloat = 0, maxDownRun: CGFloat = 0
    var searchSwitches: [Date] = []
    var keyWindowStart = Date()
    let searchWords = ["google", "chatgpt", "claude", "perplexity", "stack overflow", "bing", "duckduckgo", "gemini", "grok", "phind", "kagi"]
    let aiApps = ["ChatGPT", "Claude", "Perplexity", "Raycast"]

    func onScroll(_ e: NSEvent) {
        let dy = e.scrollingDeltaY
        guard abs(dy) > 0.5 else { return }
        let sign = dy > 0 ? 1 : -1
        if sign != lastScrollSign && lastScrollSign != 0 {
            scrollReversals += 1
            if sign > 0 && scrollRun < -120 { rereads += 1 }      // scrolled down a lot, now going back up = re-reading
            maxDownRun = min(maxDownRun, scrollRun); scrollRun = 0
        }
        lastScrollSign = sign; scrollRun += dy
    }
    func onKey() { keyCount += 1 }

    func refreshFront() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let newApp = front.localizedName ?? ""
        let newTitle = AXReader.focusedWindowTitle(pid: front.processIdentifier) ?? ""
        if newApp != app || newTitle != title {
            let t = newTitle.lowercased()
            if aiApps.contains(newApp) || searchWords.contains(where: { t.contains($0) }) { searchSwitches.append(Date()) }
            // a different document/page resets dwell; coming back to the same task keeps the task clock
            let sameTask = newApp == app && commonPrefixRatio(newTitle, title) > 0.6
            app = newApp; title = newTitle; pid = front.processIdentifier; windowSince = Date()
            scrollReversals = 0; rereads = 0; scrollRun = 0; lastScrollSign = 0
            if !sameTask && !(aiApps.contains(newApp) || searchWords.contains(where: { t.contains($0) })) { taskSince = Date() }
            url = BrowserURL.current(app: newApp) ?? ""
        }
        searchSwitches.removeAll { Date().timeIntervalSince($0) > 300 }
    }

    func commonPrefixRatio(_ a: String, _ b: String) -> Double {
        let n = zip(a, b).prefix { $0 == $1 }.count
        return Double(n) / Double(max(1, max(a.count, b.count)))
    }

    func idleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    func snapshot() -> [String: Any] {
        let mins = max(Date().timeIntervalSince(keyWindowStart) / 60, 0.5)
        let cpm = Double(keyCount) / mins
        if mins > 3 { keyCount = 0; keyWindowStart = Date() }
        let idle = idleSeconds()
        return ["app": app, "window_title": title, "url": url,
                "dwell_s": Date().timeIntervalSince(windowSince), "time_on_task_s": Date().timeIntervalSince(taskSince),
                "scroll_reversals": scrollReversals, "rereads": rereads, "search_switches": searchSwitches.count,
                "idle_s": idle, "present": idle < 300 && !ScreenState.locked, "typing_cpm": cpm]
    }
}

enum ScreenState { static var locked = false }

enum BrowserURL {
    // Only for browsers, only when the window changes. macOS asks once for Automation permission.
    static func current(app: String) -> String? {
        let scripts = ["Safari": "tell application \"Safari\" to return URL of front document",
                       "Google Chrome": "tell application \"Google Chrome\" to return URL of active tab of front window",
                       "Arc": "tell application \"Arc\" to return URL of active tab of front window",
                       "Brave Browser": "tell application \"Brave Browser\" to return URL of active tab of front window"]
        guard let src = scripts[app], let s = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        return s.executeAndReturnError(&err).stringValue
    }
}

// MARK: - Reading the screen (Accessibility first, Vision OCR fallback). All on-device.
enum AXReader {
    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let w = attr(app, kAXFocusedWindowAttribute as String), CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }
    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted(), let w = focusedWindow(pid: pid) else { return nil }
        return attr(w, kAXTitleAttribute as String) as? String
    }
    static func frame(_ el: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = attr(el, kAXPositionAttribute as String), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = attr(el, kAXSizeAttribute as String), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }
    /// Breadth-first walk of the focused window, collecting visible strings with their frames.
    static func visibleText(pid: pid_t, maxChars: Int = 6000) -> [TextItem] {
        guard AXIsProcessTrusted(), let root = focusedWindow(pid: pid) else { return [] }
        var out: [TextItem] = [], queue: [(AXUIElement, Int)] = [(root, 0)], total = 0, visited = 0
        while !queue.isEmpty && total < maxChars && visited < 4000 {
            let (el, depth) = queue.removeFirst(); visited += 1
            for key in [kAXValueAttribute as String, kAXTitleAttribute as String, kAXDescriptionAttribute as String] {
                if let s = attr(el, key) as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count > 1 && !(out.last?.text == t) { out.append(TextItem(text: String(t.prefix(1500)), rect: frame(el))); total += t.count }
                }
            }
            if depth < 14, let kids = attr(el, kAXChildrenAttribute as String) as? [AXUIElement] {
                queue.append(contentsOf: kids.prefix(200).map { ($0, depth + 1) })
            }
        }
        return out
    }
}

enum OCR {
    @available(macOS 14.0, *)
    static func window(pid: pid_t) async -> ([TextItem], CGImage?) {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let win = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.isOnScreen })
        else { return ([], nil) }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let conf = SCStreamConfiguration()
        conf.width = Int(win.frame.width * 2); conf.height = Int(win.frame.height * 2); conf.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: conf) else { return ([], nil) }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        let f = win.frame
        let items: [TextItem] = (req.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox   // normalised, bottom-left origin
            return TextItem(text: c.string, rect: CGRect(x: f.minX + b.minX * f.width, y: f.minY + (1 - b.maxY) * f.height,
                                                         width: b.width * f.width, height: b.height * f.height))
        }
        return (items, img)
    }
    static func jpegBase64(_ img: CGImage, maxSide: CGFloat = 1280) -> String? {
        let rep = NSBitmapImageRep(cgImage: img)
        let scale = min(1, maxSide / CGFloat(max(img.width, img.height)))
        let size = NSSize(width: CGFloat(img.width) * scale, height: CGFloat(img.height) * scale)
        let small = NSImage(size: size)
        small.lockFocus(); rep.draw(in: NSRect(origin: .zero, size: size)); small.unlockFocus()
        guard let tiff = small.tiffRepresentation, let r = NSBitmapImageRep(data: tiff),
              let d = r.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return nil }
        return d.base64EncodedString()
    }
}

// Global (top-left origin) → Cocoa (bottom-left origin) using the primary screen height.
func toCocoa(_ r: CGRect) -> NSRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

// MARK: - Orb (ghost cursor)
final class OrbView: NSView {
    let core = CAGradientLayer(), halo = CALayer()
    var onHover: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = false
        halo.frame = bounds.insetBy(dx: 6, dy: 6); halo.cornerRadius = halo.frame.width / 2
        halo.backgroundColor = NSColor.systemIndigo.withAlphaComponent(0.35).cgColor
        halo.shadowColor = NSColor.systemPurple.cgColor; halo.shadowRadius = 10; halo.shadowOpacity = 0.9; halo.shadowOffset = .zero
        core.type = .radial
        core.colors = [NSColor.white.cgColor, NSColor(calibratedRed: 0.56, green: 0.65, blue: 1, alpha: 1).cgColor,
                       NSColor(calibratedRed: 0.71, green: 0.55, blue: 1, alpha: 0.9).cgColor]
        core.locations = [0, 0.45, 1]; core.startPoint = CGPoint(x: 0.5, y: 0.5); core.endPoint = CGPoint(x: 1, y: 1)
        core.frame = bounds.insetBy(dx: 12, dy: 12); core.cornerRadius = core.frame.width / 2
        layer?.addSublayer(halo); layer?.addSublayer(core)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onHover?() }

    func pulse(_ on: Bool) {
        halo.removeAllAnimations(); core.removeAllAnimations()
        guard on else { return }
        if reduceMotion() { halo.opacity = 1; return }
        let a = CABasicAnimation(keyPath: "transform.scale"); a.fromValue = 0.85; a.toValue = 1.25
        a.duration = 1.4; a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 0.5; o.toValue = 1
        o.duration = 1.4; o.autoreverses = true; o.repeatCount = .infinity
        halo.add(a, forKey: "pulse"); halo.add(o, forKey: "glow")
    }
    func thinking(_ on: Bool) {
        core.removeAnimation(forKey: "spin")
        guard on, !reduceMotion() else { return }
        let r = CABasicAnimation(keyPath: "transform.rotation"); r.fromValue = 0; r.toValue = Double.pi * 2
        r.duration = 1.2; r.repeatCount = .infinity
        core.add(r, forKey: "spin")
    }
}

final class FloatingPanel: NSPanel {
    var acceptsKey = false
    init(size: NSSize, key: Bool = false) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        acceptsKey = key
        isFloatingPanel = true; level = .statusBar; hidesOnDeactivate = false
        backgroundColor = .clear; isOpaque = false; hasShadow = key
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        becomesKeyOnlyIfNeeded = !key
    }
    override var canBecomeKey: Bool { acceptsKey }
}

// MARK: - Ghost-text input (type-ahead with Tab to accept)
final class GhostField: NSView, NSTextFieldDelegate {
    let field = NSTextField(), ghost = NSTextField(labelWithString: "")
    var suggestion = "" { didSet { update() } }
    var usedSuggestion = false
    var onSubmit: ((String) -> Void)?, onEscape: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1; layer?.borderColor = NSColor.separatorColor.cgColor
        for f in [ghost, field] {
            f.font = .systemFont(ofSize: 14); f.isBordered = false; f.drawsBackground = false
            f.focusRingType = .none; f.translatesAutoresizingMaskIntoConstraints = false; addSubview(f)
            NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                                         f.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                                         f.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        ghost.textColor = .tertiaryLabelColor; ghost.lineBreakMode = .byTruncatingTail
        field.delegate = self; field.placeholderString = ""
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func update() {
        let typed = field.stringValue
        if suggestion.lowercased().hasPrefix(typed.lowercased()) && !suggestion.isEmpty {
            let s = NSMutableAttributedString(string: suggestion, attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 14)])
            s.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: (typed as NSString).length))
            ghost.attributedStringValue = s
        } else { ghost.stringValue = "" }
    }
    func controlTextDidChange(_ obj: Notification) { update() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)) where textView.selectedRange().location == (field.stringValue as NSString).length:
            if !suggestion.isEmpty && field.stringValue != suggestion {
                field.stringValue = suggestion; usedSuggestion = true; update()
                textView.moveToEndOfLine(nil); return true
            }
            return sel == #selector(NSResponder.insertTab(_:))
        case #selector(NSResponder.insertNewline(_:)):
            let t = field.stringValue.isEmpty ? suggestion : field.stringValue
            if field.stringValue.isEmpty { usedSuggestion = true }
            if !t.isEmpty { onSubmit?(t) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onEscape?(); return true
        default: return false
        }
    }
}

// MARK: - Push-to-talk (on-device speech recognition)
final class TalkButton: NSButton {
    var onText: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    override func mouseDown(with event: NSEvent) {
        start()
        super.mouseDown(with: event)   // runs until mouse-up
        stop()
    }
    func start() {
        guard let rec = SFSpeechRecognizer(), rec.isAvailable, rec.supportsOnDeviceRecognition else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = true
        request = req; latest = ""
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buf, _ in self?.request?.append(buf) }
        engine.prepare(); try? engine.start()
        contentTintColor = .systemRed
        task = rec.recognitionTask(with: req) { [weak self] res, _ in
            if let s = res?.bestTranscription.formattedString { self?.latest = s; DispatchQueue.main.async { self?.onText?(s) } }
        }
    }
    func stop() {
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); contentTintColor = .secondaryLabelColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.task?.finish() }
    }
}

// MARK: - Chip
final class Chip: NSButton {
    var index = 0
    convenience init(_ text: String, index: Int, target: AnyObject, action: Selector) {
        self.init(title: text, target: target, action: action)
        self.index = index
        isBordered = false; wantsLayer = true
        layer?.cornerRadius = 12; layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                                         .foregroundColor: NSColor.labelColor])
        (cell as? NSButtonCell)?.wraps = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        setAccessibilityLabel("Ask: \(text)")
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - The companion
@MainActor
final class Companion: NSObject, NSApplicationDelegate {
    let tracker = SignalTracker()
    let orbPanel = FloatingPanel(size: NSSize(width: 44, height: 44))
    let orb = OrbView(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
    let card = FloatingPanel(size: NSSize(width: 400, height: 300), key: true)
    let pointer = FloatingPanel(size: NSSize(width: 28, height: 28))
    let ring = FloatingPanel(size: NSSize(width: 10, height: 10))
    var orbPos = NSPoint.zero, orbTarget = NSPoint.zero
    var current: Anticipation?
    var textItems: [TextItem] = []
    var expanded = false, interacted = false, askedThisCard = false
    var chosenIndex: Int?
    var hintLevel = 1, hints: [String] = [], lastQuestion = ""
    var holdTimer: Timer?
    // card widgets
    let stack = NSStackView(), header = NSTextField(labelWithString: ""), chipsRow = NSStackView()
    let input = GhostField(frame: .zero), talk = TalkButton(title: "", target: nil, action: nil)
    let answer = NSTextView(), answerScroll = NSScrollView(), moreRow = NSStackView()
    let footer = NSTextField(labelWithString: "Tab accepts · ↩ asks · esc closes · hold ⌃⌥ to peek")

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        setupOrb(); setupCard(); setupPointer()
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.tracker.onScroll(e) }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in self?.tracker.onKey() }   // counts only
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e) }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e); return e }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.mouseMoved() }
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in ScreenState.locked = true }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in ScreenState.locked = false }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.glide() } }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tracker.refreshFront() }
        }
    }

    // MARK: orb movement: trails the cursor lazily, so you can reach it
    func mouseMoved() {
        let m = NSEvent.mouseLocation
        let d = hypot(m.x - (orbPos.x + 22), m.y - (orbPos.y + 22))
        if d > 140 || !orbPanel.isVisible { orbTarget = NSPoint(x: m.x + 26, y: m.y - 64) }
    }
    func glide() {
        guard orbPanel.isVisible, !expanded else { return }
        let k: CGFloat = reduceMotion() ? 1 : 0.14   // critically-damped-ish follow
        orbPos.x += (orbTarget.x - orbPos.x) * k; orbPos.y += (orbTarget.y - orbPos.y) * k
        orbPanel.setFrameOrigin(orbPos)
    }

    func setupOrb() {
        orbPanel.contentView = orb
        orb.onHover = { [weak self] in self?.expand() }
        orb.setAccessibilityRole(.button); orb.setAccessibilityLabel("Companion has a suggestion")
    }

    func showOrb(thinking: Bool) {
        let m = NSEvent.mouseLocation
        if !orbPanel.isVisible { orbPos = NSPoint(x: m.x + 26, y: m.y - 64); orbTarget = orbPos; orbPanel.setFrameOrigin(orbPos) }
        orbPanel.alphaValue = 0; orbPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; orbPanel.animator().alphaValue = thinking ? 0.55 : 1 }
        orb.thinking(thinking); orb.pulse(!thinking)
    }
    func hideOrb() {
        orb.pulse(false); orb.thinking(false)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; orbPanel.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { self.orbPanel.orderOut(nil) } })
    }

    // MARK: ⌃⌥ hold to peek
    func flags(_ e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if f == [.control, .option] {
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { guard let s = self else { return }
                    if s.current == nil { Task { await s.anticipate(force: true) } } else { s.expand() } }
            }
        } else {
            holdTimer?.invalidate()
            if expanded && !interacted && f.isEmpty { collapse(outcome: nil) }   // released without using it: just peeked
        }
    }

    // MARK: anticipation loop
    func tick() {
        tracker.refreshFront()
        guard !expanded else { return }
        Task { await anticipate(force: false) }
    }

    func anticipate(force: Bool) async {
        var sig = tracker.snapshot()
        if force { sig["force"] = true }
        guard let d = await API.post("api/anticipate", sig), var a = try? JSONDecoder().decode(Anticipation.self, from: d) else { return }
        if a.need_text == true || (force && a.questions == nil) {
            showOrb(thinking: true)
            textItems = AXReader.visibleText(pid: tracker.pid)
            var image: String?
            if textItems.reduce(0, { $0 + $1.text.count }) < 40, a.ocr_allowed ?? true, #available(macOS 14.0, *) {
                let (items, img) = await OCR.window(pid: tracker.pid)
                textItems = items
                if items.isEmpty, let img = img { image = OCR.jpegBase64(img) }
            }
            sig["screen_text"] = textItems.map(\.text).joined(separator: "\n")
            if let image = image { sig["image_b64"] = image }
            sig["force"] = force ? true : nil
            guard let d2 = await API.post("api/anticipate", sig), let a2 = try? JSONDecoder().decode(Anticipation.self, from: d2) else { hideOrb(); return }
            a = a2
        }
        guard let qs = a.questions, !qs.isEmpty else { if orbPanel.alphaValue < 0.9 { hideOrb() }; return }
        if let old = current, old.id != a.id, !askedThisCard { feedback(outcome: "ignored", index: nil, final: nil) }
        current = a; askedThisCard = false
        showOrb(thinking: false)
        if force { expand() }
    }

    // MARK: card
    func setupCard() {
        let fx = NSVisualEffectView(); fx.material = .popover; fx.blendingMode = .behindWindow; fx.state = .active
        fx.wantsLayer = true; fx.layer?.cornerRadius = 18; fx.layer?.masksToBounds = true
        fx.layer?.borderWidth = 1; fx.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        card.contentView = fx
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor), stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: fx.topAnchor), stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
                                     fx.widthAnchor.constraint(equalToConstant: 400)])
        header.font = .systemFont(ofSize: 11, weight: .semibold); header.textColor = .secondaryLabelColor
        chipsRow.orientation = .vertical; chipsRow.alignment = .leading; chipsRow.spacing = 6
        talk.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Hold to talk")
        talk.isBordered = false; talk.contentTintColor = .secondaryLabelColor; talk.toolTip = "Hold to talk (on-device)"
        talk.onText = { [weak self] s in self?.input.field.stringValue = s; self?.input.update(); self?.interacted = true }
        let inputRow = NSStackView(views: [input, talk]); inputRow.spacing = 8
        input.widthAnchor.constraint(equalToConstant: 336).isActive = true
        input.onSubmit = { [weak self] q in self?.ask(q) }
        input.onEscape = { [weak self] in self?.collapse(outcome: "dismissed") }
        answer.isEditable = false; answer.drawsBackground = false; answer.font = .systemFont(ofSize: 13.5)
        answer.textContainerInset = NSSize(width: 0, height: 2)
        answerScroll.documentView = answer; answerScroll.hasVerticalScroller = true; answerScroll.drawsBackground = false
        answerScroll.translatesAutoresizingMaskIntoConstraints = false
        answerScroll.widthAnchor.constraint(equalToConstant: 368).isActive = true
        answerScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        answer.minSize = NSSize(width: 368, height: 0); answer.isVerticallyResizable = true
        answer.autoresizingMask = [.width]; answer.textContainer?.widthTracksTextView = true
        moreRow.spacing = 8
        footer.font = .systemFont(ofSize: 10.5); footer.textColor = .tertiaryLabelColor
        for v in [header, chipsRow, inputRow, answerScroll, moreRow, footer] { stack.addArrangedSubview(v) }
        answerScroll.isHidden = true; moreRow.isHidden = true
    }

    func expand() {
        guard let a = current, !expanded else { return }
        expanded = true; interacted = false; chosenIndex = nil; hintLevel = 1; hints = []
        let modeName = (a.mode ?? "unknown") == "unknown" ? "Looks like you're stuck" : "\((a.mode ?? "").capitalized)\(a.subject.map { $0.isEmpty ? "" : " · \($0)" } ?? "")"
        header.stringValue = modeName.uppercased()
        header.toolTip = (a.reasons ?? []).joined(separator: "\n")
        chipsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, q) in (a.questions ?? []).enumerated() {
            chipsRow.addArrangedSubview(Chip(q.text, index: i, target: self, action: #selector(chipTapped(_:))))
        }
        input.field.stringValue = ""; input.suggestion = a.best ?? ""; input.usedSuggestion = false
        answer.string = ""; answerScroll.isHidden = true; moreRow.isHidden = true
        layoutCard(near: NSRect(origin: orbPos, size: orbPanel.frame.size))
        orb.pulse(false)
        card.makeKeyAndOrderFront(nil); card.makeFirstResponder(input.field)
        springIn(card)
    }

    func layoutCard(near r: NSRect) {
        guard let fx = card.contentView else { return }
        fx.layoutSubtreeIfNeeded()
        let size = fx.fittingSize
        let scr = NSScreen.screens.first { NSMouseInRect(r.origin, $0.frame, false) }?.visibleFrame ?? NSScreen.main!.visibleFrame
        var o = NSPoint(x: r.midX - 24, y: r.midY - size.height + 24)
        o.x = min(max(o.x, scr.minX + 12), scr.maxX - size.width - 12)
        o.y = min(max(o.y, scr.minY + 12), scr.maxY - size.height - 12)
        card.setFrame(NSRect(origin: o, size: size), display: true, animate: false)
    }

    func springIn(_ p: NSPanel) {
        guard let l = p.contentView?.layer else { p.alphaValue = 1; return }
        p.alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        if reduceMotion() { return }
        l.anchorPoint = CGPoint(x: 0.5, y: 0.5); l.position = CGPoint(x: l.bounds.midX, y: l.bounds.midY)
        let s = CASpringAnimation(keyPath: "transform.scale")
        s.fromValue = 0.92; s.toValue = 1; s.damping = 18; s.stiffness = 260; s.mass = 1; s.initialVelocity = 4
        s.duration = s.settlingDuration
        l.add(s, forKey: "in")
    }

    func collapse(outcome: String?) {
        if let o = outcome, !askedThisCard { feedback(outcome: o, index: nil, final: nil) }
        expanded = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; card.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { self.card.orderOut(nil) } })
        if askedThisCard || outcome != nil { current = nil; hideOrb() } else { orb.pulse(true) }
    }

    @objc func chipTapped(_ c: Chip) {
        interacted = true; chosenIndex = c.index
        input.field.stringValue = c.title; input.usedSuggestion = true; input.update()
        ask(c.title)
    }

    // MARK: asking + streaming answer
    func ask(_ q: String) {
        guard let a = current else { return }
        interacted = true
        if !askedThisCard {
            let qs = (a.questions ?? []).map(\.text)
            if let i = chosenIndex ?? (input.usedSuggestion ? 0 : nil) {
                feedback(outcome: q == qs[i] ? "chosen" : "edited", index: i, final: q)
            } else if let i = qs.firstIndex(of: q) {
                feedback(outcome: "chosen", index: i, final: q)
            } else {
                feedback(outcome: "typed", index: nil, final: q)
            }
            askedThisCard = true
        }
        lastQuestion = q
        stream(level: hintLevel)
    }

    func stream(level: Int) {
        guard let a = current else { return }
        answerScroll.isHidden = false; moreRow.isHidden = true
        if level == 1 { answer.string = "" } else { answer.textStorage?.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13.5)])) }
        layoutCard(near: card.frame)
        var piece = ""
        let body: [String: Any] = ["id": a.id ?? "", "question": lastQuestion, "level": level, "previous": hints]
        Task {
            await API.stream("api/answer", body) { ev in
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    if let d = ev.delta {
                        piece += d
                        self.answer.textStorage?.append(NSAttributedString(string: d, attributes: [.font: NSFont.systemFont(ofSize: 13.5), .foregroundColor: NSColor.labelColor]))
                        self.answer.scrollToEndOfDocument(nil)
                    }
                    if let e = ev.error { self.answer.string = e }
                    if let anchor = ev.anchor { self.point(at: anchor) }
                    if ev.done == true {
                        self.hints.append(piece)
                        self.showMore(more: ev.more ?? false)
                        self.layoutCard(near: self.card.frame)
                    }
                } }
            }
        }
    }

    func showMore(more: Bool) {
        moreRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard more else { moreRow.isHidden = true; return }
        let next = NSButton(title: hintLevel == 1 ? "Next hint" : "Show full solution", target: self, action: #selector(nextHint))
        next.bezelStyle = .rounded; next.controlSize = .regular; next.keyEquivalent = "\r"
        let note = NSTextField(labelWithString: "Try it first. The next step is one tap away")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        moreRow.addArrangedSubview(next); moreRow.addArrangedSubview(note); moreRow.isHidden = false
    }
    @objc func nextHint() { hintLevel = min(3, hintLevel + 1); stream(level: hintLevel) }

    // MARK: pointing: an animated pointer springs from the orb to the on-screen target, then a ring pulses
    func setupPointer() {
        let v = NSView(); v.wantsLayer = true
        let dot = CAShapeLayer()
        let p = CGMutablePath(); p.move(to: CGPoint(x: 4, y: 24)); p.addLine(to: CGPoint(x: 4, y: 4)); p.addLine(to: CGPoint(x: 18, y: 10)); p.closeSubpath()
        dot.path = p; dot.fillColor = NSColor.controlAccentColor.cgColor; dot.strokeColor = NSColor.white.cgColor; dot.lineWidth = 1.5
        dot.shadowColor = NSColor.controlAccentColor.cgColor; dot.shadowRadius = 8; dot.shadowOpacity = 0.9; dot.shadowOffset = .zero
        v.layer?.addSublayer(dot); pointer.contentView = v; pointer.ignoresMouseEvents = true
        let rv = NSView(); rv.wantsLayer = true
        rv.layer?.borderColor = NSColor.controlAccentColor.cgColor; rv.layer?.borderWidth = 3; rv.layer?.cornerRadius = 10
        rv.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        ring.contentView = rv; ring.ignoresMouseEvents = true
    }

    func point(at anchor: String) {
        let needle = anchor.lowercased()
        guard let item = textItems.first(where: { $0.text.lowercased().contains(needle) && $0.rect.width > 1 }) else { return }
        let target = toCocoa(item.rect)
        let start = orbPanel.frame.origin
        pointer.setFrameOrigin(start); pointer.alphaValue = 1; pointer.orderFrontRegardless()
        let end = NSPoint(x: target.minX - 6, y: target.midY - 22)
        if reduceMotion() { pointer.setFrameOrigin(end); highlight(target); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)   // overshoot = spring feel
            pointer.animator().setFrameOrigin(end)
        }, completionHandler: { MainActor.assumeIsolated { self.highlight(target) } })
    }

    func highlight(_ r: NSRect) {
        ring.setFrame(r.insetBy(dx: -6, dy: -4), display: true); ring.alphaValue = 1; ring.orderFrontRegardless()
        if !reduceMotion(), let l = ring.contentView?.layer {
            let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 1; a.toValue = 0.35
            a.duration = 0.6; a.autoreverses = true; a.repeatCount = 3
            l.add(a, forKey: "pulse")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; self.ring.animator().alphaValue = 0; self.pointer.animator().alphaValue = 0 },
                                                     completionHandler: { MainActor.assumeIsolated { self.ring.orderOut(nil); self.pointer.orderOut(nil) } })
            }
        }
    }

    // MARK: learning signal
    func feedback(outcome: String, index: Int?, final: String?) {
        guard let id = current?.id else { return }
        var b: [String: Any] = ["id": id, "outcome": outcome]
        if let i = index { b["index"] = i }
        if let f = final { b["final_text"] = f }
        Task { _ = await API.post("api/companion/feedback", b) }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { Companion() }
app.delegate = delegate
app.run()
