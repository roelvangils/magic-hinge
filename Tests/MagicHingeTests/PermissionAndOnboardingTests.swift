import XCTest
@testable import MagicHinge

final class PermissionAndOnboardingTests: XCTestCase {
    @MainActor func testLaunchNeverPromptsAndRefreshReflectsRevocation() {
        var allowed = true
        var prompts = 0
        let service = PermissionService(preflight: { allowed }, requestAccess: { prompts += 1; return false }, presentSettings: {})
        XCTAssertTrue(service.granted)
        XCTAssertEqual(prompts, 0)
        allowed = false; service.refresh()
        XCTAssertFalse(service.granted)
        XCTAssertEqual(prompts, 0)
        allowed = true; service.refresh()
        XCTAssertTrue(service.granted)
        service.shutdown()
    }
    @MainActor func testDeniedRequestOffersGuidanceAndDoesNotInventPermission() {
        var panels = 0
        let service = PermissionService(preflight: { false }, requestAccess: { true }, presentSettings: { panels += 1 })
        service.request()
        XCTAssertTrue(service.requested)
        XCTAssertFalse(service.granted, "Only preflight establishes current permission, not the request result")
        XCTAssertEqual(panels, 1)
        service.shutdown()
    }
    @MainActor func testResumeSkipAndReopenDoNotGrantPermission() throws {
        let suite = "MagicHinge.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = OnboardingCoordinator(defaults: defaults)
        XCTAssertTrue(first.isPresented); XCTAssertEqual(first.step, .welcome)
        first.go(to: .screenRecording)
        let resumed = OnboardingCoordinator(defaults: defaults)
        XCTAssertEqual(resumed.step, .screenRecording)
        resumed.go(to: .ready); resumed.finish()
        let finished = OnboardingCoordinator(defaults: defaults)
        XCTAssertFalse(finished.isPresented)
        let denied = PermissionService(preflight: { false }, requestAccess: { false }, presentSettings: {})
        XCTAssertFalse(denied.granted)
        finished.reopen()
        XCTAssertTrue(finished.isPresented); XCTAssertEqual(finished.step, .welcome)
        denied.shutdown()
    }
}
