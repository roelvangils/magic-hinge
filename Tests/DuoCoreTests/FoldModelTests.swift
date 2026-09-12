import XCTest
@testable import DuoCore

final class FoldModelTests: XCTestCase {
    func testHIDReportDecodingAndMalformedData() {
        XCTAssertEqual(HingeReport.decode([1, 123, 0], length: 3), 123)
        XCTAssertEqual(HingeReport.decode([1, 0, 0], length: 3), 0)
        XCTAssertNil(HingeReport.decode([1, 90], length: 2))
        XCTAssertNil(HingeReport.decode([0, 90, 0], length: 3))
        XCTAssertNil(HingeReport.decode([1, 255, 255], length: 3))
        XCTAssertNil(HingeReport.decode([1, 90, 0], length: 9))
    }
    func testFirstSensorValueNeverStartsAnEffectAtAnyPosition() {
        for angle in [0.0, 20, 60, 98, 140] {
            var session = FoldSession()
            XCTAssertEqual(session.receive(angle: angle, at: 0), .none)
            XCTAssertEqual(session.receive(angle: angle, at: 10), .none)
            XCTAssertEqual(session.phase, .idle)
        }
    }
    func testClosingStartsAtEveryPositionButFurtherOpeningDoesNot() {
        for start in [5.0, 40, 80, 100, 140] {
            var session = FoldSession()
            _ = session.receive(angle: start, at: 0)
            XCTAssertEqual(session.receive(angle: start + 1, at: 0.01), .none)
            XCTAssertEqual(session.phase, .idle)
            XCTAssertEqual(session.receive(angle: start, at: 0.1), .capture)
            XCTAssertEqual(session.degrees, 0)
            XCTAssertEqual(session.frame(at: 0.3).degrees, 1, accuracy: 0.002)
        }
    }
    func testStationarySamplesDoNotPostponeFourHundredMillisecondTimeout() {
        var session = FoldSession()
        _ = session.receive(angle: 90, at: 0)
        _ = session.receive(angle: 70, at: 0.1)
        for i in 1...47 { _ = session.receive(angle: 70, at: 0.1 + Double(i)/120) }
        XCTAssertEqual(session.phase, .moving)
        XCTAssertEqual(session.frame(at: 0.499).phase, .moving)
        let first = session.frame(at: 0.5)
        XCTAssertEqual(first.phase, .returning)
        XCTAssertEqual(first.degrees, 20, accuracy: 0.001)
        let middle = session.frame(at: 0.725)
        XCTAssertEqual(middle.degrees, 10, accuracy: 0.01)
        let last = session.frame(at: 0.951)
        XCTAssertEqual(last.action, .dismiss)
        XCTAssertEqual(last.degrees, 0)
        XCTAssertEqual(last.phase, .idle)
    }
    func testAfterReturningNewMovementUsesNewRestingPosition() {
        var session = FoldSession()
        _ = session.receive(angle: 120, at: 0)
        _ = session.receive(angle: 80, at: 0.1)
        _ = session.frame(at: 1.6)
        XCTAssertEqual(session.receive(angle: 79, at: 2), .capture)
        XCTAssertEqual(session.degrees, 0)
        XCTAssertEqual(session.frame(at: 2.2).degrees, 1, accuracy: 0.002)
    }
    func testReversingDirectionDuringMovementReusesSnapshot() {
        var session = FoldSession()
        _ = session.receive(angle: 90, at: 0)
        XCTAssertEqual(session.receive(angle: 70, at: 0.01), .capture)
        XCTAssertEqual(session.receive(angle: 100, at: 0.2), .none)
        _ = session.frame(at: 0.4)
        XCTAssertEqual(session.degrees, 0, accuracy: 0.1)
        XCTAssertEqual(session.phase, .moving)
    }
    func testMotionDuringReturnContinuesFromVisiblePoseWithoutRecapture() {
        var session = FoldSession()
        _ = session.receive(angle: 90, at: 0)
        _ = session.receive(angle: 70, at: 0.1)
        let before = session.frame(at: 0.725).degrees
        XCTAssertEqual(before, 10, accuracy: 0.01)
        XCTAssertEqual(session.receive(angle: 69, at: 0.725), .none)
        XCTAssertEqual(session.degrees, before, accuracy: 0.0001)
        XCTAssertEqual(session.phase, .moving)
        _ = session.frame(at: 0.825)
        XCTAssertEqual(session.degrees, before + 1, accuracy: 0.05)
        XCTAssertEqual(session.frame(at: 1.124).phase, .moving)
        XCTAssertEqual(session.frame(at: 1.126).phase, .returning)
    }
    func testContinuedSlowMotionRestartsIdleTimer() {
        var session = FoldSession()
        _ = session.receive(angle: 90, at: 0)
        for i in 1...5 {
            _ = session.receive(angle: 90-Double(i), at: Double(i)*0.3)
            XCTAssertEqual(session.phase, .moving)
        }
        XCTAssertEqual(session.frame(at: 1.899).phase, .moving)
        XCTAssertEqual(session.frame(at: 1.901).phase, .returning)
    }
    func testInvalidSensorAndDisableCancelImmediately() {
        for invalid in [nil, Double.nan, Double.infinity, -10.0] as [Double?] {
            var session = FoldSession()
            _ = session.receive(angle: 90, at: 0)
            _ = session.receive(angle: 80, at: 0.1)
            XCTAssertEqual(session.receive(angle: invalid, at: 0.2), .dismiss)
            XCTAssertEqual(session.phase, .idle)
            XCTAssertEqual(session.receive(angle: 80, at: 0.3), .none)
        }
        var session = FoldSession()
        _ = session.receive(angle: 90, at: 0)
        _ = session.receive(angle: 80, at: 0.1)
        XCTAssertEqual(session.receive(angle: 80, at: 0.2, enabled: false), .dismiss)
    }
    func testReturnIsMonotonicAndFrameRateIndependent() {
        for delta in [10.0, 35] {
            var a = FoldSession(); var b = FoldSession()
            _ = a.receive(angle: 90, at: 0); _ = b.receive(angle: 90, at: 0)
            _ = a.receive(angle: 90-delta, at: 0.01); _ = b.receive(angle: 90-delta, at: 0.01)
            for i in 1...24 { _ = a.frame(at: 0.01 + Double(i)/60) }
            for i in 1...48 { _ = b.frame(at: 0.01 + Double(i)/120) }
            XCTAssertEqual(a.degrees, b.degrees, accuracy: 0.001)
            var previous = abs(a.degrees)
            for i in 1...60 {
                let current = abs(a.frame(at: 0.41 + Double(i)/120).degrees)
                XCTAssertLessThanOrEqual(current, previous + 1e-9)
                previous = current
            }
            XCTAssertEqual(a.phase, .idle)
        }
    }
    func testOpeningAfterSleepRevealsOnlyWhileNearlyClosed() {
        var session = FoldSession()
        XCTAssertEqual(session.beginOpening(angle: 15, at: 5), .capture)
        XCTAssertEqual(session.degrees, 85 * 2 / 3, accuracy: 0.001)
        XCTAssertEqual(session.receive(angle: 30, at: 5.1), .none)
        XCTAssertLessThan(session.frame(at: 5.3).degrees, 29)
        XCTAssertEqual(session.receive(angle: 45, at: 5.31), .none)
        let flat = session.frame(at: 5.6)
        XCTAssertEqual(flat.degrees, 0, accuracy: 0.002)
        XCTAssertEqual(flat.action, .dismiss, "Release the frozen screenshot immediately when opening has restored the flat pose.")
        XCTAssertEqual(session.receive(angle: 60, at: 6.3), .none)
        XCTAssertEqual(session.phase, .idle)
        for angle in [45.0, 90, 129] {
            XCTAssertEqual(session.beginOpening(angle: angle, at: 10), .none)
            XCTAssertEqual(session.phase, .idle)
        }
    }
    func testOldSettingsMigrateWithoutLosingTuningAndNewSwitchesPersist() throws {
        let old = Data(#"{"startAngle":118,"closedAngle":5,"eyeDistance":3.1,"blur":0.055,"darkness":0.9,"perspective":1.1}"#.utf8)
        var settings = try JSONDecoder().decode(FoldSettings.self, from: old)
        XCTAssertEqual(settings.eyeDistance, 3.1)
        XCTAssertEqual(settings.blur, 0.055)
        XCTAssertFalse(settings.hideCursor)
        XCTAssertTrue(settings.animateOnOpen)
        settings.hideCursor = true; settings.animateOnOpen = false
        XCTAssertEqual(try JSONDecoder().decode(FoldSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
    func testProjectionIdentityAndFixedHingeInBothDirections() {
        for x in [0.0, 0.2, 0.5, 1.0] {
            for y in [0.0, 0.6, 1.0] {
                let uv = FoldProjection.sampleUV(x: x, y: y, tilt: 0, eyeDistance: 2.4)
                XCTAssertEqual(uv.x, x, accuracy: 1e-10); XCTAssertEqual(uv.y, y, accuracy: 1e-10)
            }
            for tilt in [-1.2, 1.2] {
                let hinge = FoldProjection.sampleUV(x: x, y: 1, tilt: tilt, eyeDistance: 2.4)
                XCTAssertEqual(hinge.x, x, accuracy: 1e-10); XCTAssertEqual(hinge.y, 1, accuracy: 1e-10)
            }
        }
        let closing = FoldProjection.sampleUV(x: 0.25, y: 0, tilt: 0.8, eyeDistance: 2.4)
        let opening = FoldProjection.sampleUV(x: 0.25, y: 0, tilt: -0.8, eyeDistance: 2.4)
        XCTAssertLessThan(closing.x, 0.25)
        XCTAssertEqual(opening.x, closing.x, accuracy: 1e-10)
        XCTAssertEqual(opening.y, closing.y, accuracy: 1e-10)
        // Sampling must never contract toward the center: that would magnify
        // the rendered desktop past its normal width on outward movement.
        for angle in stride(from: -1.48, through: 1.48, by: 0.04) {
            for y in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let left = FoldProjection.sampleUV(x: 0.25, y: y, tilt: angle, eyeDistance: 2.4)
                let right = FoldProjection.sampleUV(x: 0.75, y: y, tilt: angle, eyeDistance: 2.4)
                XCTAssertLessThanOrEqual(left.x, 0.25)
                XCTAssertGreaterThanOrEqual(right.x, 0.75)
            }
        }
    }
}
