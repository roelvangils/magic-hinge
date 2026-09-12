import XCTest
@testable import DuoSimulation

final class LidScrollPhysicsTests: XCTestCase {
    private func stroke(duration: Double, rate: Double = 60) -> (Double,Double) {
        var physics = LidScrollPhysics()
        var distance = 0.0
        let samples = Int(duration*rate)
        for frame in 0..<samples {
            distance += physics.displacement(30/Double(samples),at:Double(frame)/rate)
        }
        return (distance,physics.releaseVelocity(at:duration))
    }
    func testFastStrokeTravelsFurtherAndSlowStrokeRemainsPrecise() {
        let slow = stroke(duration:1.5), fast = stroke(duration:0.15)
        XCTAssertEqual(slow.0,30,accuracy:0.001)
        XCTAssertGreaterThan(fast.0,slow.0*1.2)
        XCTAssertGreaterThan(fast.1,65)
        XCTAssertLessThan(slow.1,65)
        let frequent = stroke(duration:0.15,rate:120)
        XCTAssertEqual(frequent.0,fast.0,accuracy:3)
        XCTAssertEqual(frequent.1,fast.1,accuracy:45)
    }
    func testPauseAndReversalRemoveStaleOpeningMomentum() {
        var physics = LidScrollPhysics()
        for frame in 0..<8 { _ = physics.displacement(6,at:Double(frame)/60) }
        XCTAssertGreaterThan(physics.releaseVelocity(at:8.0/60),65)
        XCTAssertLessThan(physics.releaseVelocity(at:1),1)
        _ = physics.displacement(-2,at:8.0/60)
        XCTAssertLessThan(physics.releaseVelocity(at:9.0/60),0)
        physics.reset()
        XCTAssertEqual(physics.releaseVelocity(at:2),0)
    }
    func testReleaseVelocityDeterminesOvershootAndAlwaysSettlesAtNinety() {
        var peaks: [Double] = []
        for velocity in [100.0,350,700] {
            var spring = LidReleaseSpring(angle:75,velocity:velocity)
            var peak = 75.0
            for _ in 0..<300 {
                let angle = spring.advance(by:1.0/60)
                XCTAssertTrue((0...130).contains(angle))
                peak = max(peak,angle)
            }
            XCTAssertTrue(spring.isComplete)
            XCTAssertEqual(spring.angle,90)
            peaks.append(peak)
        }
        XCTAssertGreaterThan(peaks[1],peaks[0]+4)
        XCTAssertGreaterThan(peaks[2],peaks[1]+4)
        print("Opening flick peaks at 100/350/700 degrees per second: \(peaks)")
    }
    func testSpringIsStableAcrossFrameRatesAndAtPhysicalStop() {
        var regular = LidReleaseSpring(angle:80,velocity:400)
        var reduced = regular
        for _ in 0..<60 { _ = regular.advance(by:1.0/60) }
        for _ in 0..<30 { _ = reduced.advance(by:1.0/30) }
        XCTAssertEqual(regular.angle,reduced.angle,accuracy:0.01)
        var atStop = LidReleaseSpring(angle:129,velocity:900)
        for _ in 0..<300 {
            XCTAssertTrue((0...130).contains(atStop.advance(by:1.0/60)))
        }
        XCTAssertEqual(atStop.angle,90)
    }
}
