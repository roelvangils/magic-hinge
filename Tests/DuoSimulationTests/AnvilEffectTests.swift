import XCTest
import AppKit
import SceneKit
@testable import DuoSimulation

final class AnvilEffectTests: XCTestCase {
    @MainActor func testOneContactBurstNoLaunchBurstAndBoundedCleanup() throws {
        let view = AnvilBurstView(frame:CGRect(x:0,y:0,width:900,height:600))
        var contact = LidClosureContact()
        for angle in [0.0,0,90,45,0.1] { XCTAssertFalse(contact.receive(angle:angle)) }
        XCTAssertTrue(contact.receive(angle:0))
        view.begin(left:CGPoint(x:150,y:150),right:CGPoint(x:750,y:150),at:10)
        XCTAssertTrue(view.isActive)
        XCTAssertNil(view.hitTest(CGPoint(x:300,y:150)))
        view.advance(at:10.25)
        XCTAssertTrue(try XCTUnwrap(view.layer?.sublayers).contains { $0.opacity > 0.1 })
        XCTAssertFalse(contact.receive(angle:0))
        view.begin(left:CGPoint(x:150,y:150),right:CGPoint(x:750,y:150),at:10.3)
        XCTAssertEqual(view.layer?.sublayers?.count,view.particles.count,"Repeated closures must not accumulate old layers")
        view.advance(at:12)
        XCTAssertFalse(view.isActive)
        XCTAssertTrue(view.isHidden)
        XCTAssertTrue(view.layer?.sublayers?.isEmpty ?? true)
        view.begin(left:CGPoint(x:150,y:150),right:CGPoint(x:750,y:150),at:13)
        view.cancel()
        XCTAssertFalse(view.isActive)
        XCTAssertTrue(view.layer?.sublayers?.isEmpty ?? true)
    }
    func testAnvilAddsWeightToGentleClosureAndSettlesWithoutDoubleImpulse() {
        var impact = LidImpactResponse()
        _ = impact.frame(angle:90,at:0)
        _ = impact.frame(angle:0.1,at:2)
        XCTAssertFalse(impact.isActive)
        _ = impact.frame(angle:0,at:2.02)
        impact.strike()
        XCTAssertEqual(impact.velocity,-2.1)
        impact.strike()
        XCTAssertEqual(impact.velocity,-2.1,"A stronger slam must not be compounded")
        var minimum = 0.0
        for step in 1...180 { minimum = min(minimum,impact.frame(angle:0,at:2.02+Double(step)/120)) }
        XCTAssertLessThan(minimum,-0.04)
        XCTAssertGreaterThan(minimum,-0.1)
        XCTAssertFalse(impact.isActive)
    }
    /// Inspect real composited sprites against the official model, at deterministic contact times.
    @MainActor func testRenderContactFrames() async throws {
        guard let path = ProcessInfo.processInfo.environment["DUO_APPLE_MODELS"] else {
            throw XCTSkip("Set DUO_APPLE_MODELS to render the official MacBook with the burst")
        }
        for config in [MacBookConfiguration(family:.pro,size:14,color:.silver),
                       .init(family:.pro,size:16,color:.silver),
                       .init(family:.air,size:13,color:.midnight),
                       .init(family:.neo,size:13,color:.silver)] {
        let url = try await AppleModelCache(directory:URL(fileURLWithPath:path)).modelURL(for:config)
        let model = try MacBookModel(assetURL:url,configuration:config)
        model.setAngle(0)
        let view = SimulationSceneView(frame:CGRect(x:0,y:0,width:1000,height:625))
        view.reduceMotion = false // Render fixtures independently of the test host accessibility preference.
        view.scene = model.scene; view.pointOfView = model.camera
        view.bodyNode = model.bodyInteractionBounds
        view.contactNode = model.contactEdgeBounds
        view.backgroundColor = .clear
        view.antialiasingMode = SimulationSceneView.antialiasingMode(for:view.device)
        _ = view.snapshot()
        view.showAnvil(at:0)
        let burst = try XCTUnwrap(view.subviews.compactMap { $0 as? AnvilBurstView }.first)
        let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification/anvil")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let wallpaper = try XCTUnwrap(NSImage(contentsOfFile:"Sources/MagicHinge/Resources/DesertWallpaper.jpg")?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        var impact = LidImpactResponse()
        _ = impact.frame(angle:0,at:0); impact.strike()
        var time = 0.0
        for frameTime in [0.0,0.12,0.3,0.6,1.0,1.7] {
            while time < frameTime {
                time = min(frameTime,time+1.0/120)
                model.setFloatingOffset(0,impactOffset:impact.frame(angle:0,at:time))
            }
            view.advanceAnvil(at:frameTime)
            let context = try XCTUnwrap(CGContext(data:nil,width:2000,height:1250,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x:2,y:2)
            let bounds = CGRect(x:0,y:0,width:1000,height:625)
            context.draw(wallpaper,in:bounds)
            context.setFillColor(CGColor(gray:0,alpha:0.32)); context.fill(bounds)
            let scene = try XCTUnwrap(view.snapshot().cgImage(forProposedRect:nil,context:nil,hints:nil))
            context.draw(scene,in:bounds)
            burst.layer?.render(in:context)
            let image = try XCTUnwrap(context.makeImage())
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]))
            try png.write(to:directory.appendingPathComponent("\(config.family.rawValue)-\(config.size)-contact-\(Int(frameTime*1000)).png"))
        }
        XCTAssertFalse(view.isAnvilActive)
        }
    }
}
