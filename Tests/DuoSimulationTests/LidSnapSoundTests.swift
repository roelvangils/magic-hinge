import XCTest
@testable import DuoSimulation

final class LidSnapSoundTests: XCTestCase {
    func testOnlyFullyClosedPresentedLidTriggersOnce() {
        var contact = LidClosureContact()
        for angle in [0.0,0,90,45,1,0.2,0.01] { XCTAssertFalse(contact.receive(angle:angle)) }
        XCTAssertTrue(contact.receive(angle:0))
        for angle in [0.0,0.1,0,0.4,0,Double.nan,-1] { XCTAssertFalse(contact.receive(angle:angle)) }
        XCTAssertFalse(contact.receive(angle:1))
        XCTAssertTrue(contact.receive(angle:0))
    }
    func testResetDoesNotPlayOnLaunchOrResumeClosed() {
        var contact = LidClosureContact()
        _ = contact.receive(angle:90)
        contact.reset()
        XCTAssertFalse(contact.receive(angle:0))
    }
    func testSnapAnticipatesAnimatedContactByTwoHundredMilliseconds() throws {
        for slow in [false,true] {
            let transition = LidTransition(from:90,target:0,at:0,slowMotion:slow)
            var contact = LidClosureContact()
            var shown = 90.0
            var sounds: [Double] = []
            var closedAt: Double?
            for step in 0...300 {
                let time = Double(step)/60
                let target = transition.angle(at:time)
                shown += (target-shown)*(1-exp(-(1.0/60)/0.018))
                if abs(shown-target) < 0.005 { shown = target }
                let soon = LidClosureContact.closingSoon(presented:shown,target:target,transition:transition,at:time)
                if contact.receive(angle:shown,closingSoon:soon) { sounds.append(time) }
                if closedAt == nil && shown == 0 { closedAt = time }
            }
            XCTAssertEqual(sounds.count,1)
            XCTAssertEqual(try XCTUnwrap(closedAt)-XCTUnwrap(sounds.first),0.2,accuracy:0.035)
        }
        XCTAssertFalse(LidClosureContact.closingSoon(presented:20,target:5,transition:nil,at:0))
        XCTAssertTrue(LidClosureContact.closingSoon(presented:20,target:0,transition:nil,at:0))
    }
    @MainActor func testBundledAudioPreparesOffMainAndResumesAfterPause() async throws {
        let sound = try LidSnapSound(volume:0)
        let prepared = await sound.isPrepared()
        XCTAssertTrue(prepared)
        sound.stop()
        let stopped = await sound.isPrepared()
        XCTAssertFalse(stopped)
        sound.activate()
        let resumed = await sound.isPrepared()
        XCTAssertTrue(resumed)
        for _ in 0..<2 {
            let began = ProcessInfo.processInfo.systemUptime
            sound.play()
            let submission = ProcessInfo.processInfo.systemUptime-began
            XCTAssertLessThan(submission,0.016,"Audio submission must not consume an animation frame")
            let ready = await sound.isPrepared()
            XCTAssertTrue(ready)
        }
        sound.stop()
    }
}
