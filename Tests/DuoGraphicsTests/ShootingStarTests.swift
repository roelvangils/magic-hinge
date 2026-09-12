import XCTest
import AppKit
@testable import DuoGraphics

final class ShootingStarTests: XCTestCase {
    func testSparseIrregularScheduleHasNoOverlapIncludingLoopBoundary() {
        for seed: UInt64 in [1,42,100,9999] {
            let schedule = ShootingStar.schedule(seed:seed)
            XCTAssertEqual(schedule.stars.count,7)
            XCTAssertTrue((8...14).contains(schedule.stars[0].start))
            for (i,star) in schedule.stars.enumerated() {
                let next = i+1 < schedule.stars.count ? schedule.stars[i+1].start : schedule.duration+schedule.stars[0].start
                XCTAssertTrue((24...42).contains(next-star.start))
                XCTAssertTrue((0.65...0.95).contains(star.duration))
                XCTAssertLessThan(star.start+star.duration,schedule.duration)
            }
        }
    }
    func testPathsStayInsideVisibleSkyAcrossWindowShapes() throws {
        for size in [CGSize(width:960,height:714),CGSize(width:1600,height:700),CGSize(width:960,height:1000)] {
            let wallpaper = SkyStar.wallpaperRect(imageSize:CGSize(width:6016,height:3900),viewSize:size)
            let mountainTop = size.height-(wallpaper.minY+wallpaper.height*0.385)
            for seed: UInt64 in 1...20 {
                for star in ShootingStar.schedule(seed:seed).stars {
                    let path = try XCTUnwrap(star.path(wallpaper:wallpaper,viewport:size))
                    for point in [path.start,path.end] {
                        XCTAssertTrue(CGRect(origin:.zero,size:size).contains(point))
                        XCTAssertGreaterThan(point.y,mountainTop)
                    }
                    XCTAssertLessThan(path.end.y,path.start.y)
                }
            }
        }
    }
    @MainActor func testRenderTrailAndPauseWithSky() throws {
        let view = StarSkyView(frame:CGRect(x:0,y:0,width:1100,height:714))
        view.layoutSubtreeIfNeeded()
        let layer = try XCTUnwrap(view.shootingSky.sublayers?.first as? ShootingStarLayer)
        let animation = try XCTUnwrap(layer.animation(forKey:"shootingStar") as? CAAnimationGroup)
        XCTAssertEqual(animation.repeatCount,.infinity)
        XCTAssertEqual(animation.beginTime,0.000001)
        view.setRunning(true); view.stop()
        XCTAssertEqual(view.sky.speed,0)
        XCTAssertTrue(view.shootingSky.superlayer === view.sky,"The streak must inherit the same paused clock")
        XCTAssertNil(view.hitTest(CGPoint(x:200,y:80)))
        let viewport = view.bounds.size
        let wallpaperRect = SkyStar.wallpaperRect(imageSize:view.imageSize,viewSize:viewport)
        let star = view.shootingSchedule.stars[0]
        let path = try XCTUnwrap(star.path(wallpaper:wallpaperRect,viewport:viewport))
        layer.removeAllAnimations()
        layer.position = CGPoint(x:(path.start.x+path.end.x)/2,y:(path.start.y+path.end.y)/2)
        layer.opacity = 0.85
        let context = try XCTUnwrap(CGContext(data:nil,width:2200,height:1428,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x:2,y:2)
        let wallpaper = try XCTUnwrap(NSImage(contentsOfFile:"Sources/MagicHinge/Resources/DuoNightStarless.jpg")?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        context.draw(wallpaper,in:wallpaperRect)
        view.layer?.render(in:context)
        let image = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]))
        let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try png.write(to:directory.appendingPathComponent("shooting-star.png"))
    }
}
