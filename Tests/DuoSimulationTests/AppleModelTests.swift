import XCTest
import SceneKit
import DuoSimulation
import DuoGraphics

final class AppleModelTests: XCTestCase {
    func testHardwareDetectionAndValidCombinations() {
        XCTAssertEqual(MacBookConfiguration.detected(productName:"MacBook Pro (14-inch, M5 Max)")?.size,14)
        XCTAssertEqual(MacBookConfiguration.detected(productName:"MacBook Air (15-inch, M4)")?.family,.air)
        XCTAssertEqual(MacBookConfiguration.detected(productName:"MacBook Neo")?.family,.neo)
        XCTAssertNil(MacBookConfiguration.detected(productName:"MacBook Pro (13-inch, M1)"))
        XCTAssertNil(MacBookConfiguration.detected(productName:"Mac Studio"))
        XCTAssertNil(MacBookConfiguration.detected(productName:"MacBook Air"))
        XCTAssertEqual(MacBookConfiguration(family:.neo,size:16,color:.spaceBlack),.init(family:.neo,size:13,color:.silver))
        let configurations = MacBookFamily.allCases.flatMap { family in family.sizes.flatMap { size in family.colors.map { MacBookConfiguration(family:family,size:size,color:$0) } } }
        XCTAssertEqual(configurations.count,16)
        XCTAssertEqual(Set(configurations.map(\.assetURL)).count,12)
        XCTAssertTrue(configurations.allSatisfy { $0.assetURL.host == "www.apple.com" && $0.assetURL.pathExtension == "usdz" })
    }
    /// Opt-in fixture validation: original Apple assets are downloaded separately, never bundled.
    func testOfficialAssetsArticulateAndRender() async throws {
        guard let path = ProcessInfo.processInfo.environment["DUO_APPLE_MODELS"] else { throw XCTSkip("Set DUO_APPLE_MODELS to a cache containing the 12 official USDZ files") }
        let cache = AppleModelCache(directory:URL(fileURLWithPath:path))
        let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification/apple-models")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for family in MacBookFamily.allCases {
            for size in family.sizes {
                for color in family.colors {
                    let config = MacBookConfiguration(family:family,size:size,color:color)
                    let url = try await cache.modelURL(for:config)
                    let model = try MacBookModel(assetURL:url,configuration:config)
                    XCTAssertTrue(model.isOfficialModel)
                    XCTAssertEqual(model.screenMaterial.lightingModel,.constant)
                    model.screenMaterial.diffuse.contents = DemoArtwork.make(width:1536,height:1000)
                    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
                    renderer.scene = model.scene; renderer.pointOfView = model.camera
                    for angle in [0.0,45,110] {
                        model.setAngle(angle)
                        if angle == 0, let screen = model.screenNode {
                            let b = screen.boundingBox
                            let center = screen.convertPosition(SCNVector3((b.min.x+b.max.x)/2,(b.min.y+b.max.y)/2,(b.min.z+b.max.z)/2),to:model.product)
                            // A closed display lies near the top of the base. The rear hinge housing
                            // extends up to 3 mm above the display plane; a wrong Pro pivot exceeds this.
                            XCTAssertLessThan(model.contactEdgeBounds.boundingBox.max.y-model.contactEdgeBounds.boundingBox.min.y,0.3)
                            let baseTop = model.contactEdgeBounds.boundingBox.max.y
                            XCTAssertGreaterThan(center.y, baseTop - 0.03, "Closed lid below keyboard: \(config)")
                            XCTAssertLessThan(center.y, baseTop + 0.10, "Closed lid floats above keyboard: \(config)")
                        }
                        XCTAssertEqual(model.hinge.eulerAngles.x,-angle * .pi / 180,accuracy:0.00001)
                        let image = renderer.snapshot(atTime:0,with:CGSize(width:1000,height:625),antialiasingMode:.multisampling4X)
                        let data = try XCTUnwrap(image.tiffRepresentation)
                        let pixels = try XCTUnwrap(NSBitmapImageRep(data:data))
                        XCTAssertEqual(pixels.colorAt(x:0,y:0)?.alphaComponent,0,"No background should be rendered")
                        let png = try XCTUnwrap(NSBitmapImageRep(data:data)?.representation(using:.png,properties:[:]))
                        try png.write(to:directory.appendingPathComponent("\(family.rawValue)-\(size)-\(color.rawValue)-\(Int(angle)).png"))
                        XCTAssertGreaterThan(png.count,20000)
                    }
                    print("Verified Apple model: \(config.title) \(color.rawValue)")
                }
            }
        }
    }
}
