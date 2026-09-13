import XCTest
import Sentry
@testable import MagicHinge

final class CrashReportingTests: XCTestCase {
    @MainActor func testConsentControlsSDKLifecycleAndRevokedEventsAreDropped() throws {
        let suite = "MagicHinge.crash-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var starts = 0, stops = 0
        var captured: Options?
        let service = CrashReportingService(defaults: defaults, dsn: "https://public@example.com/123",
            startSDK: { starts += 1; captured = $0 }, stopSDK: { stops += 1 })
        XCTAssertFalse(service.enabled)
        XCTAssertEqual(starts, 0, "No SDK or network activity before consent")
        service.enabled = true
        service.enabled = true
        XCTAssertEqual(starts, 1)
        let options = try XCTUnwrap(captured)
        XCTAssertFalse(options.sendDefaultPii)
        XCTAssertFalse(options.enableMemoryIntrospection)
        XCTAssertFalse(options.enableAutoSessionTracking)
        XCTAssertFalse(options.enableAutoPerformanceTracing)
        XCTAssertFalse(options.enableNetworkTracking)
        XCTAssertFalse(options.enableLogs)
        XCTAssertEqual(options.maxBreadcrumbs, 0)
        let event = Event(level: .error)
        event.user = User(userId: "must-not-leave-device")
        event.extra = ["private": "value"]
        event.context = ["app": ["device_app_hash": "identifier", "app_version": "1"],
                         "culture": ["timezone": "private"], "device": ["model": "Mac", "id": "private"]]
        XCTAssertNotNil(options.beforeSend?(event))
        XCTAssertNil(event.user)
        XCTAssertNil(event.extra)
        XCTAssertNil(event.context?["culture"])
        XCTAssertNil(event.context?["app"]?["device_app_hash"])
        XCTAssertNil(event.context?["device"]?["id"])
        XCTAssertEqual(event.context?["device"]?["model"] as? String, "Mac")
        service.enabled = false
        XCTAssertEqual(stops, 1)
        XCTAssertNil(options.beforeSend?(Event(level: .error)))
        XCTAssertFalse(defaults.bool(forKey: CrashReportingService.preferenceKey))
    }

    @MainActor func testMissingOrMalformedDSNDoesNotStartSDK() throws {
        let suite = "MagicHinge.crash-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: CrashReportingService.preferenceKey)
        for dsn in [nil, "", "http://public@example.com/123", "https://example.com/123",
                    "https://public:secret@example.com/123", "https://public@example.com/not-a-project"] {
            let service = CrashReportingService(defaults: defaults, dsn: dsn,
                startSDK: { _ in XCTFail("Invalid DSN started Sentry") }, stopSDK: {})
            XCTAssertFalse(service.isConfigured)
        }
    }
}
