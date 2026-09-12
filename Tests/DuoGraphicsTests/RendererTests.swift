import XCTest
import AppKit
import MetalKit
import DuoCore
@testable import DuoGraphics

final class RendererTests: XCTestCase {
    func testSimulationTextureMatchesOffscreenMetalOutput() throws {
        let renderer = try FoldRenderer()
        try renderer.setImage(DemoArtwork.make(width:512,height:320))
        renderer.foldDegrees = 22
        let expected = bytes(try renderer.renderOffscreen(width:512,height:320))
        let finished = expectation(description:"GPU texture ready for SceneKit")
        var output: Result<MTLTexture,Error>?
        renderer.renderTexture(width:512,height:320) { result in output = result; finished.fulfill() }
        wait(for:[finished],timeout:5)
        let texture = try XCTUnwrap(output).get()
        XCTAssertEqual(texture.storageMode,.private)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm_srgb,width:512,height:320,mipmapped:false)
        descriptor.storageMode = .shared
        let readback = try XCTUnwrap(renderer.device.makeTexture(descriptor:descriptor))
        let command = try XCTUnwrap(renderer.device.makeCommandQueue()?.makeCommandBuffer())
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from:texture,to:readback); blit.endEncoding()
        command.commit(); command.waitUntilCompleted()
        var actual = [UInt8](repeating:0,count:512*320*4)
        readback.getBytes(&actual,bytesPerRow:512*4,from:MTLRegionMake2D(0,0,512,320),mipmapLevel:0)
        var maximumError = 0
        for i in stride(from:0,to:actual.count,by:4) {
            for c in 0..<3 { maximumError = max(maximumError,abs(Int(actual[i+2-c])-Int(expected[i+c]))) }
        }
        XCTAssertLessThanOrEqual(maximumError,1,"The simulated screen must use the same shader, colors and orientation.")
    }
    func testScreenshotCrossfadePreservesEndpointsAndBlendsInLinearLight() throws {
        func solid(_ white: CGFloat) -> CGImage {
            let context = CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray:white,alpha:1)); context.fill(CGRect(x:0,y:0,width:64,height:64))
            return context.makeImage()!
        }
        let renderer = try FoldRenderer()
        try renderer.setImage(solid(0))
        try renderer.setImage(solid(1),crossfade:true)
        XCTAssertTrue(renderer.hasSourceTransition)
        XCTAssertEqual(bytes(try renderer.renderOffscreen(width:64,height:64))[0],0)
        renderer.setSourceBlend(0.5)
        let middle = bytes(try renderer.renderOffscreen(width:64,height:64))[0]
        XCTAssertEqual(Double(middle),188,accuracy:2)
        renderer.setSourceBlend(1)
        XCTAssertEqual(bytes(try renderer.renderOffscreen(width:64,height:64))[0],255)
        XCTAssertFalse(renderer.hasSourceTransition)
        try renderer.setImage(solid(0))
        XCTAssertFalse(renderer.hasSourceTransition)
        XCTAssertEqual(bytes(try renderer.renderOffscreen(width:64,height:64))[0],0)
    }
    private func bytes(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width*image.height*4))
    }
    private func stripeImage(width: Int = 512, height: Int = 320) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            let c: CGFloat = x % 16 < 8 ? 0.95 : 0.05
            ctx.setFillColor(CGColor(gray: c, alpha: 1)); ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }
    func testStandaloneMetalViewHasVisibleBackingLayer() throws {
        let renderer = try FoldRenderer()
        let view = MTKView(frame: .zero, device: renderer.device)
        renderer.configure(view)
        XCTAssertTrue(view.wantsLayer, "A standalone AppKit overlay must explicitly use a backing layer.")
        let layer = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertGreaterThanOrEqual(layer.contentsScale, 1, "Zero scale produced a black full-screen overlay despite successful GPU frames.")
    }
    func testGPUIdentityOrientationAndClosedBlack() throws {
        let renderer = try FoldRenderer()
        let source = DemoArtwork.make(width: 512, height: 320)
        try renderer.setImage(source)
        renderer.foldDegrees = 0
        let result = bytes(try renderer.renderOffscreen(width: 512, height: 320))
        let original = bytes(source)
        let meanError = zip(result, original).enumerated().filter { $0.offset % 4 != 3 }
            .reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(512*320*3)
        XCTAssertLessThan(meanError, 1.5, "At zero tilt the exact desktop, colors and orientation must survive.")
        renderer.foldDegrees = 85
        let black = bytes(try renderer.renderOffscreen(width: 512, height: 320))
        XCTAssertTrue(black.enumerated().filter { $0.offset % 4 != 3 }.allSatisfy { $0.element == 0 })
    }
    func testGPUBlurIsStrongerAtTopAndHingeRemainsSharp() throws {
        let renderer = try FoldRenderer()
        try renderer.setImage(stripeImage())
        renderer.settings.darkness = 0
        renderer.foldDegrees = 40
        let result = bytes(try renderer.renderOffscreen(width: 512, height: 320))
        func contrast(row: Int) -> Double {
            let values = (150..<360).map { Double(result[(row*512+$0)*4]) }
            let mean = values.reduce(0,+) / Double(values.count)
            return sqrt(values.reduce(0) { $0 + pow($1-mean,2) } / Double(values.count))
        }
        // bytes(CGImage) keeps row 0 at the top; the last row is adjacent to the hinge.
        XCTAssertLessThan(contrast(row: 40), contrast(row: 318) * 0.45)
        XCTAssertGreaterThan(contrast(row: 318), 50)
    }
    func testIOSurfaceCapturePathPreservesColorsAndOrientation() throws {
        let source = DemoArtwork.make(width: 512, height: 320)
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 512, 320, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: 512, height: 320,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
        context.draw(source, in: CGRect(x: 0, y: 0, width: 512, height: 320))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let renderer = try FoldRenderer()
        try renderer.setPixelBuffer(pixels)
        let original = bytes(source)
        let result = bytes(try renderer.renderOffscreen(width: 512, height: 320))
        let error = zip(original, result).enumerated().filter { $0.offset % 4 != 3 }
            .reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(512*320*3)
        XCTAssertLessThan(error, 1.5, "Zero-copy capture must have the same sRGB colors and orientation as the CPU path.")
    }
    func testStrongTopGradientKeepsHingeBrightInBothDirections() throws {
        let renderer = try FoldRenderer()
        renderer.settings.darkness = 0.86
        let context = CGContext(data: nil, width: 512, height: 320, bitsPerComponent: 8, bytesPerRow: 512*4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 512, height: 320))
        try renderer.setImage(context.makeImage()!)
        renderer.settings.blur = 0
        for degrees in [-25.0, 25] {
            renderer.foldDegrees = degrees
            let image = bytes(try renderer.renderOffscreen(width: 512, height: 320))
            XCTAssertLessThan(image[(20*512+256)*4], 40, "Top should already be nearly black at a 25-degree movement.")
            XCTAssertGreaterThan(image[(318*512+256)*4], 235, "The hinge must remain bright.")
            XCTAssertGreaterThan(image[(240*512+256)*4], image[(80*512+256)*4])
        }
    }
    func testOpeningAlsoBlursAndPerspectiveControlDoesNotDisableBlur() throws {
        let renderer = try FoldRenderer()
        try renderer.setImage(stripeImage())
        renderer.settings.darkness = 0; renderer.settings.perspective = 0
        renderer.foldDegrees = 0
        let original = bytes(try renderer.renderOffscreen(width: 512, height: 320))
        for degrees in [-30.0, 30] {
            renderer.foldDegrees = degrees
            let blurred = bytes(try renderer.renderOffscreen(width: 512, height: 320))
            func contrast(_ image: [UInt8]) -> Double {
                let values = (150..<360).map { Double(image[(40*512+$0)*4]) }
                let mean = values.reduce(0,+) / Double(values.count)
                return sqrt(values.reduce(0) { $0 + pow($1-mean,2) } / Double(values.count))
            }
            XCTAssertLessThan(contrast(blurred), contrast(original)*0.2)
        }
    }
    func testOpeningUsesSameInwardProjectionWithoutMagnification() throws {
        let renderer = try FoldRenderer()
        try renderer.setImage(DemoArtwork.make(width: 512, height: 320))
        renderer.settings.darkness = 0; renderer.settings.blur = 0
        for angle in [1.0, 15, 40, 70] {
            renderer.foldDegrees = angle
            let inward = bytes(try renderer.renderOffscreen(width: 512, height: 320))
            renderer.foldDegrees = -angle
            let outward = bytes(try renderer.renderOffscreen(width: 512, height: 320))
            XCTAssertEqual(outward, inward, "Outward motion must use the same narrowing projection, never the old widening projection.")
        }
    }
    func testCursorHideRequestsAreBalancedAcrossRepeatedFramesAndCleanup() {
        var hides = 0; var shows = 0
        var cursor: EffectCursor? = EffectCursor(hide: { hides += 1; return .success }, show: { shows += 1; return .success })
        for _ in 0..<120 { cursor?.setHidden(true) }
        XCTAssertEqual(hides, 1)
        cursor?.setHidden(false); cursor?.setHidden(false)
        XCTAssertEqual(shows, 1)
        cursor?.setHidden(true)
        cursor = nil
        XCTAssertEqual(hides, 2); XCTAssertEqual(shows, 2)
    }
    func testFailedCursorHideDoesNotAcquireUnbalancedRequest() {
        var shows = 0
        let cursor = EffectCursor(hide: { .failure }, show: { shows += 1; return .success })
        XCTAssertFalse(cursor.setHidden(true))
        XCTAssertFalse(cursor.isHidden)
        cursor.setHidden(false)
        XCTAssertEqual(shows, 0)
    }
    func testExportRealGPUFramesAndMeasureRetinaRender() throws {
        let renderer = try FoldRenderer()
        try renderer.setImage(DemoArtwork.make(width: 1440, height: 900))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/verification")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for angle in [-45.0, -20, -5, 0, 5, 20, 45, 85] {
            renderer.foldDegrees = angle
            let image = try renderer.renderOffscreen(width: 1440, height: 900)
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try data.write(to: directory.appendingPathComponent("fold-\(Int(angle)).png"))
        }
        renderer.foldDegrees = 35
        _ = try renderer.renderOffscreen(width: 3456, height: 2234)
        print("METAL GPU: 3456×2234 frame \(renderer.lastGPUTime * 1000) ms; images: \(directory.path)")
        XCTAssertGreaterThan(renderer.lastGPUTime, 0)
    }
}
