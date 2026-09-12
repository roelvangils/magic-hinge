import XCTest
import AppKit
import SceneKit
@testable import DuoSimulation

final class SwipeAffordanceTests: XCTestCase {
    func testHintLoopsInSyncAndNeverInterceptsInput() throws {
        let view = SwipeAffordanceView(frame:NSRect(x:0,y:0,width:74,height:100))
        view.setAnimating(true)
        let dots = try XCTUnwrap(view.layer?.sublayers)
        XCTAssertEqual(dots.count,2)
        let animations = try dots.map { try XCTUnwrap($0.animation(forKey:"swipe") as? CAAnimationGroup) }
        XCTAssertEqual(animations[0].beginTime,animations[1].beginTime)
        XCTAssertTrue(animations.allSatisfy { $0.repeatCount == .infinity && $0.duration == 2.1 })
        XCTAssertNil(view.hitTest(NSPoint(x:22,y:18)))
        view.setAnimating(false)
        XCTAssertTrue(view.isHidden)
        XCTAssertTrue(dots.allSatisfy { $0.animationKeys()?.isEmpty ?? true })
    }
    @MainActor func testHintAnchorsToHingeWhenClosedAndScreenCenterWhenOpen() throws {
        let model = MacBookModel()
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:800,height:500))
        view.scene = model.scene; view.pointOfView = model.camera
        view.lidNode = model.hinge; view.bodyNode = model.bodyInteractionBounds; view.screenNode = model.screenNode
        var angle = 0.0
        view.currentAngle = { angle }
        model.setAngle(angle)
        _ = view.snapshot()
        view.setSwipeHintVisible(true)
        let hint = try XCTUnwrap(view.subviews.compactMap { $0 as? SwipeAffordanceView }.first)
        let rear = view.projectPoint(model.hinge.convertPosition(SCNVector3Zero,to:nil))
        XCTAssertEqual(hint.frame.minY,CGFloat(rear.y)+6,accuracy:0.01)
        let closed = try XCTUnwrap(hint.layer?.sublayers?.first?.animation(forKey:"swipe") as? CAAnimationGroup)
        XCTAssertEqual((closed.animations?.first as? CABasicAnimation)?.toValue as? Int,40)
        angle = 90; model.setAngle(angle)
        view.setSwipeHintVisible(true)
        let screen = try XCTUnwrap(model.screenNode)
        let box = screen.boundingBox
        let middle = SCNVector3((box.min.x+box.max.x)/2,(box.min.y+box.max.y)/2,(box.min.z+box.max.z)/2)
        let point = view.projectPoint(screen.convertPosition(middle,to:nil))
        XCTAssertEqual(hint.frame.midX,CGFloat(point.x),accuracy:0.01)
        XCTAssertEqual(hint.frame.midY,CGFloat(point.y),accuracy:0.01)
        let opened = try XCTUnwrap(hint.layer?.sublayers?.first?.animation(forKey:"swipe") as? CAAnimationGroup)
        XCTAssertEqual((opened.animations?.first as? CABasicAnimation)?.toValue as? Int,-40)
    }

}
