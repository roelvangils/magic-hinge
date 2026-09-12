import XCTest
import AppKit
@testable import DuoGraphics

final class ProceduralStarsTests: XCTestCase {
    func testStarsStayInSkyAndDoNotSynchronizeOrBlinkOut() {
        let stars = SkyStar.makeSky()
        XCTAssertEqual(stars.map(\.x),SkyStar.makeSky().map(\.x))
        XCTAssertTrue(stars.allSatisfy { $0.y < 0.385 && $0.y > 0 && $0.x > 0 && $0.x < 1 })
        XCTAssertGreaterThan(Set(stars.map(\.period)).count,150)
        for star in stars {
            XCTAssertEqual(star.opacity(at:0),star.opacity(at:star.period),accuracy:1e-12)
            let cycle = (0...120).map { star.opacity(at:Double($0)/120*star.period) }
            XCTAssertGreaterThan((cycle.max()!-cycle.min()!)/star.brightness,0.55)
            for step in 0...120 {
                let time = Double(step)/10
                XCTAssertGreaterThan(star.opacity(at:time),0)
                XCTAssertLessThan(star.opacity(at:time),1)
                XCTAssertLessThan(abs(star.opacity(at:time+1.0/60)-star.opacity(at:time)),0.022)
            }
        }
    }
    func testStarCoordinatesTrackAspectFillCropping() {
        let image = CGSize(width:6016,height:3900)
        for size in [CGSize(width:960,height:714),CGSize(width:1600,height:700),CGSize(width:960,height:1000)] {
            let rect = SkyStar.wallpaperRect(imageSize:image,viewSize:size)
            XCTAssertEqual(rect.midX,size.width/2,accuracy:0.001)
            XCTAssertEqual(rect.midY,size.height/2,accuracy:0.001)
            XCTAssertGreaterThanOrEqual(rect.width+0.001,size.width)
            XCTAssertGreaterThanOrEqual(rect.height+0.001,size.height)
            XCTAssertEqual(rect.width/rect.height,image.width/image.height,accuracy:1e-10)
        }
    }
    @MainActor func testLayerClockPausesWithoutDiscardingStarsAndNeverInterceptsGestures() {
        let view = StarSkyView(frame:CGRect(x:0,y:0,width:1100,height:714))
        XCTAssertNil(view.hitTest(CGPoint(x:100,y:100)))
        XCTAssertEqual(view.sky.speed,0,"Detached stars must not animate")
        view.setRunning(true)
        XCTAssertEqual(view.sky.speed,1)
        view.setRunning(false)
        XCTAssertEqual(view.sky.speed,0)
        let frozen = view.sky.timeOffset
        view.setRunning(false)
        XCTAssertEqual(view.sky.timeOffset,frozen)
        XCTAssertEqual(view.sky.sublayers?.count,view.stars.count+1)
        view.setRunning(true)
        XCTAssertEqual(view.sky.convertTime(CACurrentMediaTime(),from:nil),frozen,accuracy:0.02)
        view.stop()
        XCTAssertEqual(view.sky.speed,0)
    }
    @MainActor func testRenderSky() throws {
        let view = StarSkyView(frame:CGRect(x:0,y:0,width:1100,height:714))
        view.layoutSubtreeIfNeeded()
        for (index,dot) in (view.sky.sublayers ?? []).prefix(view.stars.count).enumerated() {
            dot.removeAllAnimations(); dot.opacity = Float(view.stars[index].opacity(at:2))
        }
        let context = try XCTUnwrap(CGContext(data:nil,width:2200,height:1428,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x:2,y:2)
        context.setFillColor(CGColor(red:0.035,green:0.07,blue:0.12,alpha:1))
        context.fill(CGRect(x:0,y:0,width:1100,height:714))
        if let wallpaper = NSImage(contentsOfFile:"Sources/MagicHinge/Resources/DuoNightStarless.jpg")?.cgImage(forProposedRect:nil,context:nil,hints:nil) {
            let rect = SkyStar.wallpaperRect(imageSize:CGSize(width:wallpaper.width,height:wallpaper.height),viewSize:view.bounds.size)
            context.draw(wallpaper,in:rect)
        }
        view.layer?.render(in:context)
        let image = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]))
        let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try png.write(to:directory.appendingPathComponent("procedural-stars.png"))
    }
}
