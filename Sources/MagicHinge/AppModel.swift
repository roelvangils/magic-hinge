import AppKit
import SwiftUI
import DuoCore
import DuoHardware
import DuoGraphics
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: FoldSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "foldSettings") }
            overlay?.renderer.settings = settings
            effect?.setCursorHidden(effectActive && settings.hideCursor)
        }
    }
    @Published var enabled = true {
        didSet { if !enabled { dismiss(); resetMotion(); phase = .idle } }
    }
    @Published private(set) var angle: Double?
    @Published private(set) var sensorMessage = L10n.text("Looking for hinge sensor…")
    let permissionService = PermissionService()
    @Published private(set) var permission = false
    private var permissionObservation: AnyCancellable?
    @Published private(set) var hasBuiltInScreen = DesktopCapture.builtInScreen != nil
    @Published private(set) var isLidClosed = HingeSensor.lidIsClosed()
    @Published private(set) var effectActive = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var phase = FoldSession.Phase.idle
    @Published var previewDegrees = 25.0
    var livePreviewEnabled = false
    @Published private(set) var liveDegrees = 0.0
    @Published private(set) var isDemo = false
    #if DEBUG
    @Published private(set) var lockTestStatus = ""
    private let lockProbe = LockScreenProbe()
    #endif
    private let sensor = HingeSensor()
    private let desktopCapture = DesktopCapture()
    private var effect: DesktopEffect?
    private var overlay: OverlayWindow? { effect?.overlay }
    private let lifecycle = SessionLifecycle()
    private var sessionActive = DesktopCapture.sessionUnlocked
    private var openingArmed = HingeSensor.lidIsClosed()
    private var lastPhysicalAngle: Double?
    private var session = FoldSession()
    private var hingeFilter = HingeMotionFilter()
    private var lastReading: TimeInterval = 0
    private var lastPermissionCheck: TimeInterval = 0
    private var lastLidCheck: TimeInterval = 0
    private var lastUIUpdate: TimeInterval = 0
    private var lastPreviewUpdate: TimeInterval = 0
    private var generation = UUID()
    private var captureStarted: TimeInterval?
    private var task: Task<Void, Never>?
    private var warmup: Task<Void, Never>?
    private var warmupGeneration = UUID()
    private var demoStarted: TimeInterval?
    private var watchdog: Timer?
    private var suspended = false

    init() {
        let defaults = UserDefaults.standard
        var initial = defaults.data(forKey: "foldSettings").flatMap { try? JSONDecoder().decode(FoldSettings.self, from: $0) } ?? FoldSettings()
        // Apply the requested stronger blur to the existing installation once, retaining other tuning.
        if defaults.integer(forKey: "motionSettingsVersion") < 2 {
            initial.blur = min(0.24, max(0.11, initial.blur * 2))
            // A fresh installation already has the new default.
            if defaults.data(forKey: "foldSettings") == nil { initial.blur = 0.11 }
            defaults.set(2, forKey: "motionSettingsVersion")
            if let data = try? JSONEncoder().encode(initial) { defaults.set(data, forKey: "foldSettings") }
        }
        settings = initial
        permission = permissionService.granted
        permissionObservation = permissionService.$granted.removeDuplicates().sink { [weak self] allowed in
            guard let self else { return }
            self.permission = allowed
            self.desktopCapture.invalidate()
            if !allowed { self.dismiss(); self.resetMotion(); self.phase = .idle }
            else { self.prepareCapture() }
        }
        #if DEBUG
        lockProbe.onStatus = { [weak self] status in self?.lockTestStatus = status }
        #endif
        do {
            let effect = try DesktopEffect(settings: settings)
            effect.overlay.renderer.onFailure = { [weak self] message in self?.fail(message) }
            effect.clock.onFrame = { [weak self] now in self?.renderFrame(at: now) }
            self.effect = effect
        } catch { errorMessage = error.localizedDescription }
        startSensor()
        watchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        RunLoop.main.add(watchdog!, forMode: .common)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            lifecycle.observe(name, center: workspace) { [weak self] in self?.suspend() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            lifecycle.observe(name, center: workspace) { [weak self] in self?.resume() }
        }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            lifecycle.observe(name, center: workspace) { [weak self] in self?.sessionChanged() }
        }
        lifecycle.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self else { return }
            self.dismiss(); self.resetMotion(); self.phase = .idle
            self.desktopCapture.invalidate()
            self.hasBuiltInScreen = DesktopCapture.builtInScreen != nil
            self.refreshLidState(); self.prepareCapture()
        }
        lifecycle.observe(NSApplication.didResignActiveNotification) { [weak self] in
            if self?.isDemo == true { self?.dismiss(); self?.resetMotion() }
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            lifecycle.observe(Notification.Name(name), center: DistributedNotificationCenter.default()) { [weak self] in self?.sessionChanged() }
        }
        lifecycle.monitorEscape { [weak self] in self?.emergencyStop() }
        prepareCapture()
    }

    var status: String {
        if let errorMessage { return errorMessage }
        if !enabled { return L10n.text("Effect paused") }
        if isDemo { return L10n.text("Demo · both directions · 8 seconds") }
        if !hasBuiltInScreen { return L10n.text("Open your MacBook to begin") }
        if !permission { return L10n.text("Screen access required") }
        if angle == nil { return sensorMessage }
        if phase == .returning { return L10n.text("Returning to your desktop…") }
        if effectActive { return L10n.text("Following movement…") }
        return L10n.text("Ready")
    }
    private var eligible: Bool { enabled && permission && hasBuiltInScreen && !suspended && sessionActive && errorMessage == nil }
    private func startSensor() {
        guard !suspended, sessionActive else { return }
        sensor.start { [weak self] reading in Task { @MainActor in self?.receive(reading) } }
    }
    private func receive(_ reading: HingeSensor.Reading) {
        guard !suspended, sessionActive else { return }
        lastReading = reading.timestamp
        if let raw = reading.angle {
            lastPhysicalAngle = raw
            if raw <= 3 { openingArmed = true }
        }
        if sensorMessage != reading.message { sensorMessage = reading.message }
        // Hardware/rendering runs at 120 Hz; the settings window needs only a 10 Hz readout.
        if reading.angle == nil || angle == nil || reading.timestamp - lastUIUpdate >= 0.1 {
            if angle != reading.angle { angle = reading.angle }
            lastUIUpdate = reading.timestamp
        }
        guard !isDemo else { return }
        if !eligible { hingeFilter.reset() }
        let filteredAngle = hingeFilter.receive(angle: reading.angle, at: reading.timestamp)
        let action: FoldSession.Action
        if openingArmed, eligible, let raw = reading.angle, raw > 3, session.phase == .idle {
            openingArmed = false
            if settings.animateOnOpen { action = session.beginOpening(angle: raw, at: reading.timestamp) }
            else { openingArmed = false; action = session.receive(angle: filteredAngle, at: reading.timestamp, enabled: eligible, animateOpening:settings.animateOnOpen, animateClosing:settings.animateOnClose) }
        } else { action = session.receive(angle: filteredAngle, at: reading.timestamp, enabled: eligible, animateOpening:settings.animateOnOpen, animateClosing:settings.animateOnClose) }
        if phase != session.phase { phase = session.phase }
        switch action {
        case .capture: capture(demo: false)
        case .dismiss: dismiss()
        case .none: break
        }
        // Presentation is driven by DisplayClock, never by irregular HID callbacks.
    }

    private func resetMotion() { session.reset(); hingeFilter.reset() }

    private func renderFrame(at now: TimeInterval) {
        guard let overlay, effectActive else { return }
        if let demoStarted {
            let elapsed = now - demoStarted
            if elapsed >= 8 { dismiss(); resetMotion(); phase = .idle; return }
            // Closing builds a fold; reopening releases it without passing through flat.
            overlay.renderer.foldDegrees = 19 * (1 - cos(elapsed * .pi / 4))
        } else {
            let frame = session.frame(at: now)
            if phase != frame.phase { phase = frame.phase }
            overlay.renderer.foldDegrees = frame.degrees
            if frame.action == .dismiss { dismiss(); return }
        }
        if livePreviewEnabled, now - lastPreviewUpdate >= 1.0 / 30 {
            if liveDegrees != overlay.renderer.foldDegrees { liveDegrees = overlay.renderer.foldDegrees }
            lastPreviewUpdate = now
        }
        overlay.redraw()
    }

    private func checkHealth() {
        let now = ProcessInfo.processInfo.systemUptime
        // Keep this independent of HID readings: those can stop in clamshell mode.
        // Reuse the watchdog rather than adding another timer or polling at hinge speed.
        if now - lastLidCheck >= 0.5 {
            lastLidCheck = now
            refreshLidState()
        }
        sessionChanged()
        if now - lastPermissionCheck > 2 {
            lastPermissionCheck = now
            permissionService.refresh()
            prepareCapture()
        }
        if !permission, effectActive || captureStarted != nil { dismiss(); resetMotion(); phase = .idle }
        if sessionActive, !isDemo, lastReading > 0, now - lastReading > 0.5, angle != nil {
            angle = nil; sensorMessage = L10n.text("No recent sensor reading; effect stopped.")
            dismiss(); resetMotion(); phase = .idle
        }
        if let began = captureStarted, now - began > 2 { fail(L10n.text("Screen capture timed out. Try again.")) }
    }
    private func prepareCapture() {
        guard permission, hasBuiltInScreen, !suspended, sessionActive, warmup == nil else { return }
        let token = UUID(); warmupGeneration = token
        warmup = Task { [weak self] in
            guard let self else { return }
            defer { if self.warmupGeneration == token { self.warmup = nil } }
            do { try await self.desktopCapture.prepare(excluding: self.overlay.map { [$0.id] } ?? []) }
            catch { if !Task.isCancelled { Diagnostics.record("capture preparation: \(error.localizedDescription)") } }
        }
    }
    func retry() {
        errorMessage = nil; dismiss(); resetMotion(); phase = .idle
        permissionService.refresh()
        hasBuiltInScreen = DesktopCapture.builtInScreen != nil
        desktopCapture.invalidate(); prepareCapture(); startSensor()
    }
    func requestPermission() { permissionService.request(); prepareCapture() }
    func demonstrate() {
        guard !isDemo, permission, hasBuiltInScreen else { return }
        dismiss(); resetMotion(); errorMessage = nil
        isDemo = true
        capture(demo: true)
    }
    private func capture(demo: Bool) {
        guard let overlay, captureStarted == nil else { return }
        // Also handles a new movement arriving on the exact frame a previous return completed.
        effect?.clock.stop(); overlay.hide(); effect?.setCursorHidden(false); effectActive = false
        let token = UUID(); generation = token
        let began = ProcessInfo.processInfo.systemUptime
        captureStarted = began
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.desktopCapture.snapshot(excluding: [overlay.id])
                guard !Task.isCancelled, self.generation == token, !self.suspended, DesktopCapture.sessionUnlocked,
                      let screen = DesktopCapture.builtInScreen,
                      DesktopCapture.displayID(screen) == snapshot.displayID else { return }
                let captured = ProcessInfo.processInfo.systemUptime
                try overlay.renderer.setPixelBuffer(snapshot.pixelBuffer)
                self.captureStarted = nil
                overlay.renderer.settings = self.settings
                overlay.renderer.foldDegrees = demo ? 0 : self.session.degrees
                overlay.show(on: screen)
                self.effectActive = true
                self.openingArmed = false
                self.effect?.setCursorHidden(self.settings.hideCursor)
                if demo { self.demoStarted = ProcessInfo.processInfo.systemUptime }
                self.effect?.clock.start(view: overlay.view, screen: screen)
                Diagnostics.record(String(format: "capture: %.1f ms, GPU submission: %.1f ms, %dx%d IOSurface", (captured-began)*1000,
                    (ProcessInfo.processInfo.systemUptime-captured)*1000, CVPixelBufferGetWidth(snapshot.pixelBuffer), CVPixelBufferGetHeight(snapshot.pixelBuffer)))
            } catch {
                if !Task.isCancelled, self.generation == token { self.fail(error.localizedDescription) }
            }
        }
    }
    func emergencyStop() {
        if effectActive || captureStarted != nil { enabled = false; dismiss(); resetMotion(); phase = .idle }
    }
    private func fail(_ message: String) { Diagnostics.record("failure: \(message)"); errorMessage = message; dismiss(); resetMotion(); phase = .idle }
    private func dismiss() {
        generation = UUID(); task?.cancel(); task = nil
        effect?.stop(); demoStarted = nil
        captureStarted = nil; effectActive = false; isDemo = false
        if liveDegrees != 0 { liveDegrees = 0 }
    }
    private func sessionChanged() {
        let unlocked = DesktopCapture.sessionUnlocked
        guard unlocked != sessionActive else { return }
        sessionActive = unlocked
        dismiss(); resetMotion(); phase = .idle
        warmupGeneration = UUID(); warmup?.cancel(); warmup = nil; desktopCapture.invalidate()
        if unlocked {
            errorMessage = nil; lastReading = 0
            if !suspended { startSensor() }
            prepareCapture()
        } else { sensor.stop() }
    }
    private func suspend() {
        refreshLidState()
        if HingeSensor.lidIsClosed() || (lastPhysicalAngle.map { $0 < 25 } ?? false) { openingArmed = true }
        guard !suspended else { return }
        suspended = true; dismiss(); resetMotion(); phase = .idle; sensor.stop(); angle = nil
        warmupGeneration = UUID(); warmup?.cancel(); warmup = nil; desktopCapture.invalidate()
    }
    private func resume() {
        refreshLidState()
        guard suspended else { return }
        suspended = false; sessionActive = DesktopCapture.sessionUnlocked; lastReading = 0; retry()
    }
    #if DEBUG
    func testLockScreen() { lockProbe.arm() }
    #endif
    private func refreshLidState() {
        let closed = HingeSensor.lidIsClosed()
        if isLidClosed != closed { isLidClosed = closed }
    }
    func shutdown() {
        #if DEBUG
        lockProbe.stop()
        #endif
        lifecycle.stop(); permissionObservation = nil; permissionService.shutdown()
        dismiss(); sensor.stop(); watchdog?.invalidate(); warmup?.cancel(); desktopCapture.invalidate()
    }
}
