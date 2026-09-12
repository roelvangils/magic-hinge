import XCTest
@testable import DuoCore

final class LocalizationTests: XCTestCase {
    func testTranslationPlistsHaveMatchingKeysAndFormatArguments() throws {
        let en = try XCTUnwrap(L10n.strings(for:"en"))
        let nl = try XCTUnwrap(L10n.strings(for:"nl"))
        XCTAssertEqual(Set(en.keys),Set(nl.keys))
        XCTAssertEqual(en["Settings"],"Settings")
        XCTAssertEqual(nl["Settings"],"Instellingen")
        let format = try NSRegularExpression(pattern:"%[0-9.]*[df@]")
        func tokens(_ s: String) -> [String] {
            format.matches(in:s,range:NSRange(s.startIndex...,in:s)).map { (s as NSString).substring(with:$0.range) }
        }
        for key in en.keys {
            XCTAssertFalse(nl[key]!.isEmpty,key)
            XCTAssertEqual(tokens(en[key]!),tokens(nl[key]!),key)
        }
    }
    func testOpeningAndClosingSettingsMigrateAndPersistIndependently() throws {
        let old = Data(#"{"animateOnOpen":false,"blur":0.14}"#.utf8)
        var settings = try JSONDecoder().decode(FoldSettings.self,from:old)
        XCTAssertFalse(settings.animateOnOpen)
        XCTAssertTrue(settings.animateOnClose)
        XCTAssertEqual(settings.blur,0.14)
        settings.animateOnClose = false
        XCTAssertEqual(settings,try JSONDecoder().decode(FoldSettings.self,from:JSONEncoder().encode(settings)))
    }
    func testDirectionSwitchesDoNotBlockTheOtherDirection() {
        var session = FoldSession()
        _ = session.receive(angle:90,at:0)
        XCTAssertEqual(session.receive(angle:0,at:0.1,animateClosing:false),.none)
        XCTAssertEqual(session.receive(angle:10,at:0.2,animateClosing:false),.capture)
        _ = session.receive(angle:45,at:0.3,animateClosing:false)
        XCTAssertEqual(session.frame(at:1.2).degrees,0)
        session.reset()
        _ = session.receive(angle:0,at:0)
        XCTAssertEqual(session.receive(angle:10,at:0.1,animateOpening:false),.none)
        XCTAssertEqual(session.receive(angle:5,at:0.2,animateOpening:false),.capture)
        let before = session.frame(at:0.3).degrees
        _ = session.receive(angle:20,at:0.31,animateOpening:false)
        XCTAssertEqual(session.phase,.returning)
        XCTAssertLessThan(session.frame(at:0.5).degrees,before)
        XCTAssertEqual(session.frame(at:1).degrees,0)
    }
    func testDisabledDirectionsNeverCapture() {
        var session = FoldSession()
        for (index,angle) in [90.0,60,20,0,10,40,90,110,80].enumerated() {
            XCTAssertNotEqual(session.receive(angle:angle,at:Double(index)*0.1,animateOpening:false,animateClosing:false),.capture)
            XCTAssertEqual(session.degrees,0)
        }
    }
}
