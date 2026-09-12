import SwiftUI
import DuoCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulator: SimulatorModel
    var simulatorSuspended = false
    @AppStorage("appearance") private var appearance = AppAppearance.auto
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                SimulatorView(appModel:model, model:simulator, suspended:simulatorSuspended)
                Divider().padding(.horizontal,24)
                VStack(alignment:.leading,spacing:16) {
                    if model.isLidClosed {
                        Label {
                            Text(L10n.text("Your laptop is in clamshell mode. Open it to watch the magic happen."))
                                .fixedSize(horizontal:false,vertical:true)
                        } icon: {
                            Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        }
                        .font(.callout)
                        .frame(maxWidth:.infinity,alignment:.leading)
                    } else {
                        HStack(spacing:16) {
                            Circle().fill(model.effectActive ? .orange : model.permission && model.hasBuiltInScreen && model.angle != nil ? .green : .secondary)
                                .frame(width:8,height:8)
                            Text(model.angle.map { L10n.format("Hinge: %d°", Int($0)) } ?? L10n.text("Hinge: —"))
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                            if !model.permission {
                                Button(L10n.text("Grant screen access…")) { model.requestPermission() }
                            } else {
                                Button(L10n.text("Test full screen")) { model.demonstrate() }
                                    .disabled(!model.hasBuiltInScreen || model.effectActive)
                            }
                            if model.errorMessage != nil { Button(L10n.text("Try again")) { model.retry() } }
                            Spacer()
                        }
                    }
                    if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    #if DEBUG
                    if !model.lockTestStatus.isEmpty { Text(model.lockTestStatus).font(.caption).foregroundStyle(.secondary) }
                    #endif
                }.padding(24)
            }
        }
        .modifier(LiquidGlassButtons())
        .scrollContentBackground(.hidden)
        // The hidden-title-bar window adds 28 points above its content:
        // 1120 × (772 + 28) gives an outer window ratio of exactly 1.4:1.
        .frame(width:1120,height:772)
        .background { AppearanceWallpaper() }
        .onAppear { appearance.apply() }
        .onChange(of:appearance) { _,value in value.apply() }
    }
}

/// All visual tuning edits the same persisted settings used by the desktop effect.
struct EffectTuningControls: View {
    @Binding var settings: FoldSettings
    var horizontal = false
    var body: some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(alignment:.top,spacing:24))
            : AnyLayout(VStackLayout(alignment:.leading,spacing:17))
        layout {
            parameter(L10n.text("Blur"), value:$settings.blur, range:0...0.24,
                      text:"\(Int(settings.blur / 0.055 * 100))%")
            parameter(L10n.text("Perspective"), value:$settings.perspective, range:0...1.3,
                      text:String(format:"%.2f×",settings.perspective))
            parameter(L10n.text("Viewing distance"), value:$settings.eyeDistance, range:1.2...4,
                      text:L10n.format("%.1f× height",settings.eyeDistance))
            parameter(L10n.text("Darkening"), value:$settings.darkness, range:0...1,
                      text:"\(Int(settings.darkness*100))%")
        }
    }
    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(spacing:5) {
            HStack { Text(title); Spacer(); Text(text).foregroundStyle(.secondary).monospacedDigit() }.font(.callout)
            Slider(value:value,in:range).accessibilityLabel(title)
        }.frame(maxWidth:.infinity)
    }
}
