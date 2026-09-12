import XCTest
import AppKit
@testable import DuoSimulation

final class LidKeyboardTests: XCTestCase {
    private func key(_ code: UInt16, repeat repeated: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,
            context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeated,keyCode:code)!
    }
    @MainActor func testArrowAndPageAliasesAccumulateFiveDegreeStepsIncludingRepeat() {
        let view = SimulationSceneView()
        var motion = LidKeyboardMotion(angle:0)
        view.onKeyboardStep = { motion.step(by:$0) }
        for code: UInt16 in [126,116] {
            XCTAssertTrue(view.handleLidKey(key(code)))
            XCTAssertTrue(view.handleLidKey(key(code,repeat:true)))
        }
        XCTAssertEqual(motion.target,20)
        XCTAssertEqual(motion.angle,0,"Input must request a transition instead of jumping the displayed angle")
        for code: UInt16 in [125,121] { XCTAssertTrue(view.handleLidKey(key(code))) }
        XCTAssertEqual(motion.target,10)
        for _ in 0..<40 { XCTAssertTrue(view.handleLidKey(key(116,repeat:true))) }
        XCTAssertEqual(motion.target,130)
        for _ in 0..<40 { XCTAssertTrue(view.handleLidKey(key(121,repeat:true))) }
        XCTAssertEqual(motion.target,0)
    }
    @MainActor func testSpaceReturnAndEnterShareToggleAndShiftButNeverRepeat() {
        let view = SimulationSceneView()
        var slowMotion: [Bool] = []
        view.onToggleLid = { slowMotion.append($0) }
        for code: UInt16 in [49,36,76] {
            XCTAssertTrue(view.handleLidKey(key(code)))
            XCTAssertTrue(view.handleLidKey(key(code,repeat:true)))
            XCTAssertTrue(view.handleLidKey(key(code,modifiers:.shift)))
        }
        XCTAssertEqual(slowMotion,[false,true,false,true,false,true])
    }
    @MainActor func testHomeAndEndAlwaysChooseExplicitEndpoints() {
        let view = SimulationSceneView()
        var endpoints: [Double] = [], slowMotion: [Bool] = []
        view.onLidEndpoint = { endpoints.append($0); slowMotion.append($1) }
        for code: UInt16 in [115,119] {
            XCTAssertTrue(view.handleLidKey(key(code)))
            XCTAssertTrue(view.handleLidKey(key(code,repeat:true)))
            XCTAssertTrue(view.handleLidKey(key(code,modifiers:.shift)))
        }
        XCTAssertEqual(endpoints,[90,90,0,0])
        XCTAssertEqual(slowMotion,[false,true,false,true])
    }
    @MainActor func testShortcutsAndOtherKeysPassThrough() {
        let view = SimulationSceneView()
        var changes = 0
        view.onKeyboardStep = {_ in changes += 1}; view.onToggleLid = {_ in changes += 1}
        view.onLidEndpoint = {_,_ in changes += 1}
        for modifier: NSEvent.ModifierFlags in [.command,.control,.option] {
            for code: UInt16 in [126,125,116,121,115,119,49,36,76] {
                XCTAssertFalse(view.handleLidKey(key(code,modifiers:modifier)))
            }
        }
        XCTAssertFalse(view.handleLidKey(key(53)))
        XCTAssertFalse(view.handleLidKey(key(48)))
        XCTAssertEqual(changes,0)
    }
}
