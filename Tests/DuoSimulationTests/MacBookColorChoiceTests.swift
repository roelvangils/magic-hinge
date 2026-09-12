import XCTest
@testable import DuoSimulation

final class MacBookColorChoiceTests: XCTestCase {
    func testAutomaticChoiceSurvivesPersistenceAndResolvesBothProSizes() {
        let choice = MacBookColorChoice(storedValue:MacBookColorChoice.system.storedValue,fallback:.silver)
        XCTAssertEqual(choice,.system)
        for size in [14,16] {
            let light = MacBookConfiguration(family:.pro,size:size,color:choice.resolved(for:.pro,dark:false))
            let dark = MacBookConfiguration(family:.pro,size:size,color:choice.resolved(for:.pro,dark:true))
            XCTAssertEqual(light.color,.silver)
            XCTAssertEqual(dark.color,.spaceBlack)
            XCTAssertEqual(light.size,dark.size)
            XCTAssertEqual(choice.storedValue,"system")
        }
    }
    func testExistingManualChoicesIgnoreAppearance() {
        for family in MacBookFamily.allCases {
            for color in family.colors {
                let choice = MacBookColorChoice(storedValue:color.rawValue,fallback:family.colors[0])
                XCTAssertEqual(choice.resolved(for:family,dark:false),color)
                XCTAssertEqual(choice.resolved(for:family,dark:true),color)
                XCTAssertEqual(choice.storedValue,color.rawValue)
            }
        }
    }
    func testMissingOrUnknownPreferencePreservesDetectedFallback() {
        for stored in [nil,"invalid"] as [String?] {
            XCTAssertEqual(MacBookColorChoice(storedValue:stored,fallback:.spaceBlack),.fixed(.spaceBlack))
        }
    }
}
