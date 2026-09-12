import DuoCore
import AppKit
import ScreenCaptureKit
import CoreVideo

struct DesktopSnapshot {
    let pixelBuffer: CVPixelBuffer
    let displayID: CGDirectDisplayID
}

@MainActor
final class DesktopCapture {
    static var sessionUnlocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session[kCGSessionOnConsoleKey as String] as? Bool == true)
            && (session["CGSSessionScreenIsLocked"] as? Bool != true)
    }
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    static var builtInScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
    }
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    private let requestedDisplayID: CGDirectDisplayID?
    init(displayID: CGDirectDisplayID? = nil) { requestedDisplayID = displayID }
    private var targetScreen: NSScreen? {
        if let id = requestedDisplayID { return NSScreen.screens.first { Self.displayID($0) == id } }
        return Self.builtInScreen
    }
    private struct Context {
        let displayID: CGDirectDisplayID
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }
    private var context: Context?
    private var preparation: Task<Context, Error>?
    private var generation = UUID()

    func invalidate() { generation = UUID(); preparation?.cancel(); preparation = nil; context = nil }
    func prepare(excluding windowIDs: [CGWindowID]) async throws {
        guard Self.hasPermission else { throw CaptureError.permissionRequired }
        guard Self.sessionUnlocked else { throw CaptureError.sessionLocked }
        guard let screen = targetScreen else { throw CaptureError.noBuiltInScreen }
        let id = Self.displayID(screen)
        if context?.displayID == id { return }
        if let preparation {
            let token = generation
            let ready = try await preparation.value
            guard generation == token else { throw CancellationError() }
            context = ready
            return
        }
        let token = generation
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        let preparation = Task { @MainActor in
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noBuiltInScreen }
            let excluded = content.windows.filter { windowIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            filter.includeMenuBar = true
            let configuration = SCStreamConfiguration()
            configuration.width = width; configuration.height = height
            configuration.showsCursor = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.captureResolution = .best
            configuration.scalesToFit = true
            return Context(displayID: id, filter: filter, configuration: configuration)
        }
        self.preparation = preparation
        do {
            let context = try await preparation.value
            guard generation == token else { throw CancellationError() }
            self.context = context; self.preparation = nil
        } catch {
            if generation == token { self.preparation = nil }
            throw error
        }
    }
    func snapshot(excluding windowIDs: [CGWindowID]) async throws -> DesktopSnapshot {
        try await prepare(excluding: windowIDs)
        try Task.checkCancellation()
        let token = generation
        guard let context, let screen = targetScreen, Self.displayID(screen) == context.displayID else {
            throw CaptureError.noBuiltInScreen
        }
        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: context.filter, configuration: context.configuration)
        guard Self.hasPermission else { throw CaptureError.permissionRequired }
        guard Self.sessionUnlocked else { throw CaptureError.sessionLocked }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw CaptureError.noPixels }
        return DesktopSnapshot(pixelBuffer: buffer, displayID: context.displayID)
    }
    enum CaptureError: LocalizedError {
        case noBuiltInScreen, noPixels, sessionLocked, permissionRequired
        var errorDescription: String? {
            switch self {
            case .permissionRequired: L10n.text("Screen access required")
            case .noBuiltInScreen: L10n.text("Open the MacBook display to use the effect.")
            case .sessionLocked: L10n.text("The effect resumes after unlocking.")
            case .noPixels: L10n.text("The screen capture contains no pixel buffer.")
            }
        }
    }
}
