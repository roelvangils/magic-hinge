import XCTest
@testable import DuoCore

final class HingePollingPolicyTests: XCTestCase {
    func testIdlePollingAndImmediateAccelerationOnMovement() {
        var policy = HingePollingPolicy()
        XCTAssertEqual(policy.receive(angle: 90, at: 0), 30)
        XCTAssertEqual(policy.receive(angle: 90, at: 10), 30)
        XCTAssertEqual(policy.receive(angle: 89, at: 10.03), 120)
        XCTAssertEqual(policy.receive(angle: 89, at: 10.9), 120)
        XCTAssertEqual(policy.receive(angle: 89, at: 11.04), 30)
        XCTAssertEqual(policy.receive(angle: 90, at: 11.07), 120)
    }
    func testSlowWakePollingStillDetectsFirstStepWithin100Milliseconds() {
        var policy = HingePollingPolicy(); var filter = HingeMotionFilter(); var session = FoldSession()
        _ = session.receive(angle: filter.receive(angle: 90, at: 0), at: 0)
        _ = policy.receive(angle: 90, at: 0)
        var time = 1.0 / 30
        var detected = false
        while time < 0.1 {
            let rate = policy.receive(angle: 89, at: time)
            if session.receive(angle: filter.receive(angle: 89, at: time), at: time) == .capture { detected = true; break }
            time += 1.0 / Double(rate)
        }
        XCTAssertTrue(detected)
        XCTAssertLessThan(time, 0.1)
    }
}
