import AppKit
import MetalKit
import DuoGraphics
import DuoCore

final class EffectPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindow {
    let panel: EffectPanel
    let view: MTKView
    let renderer: FoldRenderer
    private var lastDegrees: Double?
    private var lastSettings: FoldSettings?
    var id: CGWindowID { WindowCaptureID.from(windowNumber:panel.windowNumber) ?? 0 }
    var visible: Bool { panel.isVisible }
    init(renderer: FoldRenderer) {
        self.renderer = renderer
        let initialFrame = CGRect(x: 0, y: 0, width: 640, height: 400)
        panel = EffectPanel(contentRect: initialFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.animationBehavior = .none
        view = MTKView(frame: initialFrame, device: renderer.device)
        renderer.configure(view)
        panel.contentView = view
    }
    func show(on screen: NSScreen) {
        lastDegrees = nil; lastSettings = nil
        panel.setFrame(screen.frame, display: false)
        view.frame = CGRect(origin: .zero, size: screen.frame.size)
        view.drawableSize = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                                   height: screen.frame.height * screen.backingScaleFactor)
        view.wantsLayer = true
        view.layer?.contentsScale = screen.backingScaleFactor
        view.layoutSubtreeIfNeeded()
        // Populate the drawable before ordering the panel in front to avoid a black first frame.
        view.draw()
        panel.orderFrontRegardless()
        Diagnostics.record("overlay: frame=\(view.frame), drawable=\(view.drawableSize), window=\(panel.frame), device=\(view.device?.name ?? "nil"), visible=\(panel.isVisible)")
        view.draw()
    }
    func hide() { panel.orderOut(nil); renderer.clearImage() }
    func redraw() {
        guard visible, lastDegrees != renderer.foldDegrees || lastSettings != renderer.settings else { return }
        lastDegrees = renderer.foldDegrees; lastSettings = renderer.settings
        view.draw()
    }
}
