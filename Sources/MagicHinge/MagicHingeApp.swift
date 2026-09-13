import SwiftUI
import DuoHardware
import DuoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MagicHingeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    @StateObject private var onboarding = OnboardingCoordinator()
    @StateObject private var updater = UpdaterService()
    @StateObject private var crashReporting: CrashReportingService
    @StateObject private var simulator = SimulatorModel(demoOnly: CommandLine.arguments.contains("--example-image"))
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--sentry-smoke-test") {
            CrashReportingService.runSmokeTest()
        }
        #endif
        if CommandLine.arguments.contains("--sensor-trace") {
            let sensor = HingeSensor()
            let recorder = SensorTraceRecorder()
            print("seconds,raw,filtered,deformation,phase")
            sensor.start { recorder.receive($0) }
            _ = DispatchSemaphore(value: 0).wait(timeout: .now() + 60)
            sensor.stop()
            exit(0)
        }
        if CommandLine.arguments.contains("--sensor-probe") {
            let sensor = HingeSensor()
            let done = DispatchSemaphore(value: 0)
            sensor.start { reading in
                let result: [String: Any] = ["angle": reading.angle as Any? ?? NSNull(), "status": reading.message]
                if let json = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                   let line = String(data: json, encoding: .utf8) { print(line) }
                done.signal()
            }
            let success = done.wait(timeout: .now() + 5) == .success
            sensor.stop()
            exit(success ? 0 : 1)
        }
        let reporting = CrashReportingService()
        _crashReporting = StateObject(wrappedValue: reporting)
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        Window("Magic Hinge", id: "main") {
            ContentView(model: model, simulator: simulator, simulatorSuspended: onboarding.isPresented)
                .onAppear { if onboarding.isPresented { model.enabled = false } }
                .onChange(of:onboarding.isPresented) { _,shown in if shown { model.enabled = false } }
                .sheet(isPresented: $onboarding.isPresented) {
                    OnboardingView(coordinator: onboarding, model: model, permission: model.permissionService)
                        .interactiveDismissDisabled()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown(); simulator.shutdown() }
        }
        .defaultSize(width:1120,height:772)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing:.newItem) {}
            AboutCommands()
            CommandGroup(after: .appInfo) {
                Button(L10n.text("Check for Updates…")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        Window(L10n.text("About Magic Hinge"),id:"about") { AboutView() }
            .windowResizability(.contentSize)
            .defaultPosition(.center)
            .windowStyle(.hiddenTitleBar)
        Settings { AppSettingsView(model:model, simulator:simulator, onboarding:onboarding, updater:updater, crashReporting:crashReporting) }
        MenuBarExtra("Magic Hinge", systemImage: "laptopcomputer") {
            MenuContent(model: model)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(model.angle.map { L10n.format("Hinge: %d°", Int($0)) } ?? L10n.text("Sensor unavailable"))
        Text(model.status)
        Divider()
        Toggle(L10n.text("Effect enabled"), isOn: $model.enabled)
        Button(L10n.text("Open Magic Hinge")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(L10n.text("Stop effect")) { model.emergencyStop() }.keyboardShortcut(".", modifiers: [.command, .shift])
        Divider()
        Button(L10n.text("Quit Magic Hinge")) { model.shutdown(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// A bounded diagnostic trace; mutable state is protected even if the callback executor changes.
private final class SensorTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var filter = HingeMotionFilter()
    private var session = FoldSession()
    private let start = ProcessInfo.processInfo.systemUptime
    func receive(_ reading: HingeSensor.Reading) {
        lock.lock(); defer { lock.unlock() }
        let angle = filter.receive(angle: reading.angle, at: reading.timestamp)
        _ = session.receive(angle: angle, at: reading.timestamp)
        let frame = session.frame(at: reading.timestamp)
        print(String(format: "%.4f,%.1f,%.1f,%.4f,%@", reading.timestamp - start,
            reading.angle ?? -1, angle ?? -1, frame.degrees, String(describing: frame.phase)))
        fflush(stdout)
    }
}
