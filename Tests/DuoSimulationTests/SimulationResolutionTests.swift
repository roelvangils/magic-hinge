import XCTest
import AppKit
import SceneKit
import DuoSimulation

final class SimulationResolutionTests: XCTestCase {
    @MainActor func testBackingLayerActuallyRendersAtSupersampledResolution() throws {
        let view = SimulationSceneView(frame:NSRect(x:0,y:0,width:324,height:180))
        let model = MacBookModel(); view.scene = model.scene; view.pointOfView = model.camera
        view.wantsLayer = true
        view.layout()
        let image = view.snapshot()
        let pixels = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(pixels.pixelsWide,648)
        XCTAssertEqual(pixels.pixelsHigh,360)
        XCTAssertEqual(view.projectPoint(SCNVector3Zero).x,162,accuracy:0.1,"Interaction projection stays in logical view coordinates")
        XCTAssertEqual(SimulationSceneView.renderScale(backingScale:2,size:CGSize(width:800,height:500)),4)
        let large = SimulationSceneView.renderScale(backingScale:2,size:CGSize(width:1800,height:1100))
        XCTAssertGreaterThanOrEqual(large,2)
        XCTAssertLessThanOrEqual(1800*large,4096)
        XCTAssertLessThanOrEqual(1800*1100*large*large,8_000_001)
    }
}
