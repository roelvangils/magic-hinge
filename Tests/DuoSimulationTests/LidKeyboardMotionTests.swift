import XCTest
@testable import DuoSimulation

final class LidKeyboardMotionTests: XCTestCase {
    func testOneStepAcceleratesAndSettlesExactlyWithoutOvershoot() {
        for delta in [-5.0,5] {
            var motion = LidKeyboardMotion(angle:65)
            motion.step(by:delta)
            XCTAssertEqual(motion.angle,65)
            let first = abs(motion.advance(by:1.0/120)-65)
            XCTAssertLessThan(first,0.15)
            var previous = motion.angle
            for _ in 1..<120 {
                let current = motion.advance(by:1.0/120)
                XCTAssertGreaterThanOrEqual((current-previous)*delta,0)
                XCTAssertLessThanOrEqual(abs(current-65),5)
                previous = current
            }
            XCTAssertTrue(motion.isComplete)
            XCTAssertEqual(motion.angle,65+delta)
        }
    }
    func testRepeatedStepsPreservePositionAndVelocityAndAccumulateTheirTarget() {
        var motion = LidKeyboardMotion(angle:0)
        for step in 1...12 {
            let position = motion.angle, velocity = motion.velocity
            motion.step(by:5)
            XCTAssertEqual(motion.target,Double(step)*5)
            XCTAssertEqual(motion.angle,position)
            XCTAssertEqual(motion.velocity,velocity)
            _ = motion.advance(by:1.0/30)
        }
        let previousAngle = motion.angle, previousVelocity = motion.velocity
        motion.step(by:-5)
        XCTAssertEqual(motion.target,55)
        XCTAssertEqual(motion.angle,previousAngle)
        XCTAssertEqual(motion.velocity,previousVelocity)
        for _ in 0..<120 { _ = motion.advance(by:1.0/120) }
        XCTAssertEqual(motion.angle,55)
        XCTAssertTrue(motion.isComplete)
    }
    func testFrameRateIndependentAndClampedAtBothStops() {
        for (initial,delta) in [(129.0,5.0),(1.0,-5.0)] {
            var results: [Double] = []
            for rate in [30,60,120] {
                var motion = LidKeyboardMotion(angle:initial)
                motion.step(by:delta)
                for _ in 0..<rate/5 {
                    XCTAssertTrue((0...130).contains(motion.advance(by:1.0/Double(rate))))
                }
                results.append(motion.angle)
                for _ in 0..<rate { _ = motion.advance(by:1.0/Double(rate)) }
                XCTAssertEqual(motion.angle,delta > 0 ? 130 : 0)
            }
            XCTAssertEqual(results[0],results[1],accuracy:1e-10)
            XCTAssertEqual(results[1],results[2],accuracy:1e-10)
        }
    }
}
