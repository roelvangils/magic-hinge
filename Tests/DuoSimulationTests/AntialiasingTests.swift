import XCTest
import SceneKit
import DuoSimulation

final class AntialiasingTests: XCTestCase {
    func testSupersamplingReducesSlowMotionShimmer() async throws {
        try await MainActor.run {
            let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
            let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/verification/antialiasing")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var fluctuations: [Double] = []
            for supersampled in [false,true] {
                let scene = SCNScene(); scene.background.contents = NSColor.clear
                let box = SCNBox(width:2,height:0.35,length:1.3,chamferRadius:0.04)
                box.chamferSegmentCount = 12
                box.firstMaterial?.lightingModel = .constant
                box.firstMaterial?.diffuse.contents = NSColor.white
                let object = SCNNode(geometry:box); object.eulerAngles = SCNVector3(0.18,0.13,0.07)
                scene.rootNode.addChildNode(object)
                let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(0,1,4)
                camera.look(at:SCNVector3Zero); scene.rootNode.addChildNode(camera)
                let renderer = SCNRenderer(device:device,options:nil)
                renderer.scene = scene; renderer.pointOfView = camera
                var history: [[Double]] = []
                var fluctuation = 0.0
                for frame in 0..<32 {
                    SCNTransaction.begin(); SCNTransaction.disableActions = true
                    object.position.y = CGFloat(frame)*0.0015
                    SCNTransaction.commit()
                    let scale: CGFloat = supersampled ? 2 : 1
                    let image = renderer.snapshot(atTime:Double(frame)/60,with:CGSize(width:324*scale,height:180*scale),
                        antialiasingMode:SimulationSceneView.antialiasingMode(for:device))
                    let raw = try XCTUnwrap(image.cgImage(forProposedRect:nil,context:nil,hints:nil))
                    let context = try XCTUnwrap(CGContext(data:nil,width:324,height:180,bitsPerComponent:8,bytesPerRow:0,
                        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.interpolationQuality = .high
                    context.draw(raw,in:CGRect(x:0,y:0,width:324,height:180))
                    let pixels = NSBitmapImageRep(cgImage:try XCTUnwrap(context.makeImage()))
                    XCTAssertEqual(pixels.colorAt(x:0,y:0)?.alphaComponent,0)
                    var values: [Double] = []
                    for y in 35..<145 { for x in 40..<284 {
                        values.append(Double(pixels.colorAt(x:x,y:y)?.alphaComponent ?? 0))
                    }}
                    if frame >= 10 {
                        for i in values.indices { fluctuation += abs(values[i]-2*history[1][i]+history[0][i]) }
                    }
                    history.append(values)
                    if history.count > 2 { history.removeFirst() }
                    if frame == 31 {
                        try XCTUnwrap(pixels.representation(using:.png,properties:[:]))
                            .write(to:directory.appendingPathComponent(supersampled ? "motion-supersampled.png" : "motion-msaa.png"))
                    }
                }
                fluctuations.append(fluctuation)
            }
            print("Slow-motion edge fluctuation: MSAA=\(fluctuations[0]), supersampled=\(fluctuations[1])")
            XCTAssertLessThan(fluctuations[1],fluctuations[0],"Supersampling should reduce subpixel edge shimmer")
        }
    }
    func testRefinementImprovesSilhouetteCoverage() async throws {
        try await MainActor.run {
            let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
            let scene = SCNScene(); scene.background.contents = NSColor.clear
            let box = SCNBox(width:2,height:0.35,length:1.3,chamferRadius:0.04)
            box.chamferSegmentCount = 12
            box.firstMaterial?.lightingModel = .constant
            box.firstMaterial?.diffuse.contents = NSColor.white
            let object = SCNNode(geometry:box); object.eulerAngles = SCNVector3(0.18,0.13,0.07)
            scene.rootNode.addChildNode(object)
            let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(0,1,4)
            camera.look(at:SCNVector3Zero); scene.rootNode.addChildNode(camera)
            let renderer = SCNRenderer(device:device,options:nil); renderer.scene = scene; renderer.pointOfView = camera
            let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification/antialiasing")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var coverageLevels: [Int] = []
            for refined in [false,true] {
                renderer.isJitteringEnabled = refined
                let mode: SCNAntialiasingMode = refined ? SimulationSceneView.antialiasingMode(for:device) : .multisampling4X
                let image = renderer.snapshot(atTime:0,with:CGSize(width:324,height:180),antialiasingMode:mode)
                let pixels = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(image.tiffRepresentation)))
                var levels = Set<Int>()
                for y in 0..<pixels.pixelsHigh { for x in 0..<pixels.pixelsWide {
                    let alpha = Int(((pixels.colorAt(x:x,y:y)?.alphaComponent ?? 0)*255).rounded())
                    if alpha > 0 && alpha < 255 { levels.insert(alpha) }
                }}
                XCTAssertEqual(pixels.colorAt(x:0,y:0)?.alphaComponent,0)
                coverageLevels.append(levels.count)
                try XCTUnwrap(pixels.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent(refined ? "refined.png" : "previous-4x.png"))
            }
            XCTAssertGreaterThan(coverageLevels[1],coverageLevels[0],"Refined edges should have finer subpixel coverage than 4x MSAA alone")
            print("Silhouette alpha levels: 4x=\(coverageLevels[0]), refined=\(coverageLevels[1])")
        }
    }
}
