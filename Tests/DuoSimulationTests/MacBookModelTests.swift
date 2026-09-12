import XCTest
import SceneKit
import DuoSimulation
import DuoGraphics

final class MacBookModelTests: XCTestCase {
    func testPhysicalHingeAndExportStudioViews() throws {
        let model = MacBookModel()
        model.setAngle(0)
        let closed = model.hinge.convertPosition(SCNVector3(0,0,2.4),to:nil)
        XCTAssertEqual(closed.y,0.148,accuracy:0.001)
        model.setAngle(90)
        let upright = model.hinge.convertPosition(SCNVector3(0,0,2.4),to:nil)
        XCTAssertEqual(upright.y,2.548,accuracy:0.001)
        XCTAssertEqual(upright.z,-1.18,accuracy:0.001)
        model.screenMaterial.diffuse.contents = DemoArtwork.make(width:1536,height:1000)
        let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
        renderer.scene = model.scene; renderer.pointOfView = model.camera
        let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification/simulator")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for angle in [0.0,45,110,130] {
            model.setAngle(angle)
            let image = renderer.snapshot(atTime:0,with:CGSize(width:1280,height:820),antialiasingMode:.multisampling4X)
            let data = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data:data)?.representation(using:.png,properties:[:]))
            try png.write(to:directory.appendingPathComponent("macbook-\(Int(angle)).png"))
            XCTAssertGreaterThan(png.count,20000)
        }
    }
}
