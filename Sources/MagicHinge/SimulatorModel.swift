import SwiftUI
import Combine
import SceneKit
import MetalKit
import DuoCore
import DuoGraphics
import DuoSimulation

@MainActor
final class SimulatorModel: ObservableObject {
    @Published var angle = 0.0
    @Published var followSensor = false
    @Published var effectEnabled = true
    @Published private(set) var usesDesktop = UserDefaults.standard.object(forKey:"simulator.usesDesktop") as? Bool ?? true
    @Published private(set) var showSwipeHint = false
    @Published var error: String?
    @Published private(set) var laptop = MacBookModel()
    @Published private(set) var configuration: MacBookConfiguration
    @Published private(set) var colorChoice: MacBookColorChoice
    @Published private(set) var loadingModel = false
    @Published private(set) var modelError: String?
    let detectedProduct = MacBookConfiguration.currentProductName
    private var assetTask: Task<Void,Never>?
    private var loadedConfiguration: MacBookConfiguration?
    private var requestedConfiguration: MacBookConfiguration?
    private var systemAppearanceObserver: AnyCancellable?
    var detectedConfiguration: MacBookConfiguration? { detectedProduct.flatMap(MacBookConfiguration.detected) }
    var colorWasChosen: Bool { UserDefaults.standard.string(forKey:"simulator.color.\(configuration.family.rawValue)") != nil }

    private var renderer: FoldRenderer?
    private var session = FoldSession()
    private var clock: Task<Void,Never>?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var shownAngle = 0.0
    private var floating = ClosedLidFloat()
    private var impact = LidImpactResponse()
    private var closureContact = LidClosureContact()
    private var visualContact = LidClosureContact()
    private var snapSound: LidSnapSound?
    private var lidTransition: LidTransition?
    private var releaseSpring: LidReleaseSpring?
    private var keyboardMotion: LidKeyboardMotion?
    private var interruptedToggleTarget: Double?
    private var lastTextureDegrees: Double?
    private var lastSettings: FoldSettings?
    private var textureGeneration = UUID()
    private var textureBusy = false
    private var texturePending = false
    private var visible = false
    private var settings = FoldSettings()
    private var captureTask: Task<Void,Never>?
    private var usingDemo = true
    private var exampleIsDark = false
    private var hintHiddenUntil = 0.0
    private var hintTask: Task<Void,Never>?
    private var sourceFadeStarted: Double?
    private var lastSourceBlend: Double?
    weak var view: SimulationSceneView?

    private var privacyObservers: [AnyCancellable] = []
    private let demoOnly: Bool
    init(demoOnly: Bool = false) {
        self.demoOnly = demoOnly
        if demoOnly { usesDesktop = false }
        let detected = MacBookConfiguration.currentProductName.flatMap(MacBookConfiguration.detected)
        let initial = detected ?? MacBookConfiguration(family:.pro,size:14,color:.spaceBlack)
        let choice = MacBookColorChoice(storedValue:UserDefaults.standard.string(forKey:"simulator.color.\(initial.family.rawValue)"),fallback:initial.color)
        colorChoice = choice
        configuration = MacBookConfiguration(family:initial.family,size:initial.size,
            color:choice.resolved(for:initial.family,dark:Self.systemIsDark))
        laptop.setAngle(0)
        do { snapSound = try LidSnapSound() }
        catch { self.error = error.localizedDescription }
        _ = session.receive(angle: angle, at: lastTick)
        do {
            let renderer = try FoldRenderer()
            try renderer.setImage(ExampleScreen.image(dark:exampleIsDark))
            self.renderer = renderer
        } catch { self.error = error.localizedDescription }
        systemAppearanceObserver = DistributedNotificationCenter.default()
            .publisher(for:Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on:RunLoop.main)
            .sink { [weak self] _ in self?.refreshSystemColor() }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            privacyObservers.append(DistributedNotificationCenter.default().publisher(for: Notification.Name(name))
                .receive(on: RunLoop.main).sink { [weak self] _ in
                    guard let self else { return }
                    self.clearDesktop()
                    self.setVisible(DesktopCapture.sessionUnlocked && NSApp.isActive)
                })
        }
    }
    // Read the OS preference, independent of the app's explicit Light/Dark override.
    private static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey:"AppleInterfaceStyle") == "Dark"
    }
    func selectColor(_ choice: MacBookColorChoice) {
        colorChoice = choice
        UserDefaults.standard.set(choice.storedValue,forKey:"simulator.color.\(configuration.family.rawValue)")
        select()
    }
    private func refreshSystemColor() {
        guard colorChoice == .system else { return }
        let color = colorChoice.resolved(for:configuration.family,dark:Self.systemIsDark)
        guard color != configuration.color else { return }
        configuration = MacBookConfiguration(family:configuration.family,size:configuration.size,color:color)
        loadModel()
    }
    func select(family: MacBookFamily? = nil, size: Int? = nil, color: MacBookColor? = nil) {
        let family = family ?? configuration.family
        let choice = color.map(MacBookColorChoice.fixed) ?? MacBookColorChoice(
            storedValue:UserDefaults.standard.string(forKey:"simulator.color.\(family.rawValue)"),
            fallback:family == configuration.family ? configuration.color : family.colors[0])
        colorChoice = choice
        configuration = MacBookConfiguration(family:family,size:size ?? configuration.size,
            color:choice.resolved(for:family,dark:Self.systemIsDark))
        if let color { UserDefaults.standard.set(color.rawValue,forKey:"simulator.color.\(family.rawValue)") }
        loadModel()
    }
    func useDetectedModel() {
        guard let detected = detectedConfiguration else { return }
        select(family:detected.family,size:detected.size)
    }
    func loadModel() {
        guard visible else { return }
        if loadedConfiguration == configuration {
            assetTask?.cancel(); requestedConfiguration = nil; loadingModel = false; modelError = nil
            return
        }
        guard requestedConfiguration != configuration else { return }
        assetTask?.cancel()
        let requested = configuration
        requestedConfiguration = requested; loadingModel = true; modelError = nil
        assetTask = Task { [weak self] in
            do {
                let url = try await AppleModelCache.shared.modelURL(for:requested)
                try Task.checkCancellation()
                let newLaptop = try await Task.detached(priority:.userInitiated) {
                    try MacBookModel(assetURL:url,configuration:requested)
                }.value
                try Task.checkCancellation()
                guard let self, self.configuration == requested else { return }
                self.floating.reset(); self.impact.reset(); self.visualContact.reset(); self.view?.cancelAnvil()
                self.textureGeneration = UUID()
                self.laptop = newLaptop; self.loadedConfiguration = requested
                newLaptop.setAngle(self.shownAngle)
                self.view?.scene = newLaptop.scene; self.view?.pointOfView = newLaptop.camera
                self.view?.setAccessibilityLabel(L10n.format("Interactive 3D model of %@", requested.title))
                if self.usingDemo {
                    try self.renderer?.setImage(ExampleScreen.image(dark:self.exampleIsDark))
                }
                self.lastTextureDegrees = nil
                self.updateTexture(degrees:self.effectEnabled ? self.session.degrees : 0)
                self.loadingModel = false; self.requestedConfiguration = nil
                self.view?.needsDisplay = true
                self.startClock()
            } catch {
                guard !Task.isCancelled, let self, self.configuration == requested else { return }
                self.modelError = error.localizedDescription
                self.loadingModel = false; self.requestedConfiguration = nil
            }
        }
    }
    func setAngle(_ value: Double) {
        noteInteraction()
        interruptLidMotion()
        applyAngle(value,at:ProcessInfo.processInfo.systemUptime)
        startClock()
    }
    func interruptLidMotion() { lidTransition = nil; releaseSpring = nil; keyboardMotion = nil; interruptedToggleTarget = nil }
    func noteInteraction() {
        hintHiddenUntil = ProcessInfo.processInfo.systemUptime+8
        showSwipeHint = false
        scheduleSwipeHint()
    }
    private func scheduleSwipeHint() {
        hintTask?.cancel(); hintTask = nil
        guard visible else { return }
        let delay = max(0,hintHiddenUntil-ProcessInfo.processInfo.systemUptime)
        hintTask = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(delay)) } catch { return }
            guard let self else { return }
            self.updateSwipeHint(at:ProcessInfo.processInfo.systemUptime)
            self.hintTask = nil
        }
    }
    private func updateSwipeHint(at now: Double) {
        let settled = abs(shownAngle-angle) < 0.05 && lidTransition == nil && releaseSpring == nil && keyboardMotion == nil
        let visible = visible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !loadingModel && settled && now >= hintHiddenUntil
            && (shownAngle <= 0.2 || shownAngle >= 45)
        if showSwipeHint != visible { showSwipeHint = visible }
        view?.positionSwipeHint()
    }
    func beginGesture() {
        noteInteraction()
        // Preserve the direction if this initial press becomes a reversing double-click.
        interruptedToggleTarget = lidTransition?.target
        lidTransition = nil; releaseSpring = nil; keyboardMotion = nil
    }
    func releaseGesture(velocity: Double) {
        guard visible else { return }
        // Only an opening flick (or a gently released overextension) returns to the open detent.
        guard velocity > 65 || (angle > 90 && velocity >= -25) else { return }
        lidTransition = nil; keyboardMotion = nil
        releaseSpring = LidReleaseSpring(angle:angle,velocity:velocity)
        startClock()
    }
    private func applyAngle(_ value: Double, at time: Double) {
        angle = min(130,max(0,value))
        _ = session.receive(angle:angle,at:time, animateOpening:settings.animateOnOpen, animateClosing:settings.animateOnClose)
    }
    func stepLid(by delta: Double) {
        noteInteraction()
        lidTransition = nil; releaseSpring = nil; interruptedToggleTarget = nil
        if keyboardMotion == nil { keyboardMotion = LidKeyboardMotion(angle:angle) }
        keyboardMotion?.step(by:delta)
        startClock()
    }
    func moveLid(to destination: Double, slowMotion: Bool = false) {
        noteInteraction()
        interruptLidMotion()
        lidTransition = LidTransition(from:angle,target:destination,at:ProcessInfo.processInfo.systemUptime,
                                      openingOvershoot:destination == 90 ? 5 : 0,slowMotion:slowMotion)
        startClock()
    }
    func toggleLid(slowMotion: Bool = false) {
        let destination = (lidTransition?.target ?? interruptedToggleTarget ?? keyboardMotion?.target ?? angle) < 45 ? 90.0 : 0.0
        moveLid(to:destination,slowMotion:slowMotion)
    }
    func update(settings: FoldSettings) {
        self.settings = settings
        if visible { updateTexture(degrees:effectEnabled ? session.degrees : 0) }
    }
    func setVisible(_ value: Bool) {
        visible = value
        if value { refreshSystemColor() }
        view?.isPlaying = false; view?.rendersContinuously = false
        if value { snapSound?.activate(); scheduleSwipeHint(); loadModel(); updateTexture(degrees:effectEnabled ? session.degrees : 0); startClock() }
        else { assetTask?.cancel(); assetTask = nil; requestedConfiguration = nil; loadingModel = false; visualContact.reset(); view?.cancelAnvil(); closureContact.reset(); snapSound?.stop(); hintTask?.cancel(); hintTask = nil; showSwipeHint = false; interruptLidMotion(); floating.reset(); impact.reset(); laptop.setFloatingOffset(0); clock?.cancel(); clock = nil; captureTask?.cancel(); captureTask = nil; view?.refineWhenStill(false) }
    }
    func reset() {
        visualContact.reset(); view?.cancelAnvil()
        closureContact.reset(); snapSound?.stop(); snapSound?.activate()
        interruptLidMotion(); floating.reset(); impact.reset(); laptop.setFloatingOffset(0)
        noteInteraction()
        session.reset(); angle = 0; shownAngle = 0
        _ = session.receive(angle:0,at:ProcessInfo.processInfo.systemUptime)
        laptop.setAngle(0); laptop.resetCamera()
        view?.pointOfView = laptop.camera
        lastTextureDegrees = nil; updateTexture(degrees:0)
        view?.needsDisplay = true
        startClock()
    }
    func setExampleAppearance(dark: Bool) {
        guard exampleIsDark != dark else { return }
        exampleIsDark = dark
        guard usingDemo else { return }
        do {
            try renderer?.setImage(ExampleScreen.image(dark:dark),crossfade:true)
            beginSourceFade()
        } catch { self.error = error.localizedDescription }
    }
    func setDesktopEnabled(_ enabled: Bool) {
        guard !demoOnly else { return }
        usesDesktop = enabled
        UserDefaults.standard.set(enabled,forKey:"simulator.usesDesktop")
        captureTask?.cancel(); captureTask = nil
        error = nil
        if enabled { refreshDesktop() }
        else {
            do {
                try renderer?.setImage(ExampleScreen.image(dark:exampleIsDark),crossfade:true)
                usingDemo = true; beginSourceFade()
            } catch { self.error = error.localizedDescription }
        }
    }
    func refreshDesktop() {
        captureTask?.cancel()
        guard usesDesktop, visible, DesktopCapture.hasPermission, DesktopCapture.sessionUnlocked else {
            if !DesktopCapture.hasPermission || !DesktopCapture.sessionUnlocked { clearDesktop() }
            return
        }
        error = nil
        captureTask = Task { [weak self] in
            do {
                // Coalesce activation/layout notifications and let the previous app finish drawing.
                try await Task.sleep(for:.milliseconds(150))
                guard let self, self.usesDesktop, self.visible else { return }
                let screen = self.view?.window?.screen ?? NSScreen.main
                let capture = DesktopCapture(displayID:screen.map(DesktopCapture.displayID))
                let ids = NSApp.windows.compactMap { WindowCaptureID.from(windowNumber:$0.windowNumber) }
                let snapshot = try await capture.snapshot(excluding:ids)
                try Task.checkCancellation()
                guard self.usesDesktop, self.visible else { return }
                try self.renderer?.setPixelBuffer(snapshot.pixelBuffer,crossfade:true)
                self.usingDemo = false
                self.beginSourceFade()
            } catch {
                guard !Task.isCancelled else { return }
                self?.error = error.localizedDescription
            }
        }
    }
    func clearDesktop() {
        captureTask?.cancel(); captureTask = nil
        guard !usingDemo else { return }
        // Discard captured textures immediately on revocation/lock; never blend stale desktop pixels.
        textureGeneration = UUID()
        laptop.screenMaterial.diffuse.contents = NSColor.black
        renderer?.clearImage()
        do { try renderer?.setImage(ExampleScreen.image(dark:exampleIsDark)) }
        catch { self.error = error.localizedDescription }
        usingDemo = true; sourceFadeStarted = nil; lastTextureDegrees = nil
        updateTexture(degrees: 0)
    }
    func shutdown() { setVisible(false); systemAppearanceObserver = nil; privacyObservers.removeAll(); renderer?.clearImage() }
    private func beginSourceFade() {
        sourceFadeStarted = ProcessInfo.processInfo.systemUptime
        lastTextureDegrees = nil; lastSourceBlend = nil
        startClock()
    }
    private func startClock() {
        guard visible, clock == nil else { return }
        view?.refineWhenStill(false)
        lastTick = ProcessInfo.processInfo.systemUptime
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if let started = self.sourceFadeStarted {
                    let t = min(1,max(0,(now-started)/0.4))
                    self.renderer?.setSourceBlend(t*t*(3-2*t))
                    if t == 1 { self.sourceFadeStarted = nil }
                }
                let dt = max(0,now - self.lastTick); self.lastTick = now
                if let transition = self.lidTransition {
                    self.applyAngle(transition.angle(at:now),at:now)
                    if transition.isComplete(at:now) { self.lidTransition = nil }
                }
                if var spring = self.releaseSpring {
                    self.applyAngle(spring.advance(by:dt),at:now)
                    self.releaseSpring = spring.isComplete ? nil : spring
                }
                if var motion = self.keyboardMotion {
                    self.applyAngle(motion.advance(by:dt),at:now)
                    self.keyboardMotion = motion.isComplete ? nil : motion
                }
                self.shownAngle += (self.angle-self.shownAngle)*(1-exp(-dt/0.018))
                if abs(self.angle-self.shownAngle) < 0.005 { self.shownAngle = self.angle }
                self.laptop.setAngle(self.shownAngle)
                let closingSoon = LidClosureContact.closingSoon(presented:self.shownAngle,target:self.angle,
                    transition:self.lidTransition,at:now)
                if self.closureContact.receive(angle:self.shownAngle,closingSoon:closingSoon) { self.snapSound?.play() }
                let offset = self.floating.frame(angle:self.shownAngle,at:now,enabled:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    resting:self.shownAngle == self.angle && self.lidTransition == nil && self.releaseSpring == nil && self.keyboardMotion == nil)
                let impactOffset = self.impact.frame(angle:self.shownAngle,at:now)
                self.laptop.setFloatingOffset(offset,impactOffset:impactOffset)
                // Audio anticipates closure; dust and chassis weight wait for actual rendered contact.
                if self.visualContact.receive(angle:self.shownAngle) {
                    self.impact.strike()
                    self.view?.showAnvil(at:now)
                }
                self.view?.advanceAnvil(at:now)
                self.updateSwipeHint(at:now)
                let floatPending = self.floating.isWaitingOrFloating
                let frame = self.session.frame(at:now)
                self.updateTexture(degrees:self.effectEnabled ? frame.degrees : 0)
                self.view?.needsDisplay = true
                if frame.phase == .idle && self.shownAngle == self.angle && !floatPending && self.lidTransition == nil && self.releaseSpring == nil && self.keyboardMotion == nil && !self.impact.isActive && self.view?.isAnvilActive != true && self.sourceFadeStarted == nil {
                    self.clock = nil; self.view?.refineWhenStill(true); return
                }
                try? await Task.sleep(for:.milliseconds(ProcessInfo.processInfo.isLowPowerModeEnabled ? 33 : 16))
            }
        }
    }
    private func updateTexture(degrees: Double) {
        guard visible, let renderer else { return }
        guard !textureBusy else { texturePending = true; return }
        guard lastTextureDegrees != degrees || lastSettings != settings || lastSourceBlend != renderer.sourceBlend else { return }
        lastTextureDegrees = degrees; lastSettings = settings; lastSourceBlend = renderer.sourceBlend
        renderer.foldDegrees = degrees; renderer.settings = settings
        textureBusy = true
        let token = textureGeneration
        renderer.renderTexture(width:1536,height:Int(1536/laptop.screenAspectRatio)) { [weak self] result in
            guard let self else { return }
            self.textureBusy = false
            guard self.textureGeneration == token else {
                self.lastTextureDegrees = nil
                self.updateTexture(degrees:self.effectEnabled ? self.session.degrees : 0)
                return
            }
            switch result {
            case .success(let texture):
                SCNTransaction.begin(); SCNTransaction.disableActions = true
                self.laptop.screenMaterial.diffuse.contents = texture
                SCNTransaction.commit()
                self.view?.needsDisplay = true
            case .failure(let error): self.error = error.localizedDescription
            }
            if self.texturePending {
                self.texturePending = false
                self.updateTexture(degrees:self.effectEnabled ? self.session.degrees : 0)
            }
        }
    }
}
