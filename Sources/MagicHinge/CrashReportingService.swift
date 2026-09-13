import Foundation
import Combine
import Sentry

/// Crash reporting is opt-in and separate from desktop capture and the render loop.
@MainActor
final class CrashReportingService: ObservableObject {
    static let preferenceKey = "sendCrashReports"
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.preferenceKey)
            reconcile()
        }
    }
    let isConfigured: Bool
    private let defaults: UserDefaults
    private let dsn: String?
    private let startSDK: (Options) -> Void
    private let stopSDK: () -> Void
    private var started = false

    init(defaults: UserDefaults = .standard,
         dsn: String? = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
         startSDK: @escaping (Options) -> Void = { SentrySDK.start(options: $0) },
         stopSDK: @escaping () -> Void = { SentrySDK.close() }) {
        self.defaults = defaults
        self.dsn = Self.validDSN(dsn)
        self.isConfigured = self.dsn != nil
        self.startSDK = startSDK
        self.stopSDK = stopSDK
        self.enabled = defaults.bool(forKey: Self.preferenceKey)
        reconcile()
    }

    #if DEBUG
    /// Explicit developer smoke test; never runs during an ordinary launch.
    static func runSmokeTest() -> Never {
        guard let dsn = validDSN(Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String) else {
            fputs("Sentry DSN is not configured in this app bundle.\n", stderr)
            exit(2)
        }
        let suite = "MagicHinge.SentrySmokeTest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: preferenceKey)
        let configuration = options(dsn: dsn, defaults: defaults)
        configuration.environment = "integration-test"
        SentrySDK.start(options: configuration)
        let id = SentrySDK.capture(message: "Magic Hinge Sentry integration test")
        SentrySDK.flush(timeout: 10)
        SentrySDK.close()
        defaults.removePersistentDomain(forName: suite)
        print("Sentry test event: \(id.sentryIdString)")
        exit(0)
    }
    #endif

    static func validDSN(_ value: String?) -> String? {
        guard let value, let url = URLComponents(string: value),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              let key = url.user, !key.isEmpty, url.password == nil,
              url.query == nil, url.fragment == nil,
              let project = url.path.split(separator: "/").last,
              project.allSatisfy({ $0.isNumber }) else { return nil }
        return value
    }

    private func reconcile() {
        if enabled, let dsn, !started {
            startSDK(Self.options(dsn: dsn, defaults: defaults))
            started = true
        } else if !enabled, started {
            stopSDK()
            started = false
        }
    }

    static func options(dsn: String, defaults: UserDefaults) -> Options {
        let options = Options()
        options.dsn = dsn
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleID = Bundle.main.bundleIdentifier ?? "be.elevenways.MacBookDuo"
        let version = info["CFBundleShortVersionString"] as? String ?? "development"
        let build = info["CFBundleVersion"] as? String ?? "0"
        options.releaseName = "\(bundleID)@\(version)+\(build)"
        options.dist = build
        options.environment = info["SentryEnvironment"] as? String ?? "development"
        options.debug = false
        options.sendDefaultPii = false
        options.enableMemoryIntrospection = false
        options.enableAutoSessionTracking = false
        options.enableAppHangTracking = false
        options.enableAutoPerformanceTracing = false
        options.tracesSampleRate = 0
        options.enableSwizzling = false
        options.enableNetworkTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableAutoBreadcrumbTracking = false
        options.maxBreadcrumbs = 0
        options.tracePropagationTargets = []
        options.enableLogs = false
        options.enableMetrics = false
        options.enableMetricKit = false
        // These reports need stack traces, not user identity, network requests,
        // arbitrary log values or UI interaction history.
        options.beforeSend = { event in
            guard defaults.bool(forKey: preferenceKey) else { return nil }
            event.user = nil
            event.request = nil
            event.extra = nil
            event.breadcrumbs = nil
            event.tags = nil
            let allowed: [String: Set<String>] = [
                "os": ["name", "version", "build", "kernel_version"],
                "device": ["arch", "family", "model", "memory_size", "processor_count", "simulator"],
                "app": ["app_identifier", "app_name", "app_version", "app_build"]
            ]
            event.context = (event.context ?? [:]).reduce(into: [:]) { result, entry in
                if let keys = allowed[entry.key] {
                    result[entry.key] = entry.value.filter { keys.contains($0.key) }
                }
            }
            for image in event.debugMeta ?? [] {
                if let path = image.codeFile { image.codeFile = (path as NSString).lastPathComponent }
            }
            return event
        }
        return options
    }
}
