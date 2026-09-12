import AppKit
import DuoCore
import DuoGraphics

/// One owner balances the overlay, display clock and cursor across every exit path.
@MainActor
final class DesktopEffect {
    let overlay: OverlayWindow
    let clock = DisplayClock()
    private let cursor = EffectCursor()
    init(settings: FoldSettings) throws {
        let renderer = try FoldRenderer()
        renderer.settings = settings
        renderer.onDebug = { Diagnostics.record($0) }
        overlay = OverlayWindow(renderer: renderer)
    }
    func setCursorHidden(_ hidden: Bool) { cursor.setHidden(hidden) }
    func stop() { clock.stop(); cursor.setHidden(false); overlay.hide() }
}
