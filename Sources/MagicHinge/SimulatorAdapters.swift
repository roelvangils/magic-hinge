import SwiftUI
import Combine
import SceneKit
import MetalKit
import DuoCore
import DuoGraphics
import DuoSimulation

struct LaptopSceneView: NSViewRepresentable {
    let model: SimulatorModel
    var onManualAngle: (Double) -> Void
    var onToggleLid: (Bool) -> Void
    var onKeyboardStep: (Double) -> Void
    var onLidEndpoint: (Double, Bool) -> Void
    var onGestureBegan: () -> Void
    var onGestureReleased: (Double) -> Void
    func makeNSView(context: Context) -> SimulationSceneView {
        let view = SimulationSceneView(frame:.zero,options:[SCNView.Option.preferredRenderingAPI.rawValue:SCNRenderingAPI.metal.rawValue])
        view.scene = model.laptop.scene; view.pointOfView = model.laptop.camera
        view.antialiasingMode = SimulationSceneView.antialiasingMode(for:view.device)
        view.refineWhenStill(true)
        view.backgroundColor = .clear
        view.allowsCameraControl = false; view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false; view.isPlaying = false
        view.setAccessibilityLabel(L10n.format("Interactive 3D model of %@", model.configuration.title))
        model.view = view
        return view
    }
    func updateNSView(_ nsView: SimulationSceneView, context: Context) {
        nsView.lidNode = model.laptop.hinge
        nsView.bodyNode = model.laptop.bodyInteractionBounds
        nsView.contactNode = model.laptop.contactEdgeBounds
        nsView.screenNode = model.laptop.screenNode
        nsView.currentAngle = { [weak model] in model?.angle ?? 0 }
        nsView.onAngleChanged = onManualAngle
        nsView.onToggleLid = onToggleLid
        nsView.onKeyboardStep = onKeyboardStep
        nsView.onLidEndpoint = onLidEndpoint
        nsView.onGestureBegan = onGestureBegan
        nsView.onGestureReleased = onGestureReleased
        nsView.setSwipeHintVisible(model.showSwipeHint)
    }
    static func dismantleNSView(_ nsView: SimulationSceneView, coordinator: ()) {
        nsView.cancelAnvil(); nsView.refineWhenStill(false); nsView.setSwipeHintVisible(false)
        nsView.isPlaying = false; nsView.rendersContinuously = false; nsView.scene = nil
        nsView.onAngleChanged = nil; nsView.onToggleLid = nil; nsView.onKeyboardStep = nil; nsView.onLidEndpoint = nil; nsView.onGestureBegan = nil; nsView.onGestureReleased = nil; nsView.currentAngle = nil; nsView.lidNode = nil; nsView.bodyNode = nil; nsView.contactNode = nil; nsView.screenNode = nil
    }
}

struct VerticalLidSlider: NSViewRepresentable {
    @Binding var value: Double
    final class Coordinator: NSObject {
        var parent: VerticalLidSlider
        init(_ parent: VerticalLidSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = sender.doubleValue }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value:value,minValue:0,maxValue:130,target:context.coordinator,action:#selector(Coordinator.changed(_:)))
        slider.frame = NSRect(x:0,y:0,width:32,height:320)
        slider.isVertical = true
        slider.isContinuous = true; slider.numberOfTickMarks = 14
        slider.allowsTickMarkValuesOnly = false
        slider.setAccessibilityLabel(L10n.text("3D lid angle"))
        return slider
    }
    func updateNSView(_ nsView: NSSlider, context: Context) {
        context.coordinator.parent = self
        if abs(nsView.doubleValue-value)>0.001 { nsView.doubleValue = value }
    }
}
