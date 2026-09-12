import XCTest
import AppKit
import SceneKit
@testable import DuoSimulation

final class LidInteractionTests: XCTestCase {
    private final class ScrollEvent: NSEvent {
        var point: CGPoint = .zero
        var dy: CGFloat = 0
        var eventTime: Double = 0
        override var timestamp: TimeInterval { eventTime }
        var gesturePhase: NSEvent.Phase = []
        var inertiaPhase: NSEvent.Phase = []
        var natural = true
        var heldModifiers: NSEvent.ModifierFlags = []
        override var modifierFlags: NSEvent.ModifierFlags { heldModifiers }
        override var locationInWindow: NSPoint { point }
        override var scrollingDeltaY: CGFloat { dy }
        override var hasPreciseScrollingDeltas: Bool { true }
        override var isDirectionInvertedFromDevice: Bool { natural }
        override var phase: NSEvent.Phase { gesturePhase }
        override var momentumPhase: NSEvent.Phase { inertiaPhase }
    }
    @MainActor func testTrackpadLocksGestureAndIgnoresMomentum() {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera; view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
        var angle = 50.0
        model.setAngle(angle)
        view.currentAngle = { angle }
        view.onAngleChanged = { angle = $0; model.setAngle($0) }
        _ = view.snapshot()
        let rect = view.lidDragRect
        let event = ScrollEvent()
        event.point = CGPoint(x:rect.midX,y:rect.midY)
        event.gesturePhase = .began; event.dy = 20
        view.scrollWheel(with:event)
        XCTAssertLessThan(angle,50)
        let first = angle
        event.point = .zero; event.gesturePhase = .changed
        view.scrollWheel(with:event)
        XCTAssertLessThan(angle,first,"Claimed swipe continues outside the moving region")
        event.gesturePhase = .ended; event.dy = 0
        view.scrollWheel(with:event)
        let stopped = angle
        event.gesturePhase = []; event.inertiaPhase = .began; event.dy = 100
        view.scrollWheel(with:event)
        XCTAssertEqual(angle,stopped,"Flick momentum must not keep opening the lid")
        event.inertiaPhase = .ended; view.scrollWheel(with:event)
        // Physical upward movement has opposite deltas with natural scrolling disabled.
        event.inertiaPhase = []; event.gesturePhase = .began; event.natural = false; event.dy = -20
        event.point = CGPoint(x:view.lidDragRect.midX,y:view.lidDragRect.midY)
        view.scrollWheel(with:event)
        XCTAssertLessThan(angle,stopped)
        event.gesturePhase = .cancelled; event.dy = 0; view.scrollWheel(with:event)
        let afterCancel = angle
        event.point = .zero; event.gesturePhase = .began; event.dy = -20
        view.scrollWheel(with:event)
        XCTAssertEqual(angle,afterCancel,"A new gesture outside the region must scroll the window")
    }
    @MainActor func testOpeningFlickReleasesOnceAndCancelsOnNewGesture() {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera
        view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
        _ = view.snapshot()
        var angle = 40.0, begins = 0
        var releases: [Double] = []
        view.currentAngle = { angle }
        view.onAngleChanged = { angle = $0 }
        view.onGestureBegan = { begins += 1 }
        view.onGestureReleased = { releases.append($0) }
        let event = ScrollEvent()
        event.point = CGPoint(x:view.lidDragRect.midX,y:view.lidDragRect.midY)
        event.dy = -10; event.gesturePhase = .began; event.eventTime = 1
        view.scrollWheel(with:event)
        event.gesturePhase = .changed; event.eventTime += 1.0/60
        view.scrollWheel(with:event)
        event.gesturePhase = .ended; event.dy = 0; event.eventTime += 1.0/60
        view.scrollWheel(with:event)
        XCTAssertEqual(releases.count,1)
        XCTAssertGreaterThan(releases[0],65)
        XCTAssertGreaterThan(angle,40)
        let releasedAngle = angle
        event.gesturePhase = []; event.inertiaPhase = .began; event.dy = -100
        view.scrollWheel(with:event)
        XCTAssertEqual(angle,releasedAngle,"Native inertia must not be added on top of the spring")
        XCTAssertEqual(releases.count,1)
        event.inertiaPhase = []; event.gesturePhase = .began; event.dy = 0
        view.scrollWheel(with:event)
        XCTAssertEqual(begins,2,"A new touch interrupts the spring even before moving")
        event.gesturePhase = .cancelled; view.scrollWheel(with:event)
        XCTAssertEqual(releases.count,1,"Cancelled gestures must not launch a spring")
    }
    @MainActor func testTwoFingerDoubleTapIsScopedToProduct() {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera
        view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
        _ = view.snapshot()
        var toggles = 0
        var slowRequests: [Bool] = []
        view.onToggleLid = { slow in toggles += 1; slowRequests.append(slow) }
        let event = ScrollEvent()
        event.point = CGPoint(x:view.lidDragRect.midX,y:view.lidDragRect.midY)
        view.smartMagnify(with:event)
        XCTAssertEqual(toggles,1)
        model.setAngle(0)
        event.heldModifiers = .shift
        event.point = CGPoint(x:view.lidDragRect.midX,y:view.lidDragRect.midY)
        view.smartMagnify(with:event)
        XCTAssertEqual(toggles,2)
        XCTAssertEqual(slowRequests,[false,true])
        event.point = .zero; view.smartMagnify(with:event)
        XCTAssertEqual(toggles,2)
    }
    @MainActor func testMouseDragUsesVelocityAndReleasesMomentum() throws {
        func gesture(duration: Double) throws -> (Double,Double) {
            let model = MacBookModel()
            let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
            view.scene = model.scene; view.pointOfView = model.camera
            view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
            _ = view.snapshot()
            var angle = 30.0, releaseVelocity = 0.0, grabs = 0
            view.currentAngle = { angle }
            view.onAngleChanged = { angle = $0 }
            view.onGestureReleased = { releaseVelocity = $0 }
            view.onGestureBegan = { grabs += 1 }
            let p = CGPoint(x:view.lidDragRect.midX,y:view.lidDragRect.midY)
            func event(_ type: NSEvent.EventType, delta: Double, at time: Double) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with:type,location:CGPoint(x:p.x,y:p.y+delta),
                    modifierFlags:[],timestamp:time,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
            }
            view.mouseDown(with:try event(.leftMouseDown,delta:0,at:1))
            XCTAssertEqual(grabs,1)
            for step in 1...12 {
                view.mouseDragged(with:try event(.leftMouseDragged,delta:Double(step)*5,at:1+duration*Double(step)/12))
            }
            view.mouseUp(with:try event(.leftMouseUp,delta:60,at:1+duration+0.01))
            return (angle,releaseVelocity)
        }
        let slow = try gesture(duration:1.2)
        let fast = try gesture(duration:0.1)
        XCTAssertEqual(slow.0,54,accuracy:0.01)
        XCTAssertGreaterThan(fast.0,slow.0+5)
        XCTAssertLessThan(slow.1,65)
        XCTAssertGreaterThan(fast.1,65)
    }
    @MainActor func testMouseDoubleClickUsesSameToggleAndDoesNotStartDrag() throws {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera
        view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
        _ = view.snapshot()
        var toggles = 0, drags = 0
        var slowRequests: [Bool] = []
        view.onToggleLid = { slow in toggles += 1; slowRequests.append(slow) }
        view.currentAngle = { 110 }
        view.onAngleChanged = { _ in drags += 1 }
        let p = CGPoint(x:view.lidDragRect.midX,y:view.lidDragRect.midY)
        func event(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with:type,location:point,modifierFlags:clicks == 2 ? [.shift] : [],timestamp:0,
                windowNumber:0,context:nil,eventNumber:0,clickCount:clicks,pressure:1))
        }
        view.mouseDown(with:try event(.leftMouseDown,p,clicks:1))
        view.mouseUp(with:try event(.leftMouseUp,p,clicks:1))
        XCTAssertEqual(toggles,0)
        view.mouseDown(with:try event(.leftMouseDown,p,clicks:2))
        view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:p.x,y:p.y+40),clicks:2))
        view.mouseUp(with:try event(.leftMouseUp,p,clicks:2))
        XCTAssertEqual(toggles,1)
        XCTAssertEqual(drags,0)
        XCTAssertEqual(slowRequests,[true])
        view.mouseDown(with:try event(.leftMouseDown,.zero,clicks:2))
        XCTAssertEqual(toggles,1)
    }
    @MainActor func testWholeProductAndMarginRemainDraggable() {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera
        view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
        _ = view.snapshot()
        for angle in [0.0,45,110,130] {
            model.setAngle(angle)
            for offset in [0.0,ClosedLidFloat.maximumOffset] {
                model.setFloatingOffset(offset)
                let rect = view.lidDragRect
                for p in [SCNVector3(-1.7,0.08,1.22),SCNVector3(1.7,0.08,1.22),SCNVector3(0,0.12,0)] {
                    let projected = view.projectPoint(model.product.convertPosition(p,to:nil))
                    XCTAssertTrue(rect.contains(CGPoint(x:projected.x,y:projected.y)))
                    XCTAssertTrue(rect.contains(CGPoint(x:projected.x,y:projected.y-25)),"Margin under the base stays draggable")
                }
            }
        }
    }
    @MainActor func testDragFollowsLidAndKeepsCameraFixed() throws {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera; view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds
        var angle = 0.0
        view.currentAngle = { angle }
        view.onAngleChanged = { angle = $0; model.setAngle($0) }
        let cameraTransform = model.camera.transform
        model.setAngle(0)
        _ = view.snapshot()
        let closedRegion = view.lidDragRect
        XCTAssertGreaterThan(closedRegion.width,300)
        XCTAssertGreaterThanOrEqual(closedRegion.height,99)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,
                windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
        }
        let grab = CGPoint(x:closedRegion.midX,y:closedRegion.midY)
        view.mouseDown(with:try event(.leftMouseDown,grab))
        // Continue after leaving the original hit area, without grabbing the 3D geometry.
        view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:grab.x,y:grab.y+220)))
        XCTAssertGreaterThan(angle,80)
        XCTAssertGreaterThan(view.lidDragRect.maxY,closedRegion.maxY+100)
        view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:grab.x,y:grab.y+600)))
        XCTAssertEqual(angle,130)
        view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:grab.x,y:grab.y+590)))
        XCTAssertLessThan(angle,130,"Reversing at the stop must respond immediately")
        view.mouseUp(with:try event(.leftMouseUp,grab))
        let previous = angle
        view.mouseDown(with:try event(.leftMouseDown,CGPoint(x:0,y:0)))
        view.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:0,y:150)))
        view.mouseUp(with:try event(.leftMouseUp,CGPoint(x:0,y:150)))
        XCTAssertEqual(angle,previous,"Outside the handle must not alter the lid")
        XCTAssertTrue(SCNMatrix4EqualToMatrix4(cameraTransform,model.camera.transform))
    }
}
