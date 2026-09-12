import XCTest
import SceneKit
@testable import DuoSimulation

final class LidImpactResponseTests: XCTestCase {
    private func close(duration: Double) -> LidImpactResponse {
        var response = LidImpactResponse()
        _ = response.frame(angle:90,at:0)
        let steps = Int((duration*120).rounded())
        for step in 1...steps {
            let progress = Double(step)/Double(steps)
            XCTAssertEqual(response.frame(angle:90*(1-progress),at:duration*progress),0,
                           "The chassis must not move before the lid hits the base")
        }
        return response
    }
    func testHarderSlamsProduceStrongerDownwardReactionThenSettle() {
        var depths: [Double] = []
        for duration in [0.3,0.1] {
            var response = close(duration:duration)
            XCTAssertLessThan(response.velocity,0)
            var lowest = 0.0, rebound = 0.0
            for step in 1...180 {
                let offset = response.frame(angle:0,at:duration+Double(step)/120)
                lowest = min(lowest,offset); rebound = max(rebound,offset)
                XCTAssertGreaterThanOrEqual(offset,-0.1)
            }
            XCTAssertLessThan(lowest,0)
            XCTAssertGreaterThan(rebound,0)
            XCTAssertLessThan(rebound,abs(lowest)*0.25)
            XCTAssertFalse(response.isActive)
            depths.append(lowest)
        }
        XCTAssertLessThan(depths[1],depths[0]*2)
    }
    func testGentleClosureAndStationaryClosedLidDoNotTrigger() {
        var gentle = close(duration:2)
        XCTAssertFalse(gentle.isActive)
        for step in 1...120 { XCTAssertEqual(gentle.frame(angle:0,at:2+Double(step)/60),0) }
        var stationary = LidImpactResponse()
        XCTAssertEqual(stationary.frame(angle:0,at:0),0)
        XCTAssertEqual(stationary.frame(angle:0,at:1),0)
        XCTAssertFalse(stationary.isActive)
    }
    func testNoImpactAfterFastMovementStopsShortOfClosing() {
        var response = LidImpactResponse()
        _ = response.frame(angle:90,at:0)
        _ = response.frame(angle:5,at:0.1)
        for step in 1...120 { _ = response.frame(angle:5,at:0.1+Double(step)/60) }
        for step in 1...60 { _ = response.frame(angle:5*(1-Double(step)/60),at:2.1+Double(step)/60) }
        XCTAssertFalse(response.isActive)
    }
    func testWholeChassisMovesWhileShadowStaysFixedAndGetsTighter() {
        let model = MacBookModel()
        let shadowPosition = model.floatingShadow.position
        let baseOpacity = model.floatingShadow.opacity
        let camera = model.camera.transform
        model.setFloatingOffset(0,impactOffset:-0.06)
        XCTAssertEqual(model.product.position.y,-0.06,accuracy:0.00001)
        XCTAssertEqual(model.product.eulerAngles.x,0)
        XCTAssertEqual(model.floatingShadow.position.y,shadowPosition.y)
        XCTAssertGreaterThan(model.floatingShadow.opacity,baseOpacity)
        XCTAssertLessThan(model.floatingShadow.scale.y,1)
        XCTAssertTrue(SCNMatrix4EqualToMatrix4(camera,model.camera.transform))
        model.setFloatingOffset(0)
        XCTAssertEqual(model.product.position.y,0)
        XCTAssertEqual(model.floatingShadow.opacity,baseOpacity)
    }
}
