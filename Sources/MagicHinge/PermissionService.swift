import AppKit
import Combine
import PermissionFlow
import PermissionFlowScreenRecordingStatus

/// Onboarding completion is a preference; only a fresh system preflight grants access.
@MainActor
final class PermissionService: ObservableObject {
    @Published private(set) var granted: Bool
    @Published private(set) var requested = false
    private let preflight: () -> Bool
    private let requestAccess: () -> Bool
    private let presentSettings: (() -> Void)?
    private let guidance: PermissionFlowController
    private var activation: AnyCancellable?

    init(preflight: @escaping () -> Bool = {
        ScreenRecordingPermissionStatusProvider().authorizationState() == .granted
    }, requestAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }, presentSettings: (() -> Void)? = nil) {
        self.presentSettings = presentSettings
        self.preflight = preflight
        self.requestAccess = requestAccess
        granted = preflight()
        PermissionFlowScreenRecordingStatus.register()
        guidance = PermissionFlow.makeController(configuration: .init(promptForAccessibilityTrust: false))
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() { granted = preflight(); if granted { guidance.closePanel() } }
    func request() {
        requested = true
        _ = requestAccess()
        refresh()
        if !granted { openSettings() }
    }
    func openSettings() { if let presentSettings { presentSettings() } else { guidance.authorize(pane: .screenRecording) } }
    func shutdown() { activation = nil; guidance.closePanel() }
}
