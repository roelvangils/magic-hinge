import SwiftUI
import Combine
import SceneKit
import MetalKit
import DuoCore
import DuoGraphics
import DuoSimulation

struct SimulatorView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var model: SimulatorModel
    var suspended = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var playing = false
    private var animatePreview: Bool { playing && scenePhase == .active && !appModel.effectActive && !suspended }
    private var content: some View {
        VStack(spacing:0) {
            HStack(alignment:.firstTextBaseline) {
                Text("Magic Hinge").font(.system(size:26,weight:.semibold,design:.rounded))
                Spacer()
                SettingsLink { Image(systemName:"gearshape").font(.system(size:18,weight:.medium)).frame(width:28,height:28) }
                    .modifier(LiquidGlassButtons(circular:true))
                    .accessibilityLabel(L10n.text("Settings"))
            }.padding(24)
            ZStack {
                LaptopSceneView(model:model, onManualAngle: { angle in
                    playing = false; model.followSensor = false; model.setAngle(angle)
                }, onToggleLid: { slowMotion in
                    playing = false; model.followSensor = false; model.toggleLid(slowMotion:slowMotion)
                }, onKeyboardStep: { delta in
                    playing = false; model.followSensor = false; model.stepLid(by:delta)
                }, onLidEndpoint: { destination, slowMotion in
                    playing = false; model.followSensor = false; model.moveLid(to:destination,slowMotion:slowMotion)
                }, onGestureBegan: {
                    playing = false; model.followSensor = false; model.beginGesture()
                }, onGestureReleased: { velocity in
                    model.releaseGesture(velocity:velocity)
                })
                    .aspectRatio(1.6,contentMode:.fit)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .clipShape(RoundedRectangle(cornerRadius:18))
                    .overlay(alignment: .top) {
                        if model.loadingModel {
                            VStack(spacing:12) { ProgressView() }
                                .padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                        } else if let error = model.modelError {
                            VStack(spacing:12) {
                                Image(systemName:"wifi.exclamationmark").font(.largeTitle)
                                Text(error).multilineTextAlignment(.center).frame(maxWidth:400)
                                Button(L10n.text("Try again")) { model.loadModel() }
                            }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                        }
                    }
                    // Keep the stage centred on the window, preserving its previous width.
                    // The controls overlay the right margin instead of shifting the model left.
                    .padding(.horizontal,92)
                VStack(spacing:16) {
                    Text("\(Int(model.angle.rounded()))°").font(.system(size:38,weight:.light,design:.rounded)).monospacedDigit()
                    VerticalLidSlider(value:Binding(get:{ model.angle },set:{ playing = false; model.setAngle($0) }))
                        .frame(width:26,height:220)
                        .modifier(LiquidGlassSlider())
                        .disabled(model.followSensor)
                    Button {
                        model.followSensor = false; playing.toggle(); model.noteInteraction()
                    } label: {
                        Image(systemName:playing ? "pause.fill" : "play.fill")
                            .font(.system(size:16,weight:.semibold)).frame(width:28,height:28)
                    }.modifier(LiquidGlassButtons(circular:true))
                    .accessibilityLabel(playing ? L10n.text("Pause") : L10n.text("Play preview"))
                }.frame(width:160)
                    .frame(maxWidth:.infinity,alignment:.trailing)
            }.padding(.bottom,18)
            if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).padding(.bottom,12) }
        }
    }
    private var lifecycleView: some View {
        content
        .frame(minWidth:960,minHeight:600)
        .onChange(of:colorScheme) { _,value in model.setExampleAppearance(dark:value == .dark) }
        .onAppear(perform:appear)
        .onDisappear { model.setVisible(false) }
        .onChange(of:suspended) { _,value in model.setVisible(!value && scenePhase == .active); if !value { model.refreshDesktop() } }
        .onChange(of:scenePhase) { _,value in model.setVisible(value == .active && !suspended) }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in
            model.setVisible(!suspended); if !suspended { model.refreshDesktop() }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in
            model.setVisible(false)
        }
    }
    var body: some View {
        lifecycleView
        .onChange(of:appModel.permission) { _,allowed in if allowed { model.refreshDesktop() } else { model.clearDesktop() } }
        .onChange(of:appModel.angle) { _,angle in
            if model.followSensor, let angle { model.setAngle(angle) }
        }
        .task(id:animatePreview) { await runPreview() }
        .onChange(of:model.followSensor) { _,enabled in
            if enabled { playing = false; if let angle = appModel.angle { model.setAngle(angle) } }
        }
        .onChange(of:model.effectEnabled) { _,_ in model.update(settings:appModel.settings) }
        .onChange(of:appModel.settings) { _,value in model.update(settings:value) }
    }
    private func appear() {
        model.setExampleAppearance(dark:colorScheme == .dark)
        model.update(settings:appModel.settings)
        model.setVisible(!suspended)
        if !suspended { model.refreshDesktop() }
        if CommandLine.arguments.contains("--example-image") { model.setAngle(90) }
    }
    // Keep the async loop outside the view builder for older Swift type checkers.
    @MainActor private func runPreview() async {
        guard animatePreview else { return }
        let start = ProcessInfo.processInfo.systemUptime
        while !Task<Never, Never>.isCancelled {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            model.setAngle(80 + 30 * cos(elapsed * 1.1))
            let delay: UInt64 = ProcessInfo.processInfo.isLowPowerModeEnabled ? 33_000_000 : 16_000_000
            do { try await Task<Never, Never>.sleep(nanoseconds:delay) }
            catch { return }
        }
    }

}
