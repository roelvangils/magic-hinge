import AppKit
import SceneKit
import Metal

/// Supersampled rendering with shared mouse and trackpad physics.
public final class SimulationSceneView: SCNView {
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    public var lidNode: SCNNode?
    public var bodyNode: SCNNode?
    public var contactNode: SCNNode?
    public var screenNode: SCNNode?
    public var currentAngle: (() -> Double)?
    public var onAngleChanged: ((Double) -> Void)?
    public var onToggleLid: ((Bool) -> Void)?
    public var onKeyboardStep: ((Double) -> Void)?
    public var onLidEndpoint: ((Double, Bool) -> Void)?
    public var onGestureBegan: (() -> Void)?
    public var onGestureReleased: ((Double) -> Void)?
    private var scrollPhysics = LidScrollPhysics()
    private var scrollEndTask: Task<Void,Never>?
    private var dragging = false
    private var hasDragged = false
    private var lastDragY: CGFloat = 0
    private var scrollClaimed: Bool?
    private var swallowMomentum = false
    private var pointerTracking: NSTrackingArea?
    private var swipeHint: SwipeAffordanceView?
    private var keyboardMonitor: Any?
    private let anvilBurst = AnvilBurstView(frame:.zero)

    public var isAnvilActive: Bool { anvilBurst.isActive }
    public func cancelAnvil() { anvilBurst.cancel() }
    public func advanceAnvil(at time: Double) { anvilBurst.advance(at:time) }
    public func showAnvil(at time: Double) {
        guard !reduceMotion, let contactNode else { return }
        if anvilBurst.superview == nil { addSubview(anvilBurst) }
        anvilBurst.frame = bounds
        let box = contactNode.boundingBox
        func project(_ x: CGFloat) -> CGPoint {
            let p = projectPoint(contactNode.convertPosition(SCNVector3(x,box.min.y,box.max.z),to:nil))
            return CGPoint(x:p.x,y:p.y)
        }
        // The overlay uses AppKit's upward Y axis, independent of the hit-region margin.
        let a = project(box.min.x), b = project(box.max.x)
        anvilBurst.begin(left:a.x < b.x ? a : b,right:a.x < b.x ? b : a,at:time)
    }

    /// View-space hit region, deliberately independent of SceneKit hit testing/camera controls.
    public var lidDragRect: CGRect {
        guard let lidNode else { return .null }
        var points: [CGPoint] = []
        for node in [lidNode, bodyNode].compactMap({ $0 }) {
            let box = node.boundingBox
            for x in [box.min.x, box.max.x] {
                for y in [box.min.y, box.max.y] {
                    for z in [box.min.z, box.max.z] {
                        let p = projectPoint(node.convertPosition(SCNVector3(x,y,z), to:nil))
                        points.append(CGPoint(x:p.x, y:isFlipped ? bounds.height-p.y : p.y))
                    }
                }
            }
        }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        let margin = max(32, (maxX-minX)*0.075)
        return CGRect(x:minX, y:minY, width:maxX-minX, height:maxY-minY)
            .insetBy(dx:-margin,dy:-margin).intersection(bounds)
    }

    /// Window-scoped keys also work before the user first clicks the model.
    private func installKeyboardMonitor() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
        guard window != nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  window.isKeyWindow, !self.isHiddenOrHasHiddenAncestor else { return event }
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return event }
            if window.firstResponder is NSControl || window.attachedSheet != nil { return event }
            return self.handleLidKey(event) ? nil : event
        }
    }
    deinit {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }
    @discardableResult
    func handleLidKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return false }
        switch event.keyCode {
        case 126, 125, 116, 121: // Up, Down, Page Up, Page Down
            guard let onKeyboardStep else { return false }
            onKeyboardStep(event.keyCode == 126 || event.keyCode == 116 ? 5 : -5)
            return true
        case 115, 119: // Home, End: explicit destinations, never toggles.
            guard let onLidEndpoint else { return false }
            if !event.isARepeat { onLidEndpoint(event.keyCode == 115 ? 90 : 0,event.modifierFlags.contains(.shift)) }
            return true
        case 49, 36, 76: // Space, Return, keypad Enter
            guard let onToggleLid else { return false }
            if !event.isARepeat { onToggleLid(event.modifierFlags.contains(.shift)) }
            return true
        default: return false
        }
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from:nil)
        guard lidDragRect.contains(p) else { super.mouseDown(with:event); return }
        if event.clickCount == 2 {
            scrollEndTask?.cancel(); scrollEndTask = nil; scrollClaimed = nil; scrollPhysics.reset()
            dragging = false; onToggleLid?(event.modifierFlags.contains(.shift)); return
        }
        scrollEndTask?.cancel(); scrollEndTask = nil
        scrollPhysics.begin(at:event.timestamp); scrollClaimed = nil
        onGestureBegan?()
        dragging = true; hasDragged = false
        lastDragY = p.y
        NSCursor.closedHand.set()
    }
    public override func mouseDragged(with event: NSEvent) {
        guard dragging else { super.mouseDragged(with:event); return }
        let y = convert(event.locationInWindow, from:nil).y
        let delta = (y-lastDragY)*(isFlipped ? -1 : 1)
        if delta != 0 { hasDragged = true }
        changeAngleWithVelocity(by:delta,at:event.timestamp)
        lastDragY = y
    }
    public override func mouseUp(with event: NSEvent) {
        guard dragging else { super.mouseUp(with:event); return }
        dragging = false
        let velocity = scrollPhysics.releaseVelocity(at:event.timestamp)
        scrollPhysics.reset()
        if hasDragged { onGestureReleased?(velocity) }
        hasDragged = false
        updateCursor(at:convert(event.locationInWindow, from:nil))
    }
    public override func scrollWheel(with event: NSEvent) {
        if !event.momentumPhase.isEmpty {
            if !swallowMomentum { super.scrollWheel(with:event) }
            if event.momentumPhase.contains(.ended) { swallowMomentum = false }
            return
        }
        let phased = !event.phase.isEmpty
        if event.phase.contains(.began) || scrollClaimed == nil {
            scrollEndTask?.cancel(); scrollEndTask = nil; scrollPhysics.begin(at:event.timestamp)
            scrollClaimed = lidDragRect.contains(convert(event.locationInWindow, from:nil))
            swallowMomentum = scrollClaimed == true
            if scrollClaimed == true {
                onGestureBegan?()
            }
        }
        let claimed = scrollClaimed == true
        if claimed {
            let delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? 1 : -1)
            let motion = delta * (event.hasPreciseScrollingDeltas ? -1 : 10)
            changeAngleWithVelocity(by:motion,at:event.timestamp)
            if event.phase.contains(.cancelled) {
                finishScroll(at:event.timestamp,cancelled:true)
            } else if event.phase.contains(.ended) {
                finishScroll(at:event.timestamp,cancelled:false)
            } else if !phased {
                // Mouse wheels / devices without gesture phases finish after a short quiet interval.
                scrollEndTask?.cancel()
                let timestamp = event.timestamp
                scrollEndTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for:.milliseconds(110)) } catch { return }
                    self?.finishScroll(at:timestamp,cancelled:false)
                }
            }
        } else {
            super.scrollWheel(with:event)
            if !phased || event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollClaimed = nil }
        }
    }
    private func finishScroll(at time: Double, cancelled: Bool) {
        let velocity = scrollPhysics.releaseVelocity(at:time)
        scrollEndTask?.cancel(); scrollEndTask = nil
        scrollPhysics.reset(); scrollClaimed = nil
        if !cancelled { onGestureReleased?(velocity) }
    }
    public override func smartMagnify(with event: NSEvent) {
        guard lidDragRect.contains(convert(event.locationInWindow,from:nil)) else {
            nextResponder?.smartMagnify(with:event); return
        }
        scrollEndTask?.cancel(); scrollEndTask = nil; scrollClaimed = nil; scrollPhysics.reset()
        // AppKit's native two-finger double tap (Smart Zoom).
        onToggleLid?(event.modifierFlags.contains(.shift))
    }
    private func changeAngleWithVelocity(by delta: CGFloat, at time: Double) {
        guard delta != 0, let angle = currentAngle?() else { return }
        let degrees = Double(delta/max(180,bounds.height*0.65))*130
        let accelerated = scrollPhysics.displacement(degrees,at:time)
        onAngleChanged?(min(130,max(0,angle+accelerated)))
    }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect:.zero, options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect], owner:self)
        addTrackingArea(area); pointerTracking = area
    }
    public override func mouseMoved(with event: NSEvent) { updateCursor(at:convert(event.locationInWindow,from:nil)) }
    public override func mouseEntered(with event: NSEvent) { updateCursor(at:convert(event.locationInWindow,from:nil)) }
    public override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }
    private func updateCursor(at point: CGPoint) {
        (dragging ? NSCursor.closedHand : lidDragRect.contains(point) ? NSCursor.openHand : NSCursor.arrow).set()
    }
    public func setSwipeHintVisible(_ visible: Bool) {
        if visible && swipeHint == nil {
            let hint = SwipeAffordanceView(frame:CGRect(x:0,y:0,width:74,height:100))
            addSubview(hint); swipeHint = hint
        }
        swipeHint?.setAnimating(visible,pointsDown:(currentAngle?() ?? 0) >= 45)
        positionSwipeHint()
    }
    public func positionSwipeHint() {
        guard let hint = swipeHint, !hint.isHidden, let lidNode else { return }
        let opened = (currentAngle?() ?? 0) >= 45
        let anchor: SCNVector3
        if opened, let screenNode {
            let box = screenNode.boundingBox
            let center = SCNVector3((box.min.x+box.max.x)/2,
                                    (box.min.y+box.max.y)/2, (box.min.z+box.max.z)/2)
            anchor = screenNode.convertPosition(center,to:nil)
        } else {
            // The physical rear hinge sits at the top edge of the closed laptop.
            // Hit-test bounds deliberately include a large margin and must not position the hint.
            anchor = lidNode.convertPosition(SCNVector3Zero,to:nil)
        }
        let p = projectPoint(anchor)
        let y = isFlipped ? bounds.height-p.y : p.y
        let originY = opened ? y-50 : (isFlipped ? y-106 : y+6)
        hint.setFrameOrigin(CGPoint(x:p.x-37,y:originY))
    }
    public static func antialiasingMode(for device: MTLDevice?) -> SCNAntialiasingMode {
        if device?.supportsTextureSampleCount(8) == true { return .multisampling8X }
        if device?.supportsTextureSampleCount(4) == true { return .multisampling4X }
        if device?.supportsTextureSampleCount(2) == true { return .multisampling2X }
        return .none
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installKeyboardMonitor()
        if window == nil { cancelAnvil(); swipeHint?.setAnimating(false); scrollEndTask?.cancel(); scrollEndTask = nil; scrollClaimed = nil; scrollPhysics.reset() }
        synchronizeResolution()
    }
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeResolution()
    }
    public override func layout() {
        super.layout()
        synchronizeResolution()
        positionSwipeHint()
        anvilBurst.frame = bounds
    }
    public static func renderScale(backingScale: CGFloat, size: CGSize) -> CGFloat {
        // Render at twice the physical display resolution, then downsample the layer.
        // Bound oversized windows to avoid unbounded multisample render targets.
        let desired = backingScale*2
        let dimensionLimit = 4096/max(1,max(size.width,size.height))
        let pixelLimit = sqrt(8_000_000/max(1,size.width*size.height))
        return max(backingScale,min(desired,dimensionLimit,pixelLimit))
    }
    private func synchronizeResolution() {
        let scale = Self.renderScale(backingScale:window?.backingScaleFactor ?? 1,size:bounds.size)
        if layer?.contentsScale != scale {
            layer?.contentsScale = scale
            layer?.minificationFilter = .linear
            layer?.magnificationFilter = .linear
            needsDisplay = true
        }
    }
    public func refineWhenStill(_ enabled: Bool) {
        // SceneKit refines asynchronously, then stops. Continuous rendering stays disabled.
        isJitteringEnabled = enabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
