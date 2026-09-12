import SwiftUI
import DuoCore

struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var model: AppModel
    @ObservedObject var permission: PermissionService
    // Same controller, adapters, physics and renderer as the main window, with a memory-only demo source.
    @StateObject private var demo = SimulatorModel(demoOnly: true)
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 76, height: 76).accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                ForEach(OnboardingCoordinator.Step.allCases, id: \.rawValue) { step in
                    Capsule().fill(step == coordinator.step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 36, height: 4)
                }
            }.accessibilityLabel(L10n.format("Step %d of 3", coordinator.step.rawValue + 1))
            Group {
                switch coordinator.step {
                case .welcome:
                    Text(L10n.text("Tilt your MacBook lid and watch your desktop move like frosted glass. Try dragging the laptop below."))
                    LaptopSceneView(model: demo, onManualAngle: demo.setAngle,
                        onToggleLid: { demo.toggleLid(slowMotion: $0) }, onKeyboardStep: demo.stepLid,
                        onLidEndpoint: { demo.moveLid(to: $0, slowMotion: $1) },
                        onGestureBegan: demo.beginGesture, onGestureReleased: { demo.releaseGesture(velocity: $0) })
                        .frame(height: 210)
                        .onAppear { demo.setVisible(true); demo.moveLid(to: 90) }
                        .onDisappear { demo.setVisible(false) }
                case .screenRecording:
                    Image(systemName: "rectangle.inset.filled.and.person.filled").font(.system(size: 48)).accessibilityHidden(true)
                    Text(L10n.text("Screen Recording lets Magic Hinge briefly capture your display for the effect. Images stay in memory on your Mac and are never saved or uploaded."))
                    Text(L10n.text("You can skip this and use the simulator with the example image."))
                    if permission.granted {
                        Label(L10n.text("Screen access granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(L10n.text("Grant screen access…")) { permission.request() }
                        if permission.requested {
                            Text(L10n.text("Access is still unavailable. Enable Magic Hinge in System Settings, then return here. If macOS asks, quit and reopen the app."))
                            Button(L10n.text("Open System Settings…")) { permission.openSettings() }
                        }
                    }
                case .ready:
                    Label(L10n.text(permission.granted ? "Screen access granted" : "Simulator available without screen access"), systemImage: permission.granted ? "checkmark.circle.fill" : "play.circle")
                    Label(model.angle.map { L10n.format("Hinge: %d°", Int($0)) } ?? model.sensorMessage, systemImage: "laptopcomputer")
                    Text(L10n.text("The effect stops when you hold the lid still. You can also pause it from the menu bar, or press Escape while Magic Hinge is active."))
                    Button(L10n.text("Start desktop effect")) { model.enabled = true; coordinator.finish() }
                        .disabled(!permission.granted || model.angle == nil || !model.hasBuiltInScreen)
                }
            }.frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack {
                if coordinator.step != .welcome {
                    Button(L10n.text("Back")) { coordinator.go(to: coordinator.step == .ready ? .screenRecording : .welcome) }
                }
                Spacer()
                Button(L10n.text(coordinator.step == .ready ? "Use simulator only" : coordinator.step == .screenRecording && !permission.granted ? "Skip for now" : "Continue")) {
                    switch coordinator.step {
                    case .welcome: coordinator.go(to: .screenRecording)
                    case .screenRecording: coordinator.go(to: .ready)
                    case .ready: model.enabled = false; coordinator.finish()
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32).frame(width: 560, height: 590)
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in demo.setVisible(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if coordinator.step == .welcome { demo.setVisible(true) }
        }
        .onDisappear { demo.shutdown() }
    }
    private var title: String {
        switch coordinator.step {
        case .welcome: L10n.text("Welcome to Magic Hinge")
        case .screenRecording: L10n.text("Your desktop, in motion")
        case .ready: L10n.text("Ready when you are")
        }
    }
}
