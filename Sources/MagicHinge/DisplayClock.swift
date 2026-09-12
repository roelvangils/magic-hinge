import AppKit
import QuartzCore

/// A display-synchronized clock, active only while an overlay is visible.
@MainActor
final class DisplayClock: NSObject {
    private var link: CADisplayLink?
    private var screenMaximum: Float = 120
    private var powerObserver: NSObjectProtocol?
    var onFrame: ((TimeInterval) -> Void)?
    override init() {
        super.init()
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRate() }
        }
    }
    func start(view: NSView, screen: NSScreen) {
        stop()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        screenMaximum = Float(min(120, max(30, screen.maximumFramesPerSecond)))
        self.link = link
        updateRate()
        link.add(to: .main, forMode: .common)
    }
    private func updateRate() {
        guard let link else { return }
        let maximum = min(screenMaximum, ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 120)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: maximum, maximum: maximum, preferred: maximum)
        Diagnostics.record("display clock: requested \(Int(maximum)) Hz")
    }
    @objc private func tick(_ link: CADisplayLink) {
        onFrame?(ProcessInfo.processInfo.systemUptime)
    }
    deinit { if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) } }
    func stop() { link?.invalidate(); link = nil }
}
