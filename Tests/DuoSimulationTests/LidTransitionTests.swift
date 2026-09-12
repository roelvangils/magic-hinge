import XCTest
@testable import DuoSimulation

final class LidTransitionTests: XCTestCase {
    func testOpeningOvershootsThenSettlesAtNinetyDegrees() {
        let motion = LidTransition(from:0,target:90,at:10,openingOvershoot:5)
        XCTAssertEqual(motion.duration,0.95*1.25)
        XCTAssertEqual(motion.angle(at:9),0)
        let peakTime = 10+motion.duration*0.7
        XCTAssertEqual(motion.angle(at:peakTime),95,accuracy:0.00001)
        XCTAssertGreaterThan(motion.angle(at:peakTime+0.1),90)
        XCTAssertLessThan(motion.angle(at:peakTime+0.1),95)
        XCTAssertEqual(motion.angle(at:10+motion.duration),90,accuracy:0.00001)
        XCTAssertEqual(motion.angle(at:12),90,accuracy:0.00001)
        let before = motion.angle(at:peakTime-0.001)
        let after = motion.angle(at:peakTime+0.001)
        XCTAssertEqual(before,95,accuracy:0.001)
        XCTAssertEqual(after,95,accuracy:0.001)
        let closing = LidTransition(from:95,target:0,at:peakTime,openingOvershoot:5)
        XCTAssertEqual(closing.duration,0.85*1.25)
        XCTAssertEqual(closing.angle(at:peakTime),95)
        XCTAssertEqual(closing.angle(at:12),0)
        let nearOpen = LidTransition(from:89,target:90,at:0,openingOvershoot:5)
        XCTAssertLessThan(nearOpen.angle(at:nearOpen.duration*0.7),90.1)
    }
    func testShiftScalesTimeWithoutChangingOpeningOrClosingCurve() {
        for (from,to) in [(0.0,90.0),(90.0,0.0)] {
            let normal = LidTransition(from:from,target:to,at:0,openingOvershoot:5)
            let slow = LidTransition(from:from,target:to,at:0,openingOvershoot:5,slowMotion:true)
            XCTAssertEqual(slow.duration,normal.duration*3)
            for frame in 0...120 {
                let time = normal.duration*Double(frame)/120
                XCTAssertEqual(slow.angle(at:time*3),normal.angle(at:time),accuracy:0.00001)
            }
            XCTAssertFalse(slow.isComplete(at:normal.duration))
            XCTAssertTrue(slow.isComplete(at:slow.duration))
        }
    }
    func testGentleFullTravelWithoutOvershoot() {
        for (from,to) in [(0.0,130.0),(130.0,0.0)] {
            let motion = LidTransition(from:from,target:to,at:10)
            XCTAssertEqual(motion.angle(at:9),from)
            XCTAssertEqual(motion.angle(at:10+motion.duration+0.01),to)
            XCTAssertFalse(motion.isComplete(at:10.5))
            XCTAssertTrue(motion.isComplete(at:10+motion.duration))
            var previous = from
            for frame in 0...60 {
                let value = motion.angle(at:10+Double(frame)/60*motion.duration)
                XCTAssertTrue((0...130).contains(value))
                XCTAssertGreaterThanOrEqual((value-previous)*(to-from),0)
                previous = value
            }
            let firstStep = abs(motion.angle(at:10+1.0/60)-from)
            let middleStep = abs(motion.angle(at:10+motion.duration/2+1.0/60)-motion.angle(at:10+motion.duration/2))
            XCTAssertLessThan(firstStep,middleStep*0.02)
            let reverse = LidTransition(from:motion.angle(at:10.3),target:from,at:10.3)
            XCTAssertEqual(reverse.angle(at:10.3),motion.angle(at:10.3))
            XCTAssertEqual(reverse.angle(at:12),from)
        }
    }
}
