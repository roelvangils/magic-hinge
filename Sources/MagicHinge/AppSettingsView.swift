import SwiftUI
import DuoCore
import DuoSimulation

enum AppAppearance: String, CaseIterable {
    case auto, dark, light
    @MainActor func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named:.darkAqua)
        case .light: NSApp.appearance = NSAppearance(named:.aqua)
        }
    }
    var title: String { L10n.text(rawValue.capitalized) }
}

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulator: SimulatorModel
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject var updater: UpdaterService
    @ObservedObject var crashReporting: CrashReportingService
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearance = AppAppearance.auto
    var body: some View {
        TabView {
            Form {
                Picker(L10n.text("Appearance"), selection:$appearance) {
                    ForEach(AppAppearance.allCases,id:\.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Section {
                    Toggle(L10n.text("Enable desktop effect"),isOn:$model.enabled)
                    Toggle(L10n.text("Hide mouse cursor during the effect"),isOn:$model.settings.hideCursor)
                }
                Section {
                    Toggle(L10n.text("Automatically check for updates"), isOn: $updater.automaticallyChecksForUpdates)
                    Button(L10n.text("Check for Updates…")) { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                    Button(L10n.text("Show welcome guide…")) { onboarding.reopen(); openWindow(id: "main") }
                }
                if crashReporting.isConfigured {
                    Section {
                        Toggle(L10n.text("Send crash reports"), isOn: $crashReporting.enabled)
                        Text(L10n.text("Help improve Magic Hinge by sending crash details to Sentry. Reports include app and macOS versions, device information and stack traces. Screen images are never included."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L10n.text("Animate on")) {
                    Toggle(L10n.text("Opening the lid"),isOn:$model.settings.animateOnOpen)
                    Toggle(L10n.text("Closing the lid"),isOn:$model.settings.animateOnClose)
                }
                if !model.permission {
                    Button(L10n.text("Grant screen access…")) { model.requestPermission() }
                }
            }.formStyle(.grouped)
                .tabItem { Label(L10n.text("General"),systemImage:"gearshape") }
            Form {
                Section { EffectTuningControls(settings:$model.settings) }
                Section {
                    Toggle(L10n.text("Desktop"),isOn:Binding(get:{simulator.usesDesktop},set:{simulator.setDesktopEnabled($0)}))
                    Toggle(L10n.text("Follow physical hinge"),isOn:$simulator.followSensor)
                    Toggle(L10n.text("Show effect in simulator"),isOn:$simulator.effectEnabled)
                }
            }.formStyle(.grouped)
                .tabItem { Label(L10n.text("Effect"),systemImage:"camera.filters") }
            Form {
                Picker(L10n.text("Model"),selection:Binding(get:{simulator.configuration.family},set:{simulator.select(family:$0)})) {
                    ForEach(MacBookFamily.allCases,id:\.self) { Text($0.title).tag($0) }
                }
                Picker(L10n.text("Size"),selection:Binding(get:{simulator.configuration.size},set:{simulator.select(size:$0)})) {
                    ForEach(simulator.configuration.family.sizes,id:\.self) { Text("\($0)″").tag($0) }
                }
                Picker(L10n.text("Colour"),selection:Binding(get:{simulator.colorChoice},set:{simulator.selectColor($0)})) {
                    ForEach(simulator.configuration.family.colorChoices,id:\.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                if simulator.detectedConfiguration != nil {
                    Button(L10n.text("This Mac")) { simulator.useDetectedModel() }
                }
                if let error = simulator.modelError { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
                .tabItem { Label("MacBook",systemImage:"laptopcomputer") }
        }
        .padding(16)
        .frame(width:500,height:560)
        .onAppear { appearance.apply() }
        .onChange(of:appearance) { _,value in value.apply() }
    }
}
