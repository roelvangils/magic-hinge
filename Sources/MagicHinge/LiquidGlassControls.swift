import SwiftUI

/// Use the system material so controls track macOS appearance and accessibility preferences.
struct LiquidGlassButtons: ViewModifier {
    var circular = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if circular {
                content.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
            } else {
                content.buttonStyle(.glass).controlSize(.large)
            }
        } else {
            content.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

struct LiquidGlassSlider: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.padding(.vertical,16).padding(.horizontal,8)
                .glassEffect(.regular,in:.capsule)
        } else {
            content.padding(.vertical,16).padding(.horizontal,8)
                .background(.regularMaterial,in:Capsule())
        }
    }
}
