import XCTest
import DuoCore

final class WindowCaptureIDTests: XCTestCase {
    func testUnrealizedWindowsDoNotTrapOrBecomeCaptureIDs() {
        let numbers = [Int.min, -1, 0, 42, Int(UInt32.max), Int(UInt32.max) + 1, Int.max]
        XCTAssertEqual(numbers.compactMap { WindowCaptureID.from(windowNumber:$0) },[42,UInt32.max])
    }
}
