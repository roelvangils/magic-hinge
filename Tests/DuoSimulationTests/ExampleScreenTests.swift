import XCTest
import DuoSimulation

final class ExampleScreenTests: XCTestCase {
    func testBothAppearanceResourcesDecodeAndDiffer() throws {
        let light = try ExampleScreen.image(dark:false)
        let dark = try ExampleScreen.image(dark:true)
        XCTAssertEqual(light.width,dark.width)
        XCTAssertEqual(light.height,dark.height)
        XCTAssertGreaterThan(light.width,1500)
        XCTAssertGreaterThan(light.height,900)
        XCTAssertFalse(light === dark)
        XCTAssertEqual(light.dataProvider?.data, try ExampleScreen.image(dark:false).dataProvider?.data)
        XCTAssertNotEqual(light.dataProvider?.data,dark.dataProvider?.data)
    }
}
