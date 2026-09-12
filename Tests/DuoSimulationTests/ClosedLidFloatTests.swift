import XCTest
import SceneKit
@testable import DuoSimulation

final class ClosedLidFloatTests: XCTestCase {
    func testDelayGentleCycleAndOpeningReturn() {
        var motion = ClosedLidFloat()
        XCTAssertEqual(motion.frame(angle:0,at:0),0)
        XCTAssertEqual(motion.frame(angle:0,at:0.99),0)
        XCTAssertEqual(motion.frame(angle:0,at:1),0)
        var previous = 0.0
        var peak = 0.0
        for step in 1...264 {
            let value = motion.frame(angle:0,at:1+Double(step)/60)
            XCTAssertLessThan(abs(value-previous),0.001)
            XCTAssertGreaterThanOrEqual(value,0)
            XCTAssertLessThanOrEqual(value,0.06)
            peak = max(peak,value); previous = value
        }
        XCTAssertGreaterThan(peak,0.055)
        for step in 1...132 { _ = motion.frame(angle:0,at:5.4+Double(step)/60) }
        let elevated = motion.offset
        XCTAssertGreaterThan(elevated,0.03)
        let opening = motion.frame(angle:1,at:7.62)
        XCTAssertGreaterThan(opening,0)
        XCTAssertLessThan(opening,elevated)
        // A quick close while settling must not teleport the chassis down.
        let closedAgain = motion.frame(angle:0,at:7.63)
        XCTAssertGreaterThan(closedAgain,opening*0.8)
        XCTAssertEqual(motion.frame(angle:80,at:12),0)
        XCTAssertEqual(motion.frame(angle:0,at:13,enabled:false),0)
    }
    func testOpenLaptopFloatsAfterRestAndMovementSettlesIt() {
        var motion = ClosedLidFloat()
        XCTAssertEqual(motion.frame(angle:90,at:0,resting:true),0)
        XCTAssertEqual(motion.frame(angle:90,at:0.99,resting:true),0)
        XCTAssertTrue(motion.isWaitingOrFloating)
        var peak = 0.0
        for frame in 60...300 { peak = max(peak,motion.frame(angle:90,at:Double(frame)/60,resting:true)) }
        XCTAssertGreaterThan(peak,0.055)
        for frame in 301...400 { _ = motion.frame(angle:Double(frame)/5,at:Double(frame)/60,resting:false) }
        XCTAssertEqual(motion.offset,0)
        XCTAssertFalse(motion.isWaitingOrFloating)
        XCTAssertEqual(motion.frame(angle:90,at:7,enabled:false),0)
    }
    func testShadowStaysFixedAndSoftensAtHeight() {
        let model = MacBookModel()
        let position = model.floatingShadow.position
        let cameraTransform = model.camera.transform
        model.setFloatingOffset(0.06)
        XCTAssertEqual(model.product.position.y,0.06,accuracy:0.00001)
        XCTAssertEqual(model.product.eulerAngles.x,-0.65 * .pi / 180,accuracy:0.00001)
        XCTAssertTrue(SCNMatrix4EqualToMatrix4(model.camera.transform,cameraTransform))
        XCTAssertEqual(model.floatingShadow.position.y,position.y)
        XCTAssertEqual(model.floatingShadow.position.z,position.z)
        XCTAssertLessThan(model.floatingShadow.opacity,0.78)
        XCTAssertGreaterThan(model.floatingShadow.scale.x,1)
        XCTAssertGreaterThan(model.floatingShadow.scale.y,1)
        model.setFloatingOffset(0)
        XCTAssertEqual(model.product.position.y,0)
        XCTAssertEqual(model.product.eulerAngles.x,0)
        XCTAssertEqual(model.floatingShadow.opacity,0.78,accuracy:0.00001)
        XCTAssertEqual(model.floatingShadow.scale.y,1)
    }
}
