import XCTest
@testable import DuoCore

final class HingeMotionFilterTests: XCTestCase {
    func testSingleSampleSpikeAndBoundaryChatterDoNotStartEffect() {
        var filter = HingeMotionFilter(); var session = FoldSession()
        for i in 0..<360 {
            let raw = i == 40 ? 150.0 : (i % 2 == 0 ? 90.0 : 91.0)
            let now = Double(i) / 120
            let accepted = filter.receive(angle: raw, at: now)
            XCTAssertEqual(session.receive(angle: accepted, at: now), .none)
            XCTAssertEqual(session.phase, .idle)
        }
    }
    func testRealSlowOneDegreeStepsSurviveFilteringInBothDirections() {
        for direction in [-1.0, 1] {
            var filter = HingeMotionFilter()
            _ = filter.receive(angle: 90, at: 0)
            var firstChange: Double?
            var accepted: Double?
            for i in 1...80 {
                let now = Double(i) / 120
                let raw = 90 + direction * (i < 40 ? 1 : 2)
                accepted = filter.receive(angle: raw, at: now)
                if accepted != 90 && firstChange == nil { firstChange = now }
            }
            XCTAssertLessThan(firstChange ?? 1, 0.075)
            XCTAssertEqual(accepted, 90 + 2 * direction)
        }
    }
    func testNoiseWhileHoldingDoesNotPreventReturnOrRecapture() {
        var filter = HingeMotionFilter(); var session = FoldSession()
        _ = session.receive(angle: filter.receive(angle: 90, at: 0), at: 0)
        var captures = 0
        for i in 1...480 {
            let now = Double(i) / 120
            let raw = i < 60 ? 70.0 : (i % 2 == 0 ? 70.0 : 71.0)
            if session.receive(angle: filter.receive(angle: raw, at: now), at: now) == .capture { captures += 1 }
        }
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(session.phase, .idle)
    }
    func testFastMotionAndRealReversalPassWithinTwoReadings() {
        var filter = HingeMotionFilter()
        XCTAssertEqual(filter.receive(angle: 90, at: 0), 90)
        _ = filter.receive(angle: 87, at: 0.01)
        XCTAssertEqual(filter.receive(angle: 84, at: 0.02), 87)
        XCTAssertEqual(filter.receive(angle: 81, at: 0.03), 84)
        _ = filter.receive(angle: 88, at: 0.04)
        XCTAssertEqual(filter.receive(angle: 91, at: 0.05), 88)
    }
    func testStaleReadingsIgnoredAndInvalidReadingsReset() {
        var filter = HingeMotionFilter()
        XCTAssertEqual(filter.receive(angle: 90, at: 5), 90)
        XCTAssertEqual(filter.receive(angle: 150, at: 4), 90)
        XCTAssertNil(filter.receive(angle: nil, at: 6))
        XCTAssertEqual(filter.receive(angle: 30, at: 7), 30)
    }
    func testInterpolationProducesSubDegreeFramesAt60And120Hz() {
        for fps in [60.0, 120] {
            var session = FoldSession()
            _ = session.receive(angle: 90, at: 0)
            _ = session.receive(angle: 89, at: 0.01)
            var previous = 0.0
            for i in 1...Int(fps / 5) {
                let value = session.frame(at: 0.01 + Double(i) / fps).degrees
                XCTAssertGreaterThanOrEqual(value, previous)
                XCTAssertLessThanOrEqual(value, 1)
                if i == 1 { XCTAssertGreaterThan(value, 0); XCTAssertLessThan(value, 0.5) }
                previous = value
            }
            XCTAssertEqual(previous, 1, accuracy: 0.002)
        }
    }
}
