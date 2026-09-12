#if DEBUG
import DuoCore
import AppKit

/// A bounded, click-through compositor experiment. It never captures a screenshot
/// or displays the desktop, and does not participate in authentication.
@MainActor
final class LockScreenProbe {
    private var task: Task<Void, Never>?
    private var panel: EffectPanel?
    var onStatus: ((String) -> Void)?

    func arm() {
        stop()
        onStatus?(L10n.text("Test ready: lock within 2 minutes using Control–Command–Q."))
        Diagnostics.record("lock probe: armed")
        task = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(120)
            while DesktopCapture.sessionUnlocked && Date() < deadline && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { return }
            guard !DesktopCapture.sessionUnlocked else {
                self.onStatus?(L10n.text("Test expired; the screen was not locked.")); self.task = nil; return
            }
            // Let the actual lock screen replace the desktop before showing the test.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !DesktopCapture.sessionUnlocked else { return }
            self.show()
            let end = Date().addingTimeInterval(15)
            while !DesktopCapture.sessionUnlocked && Date() < end && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil); self.panel = nil; self.task = nil
            self.onStatus?(L10n.text("Test finished. Was a blue frame with a blurred background visible in the top left?"))
            Diagnostics.record("lock probe: finished; visual confirmation required")
        }
    }
    private func show() {
        guard let screen = DesktopCapture.builtInScreen else { return }
        let rect = CGRect(x: screen.frame.minX + 36, y: screen.frame.maxY - 230,
                          width: min(560, screen.frame.width - 72), height: 170)
        let panel = EffectPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: rect.size))
        glass.material = .hudWindow; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true; glass.layer?.borderColor = NSColor.systemCyan.cgColor
        glass.layer?.borderWidth = 3; glass.layer?.cornerRadius = 14; glass.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: L10n.text("Magic Hinge · lock-screen test\nDisappears automatically after 15 seconds"))
        label.textColor = .white; label.font = .systemFont(ofSize: 18, weight: .medium)
        label.frame = CGRect(x: 24, y: 45, width: rect.width - 48, height: 80)
        glass.addSubview(label); panel.contentView = glass
        self.panel = panel; panel.orderFrontRegardless()
        Diagnostics.record("lock probe: window ordered; visible=\(panel.isVisible), level=\(panel.level.rawValue)")
    }
    func stop() {
        task?.cancel(); task = nil; panel?.orderOut(nil); panel = nil
    }
}

#endif
