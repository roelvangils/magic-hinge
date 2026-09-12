import AppKit
import MetalKit
import CoreVideo
import DuoCore

public enum RenderError: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? {
        if case .unavailable(let message) = self { return message }; return nil
    }
}

public final class FoldRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let copyPipeline: MTLComputePipelineState
    private let blurPipeline: MTLComputePipelineState
    private var image: MTLTexture?
    private var previousImage: MTLTexture?
    public private(set) var sourceBlend: Double = 1
    public var hasSourceTransition: Bool { previousImage != nil }
    public var settings = FoldSettings()
    public var foldDegrees: Double = 0
    private var textureCache: CVMetalTextureCache?
    private var presentationGeneration = UUID()
    private var firstPresentation: CFTimeInterval = 0
    private var presentedFrames = 0
    public var onDebug: ((String) -> Void)?
    public var onFailure: ((String) -> Void)?
    public private(set) var lastGPUTime: Double = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private struct Uniforms {
        var tilt: Float; var eyeDistance: Float; var blurSigma: Float
        var darkness: Float; var progress: Float; var sourceHeight: Float; var perspective: Float; var sourceBlend: Float
    }

    public init(preferredDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device = preferredDevice, let queue = device.makeCommandQueue() else {
            throw RenderError.unavailable(L10n.text("This Mac has no available Metal GPU."))
        }
        self.device = device; self.queue = queue
        guard let url = Bundle.module.url(forResource: "Fold", withExtension: "metal") else {
            throw RenderError.unavailable(L10n.text("The Metal shader is missing from the app bundle."))
        }
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard let copy = library.makeFunction(name: "copyLinear"), let blur = library.makeFunction(name: "gaussianLevel") else {
            throw RenderError.unavailable(L10n.text("Incomplete Metal shader library."))
        }
        copyPipeline = try device.makeComputePipelineState(function: copy)
        blurPipeline = try device.makeComputePipelineState(function: blur)
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    public func configure(_ view: MTKView) {
        view.wantsLayer = true
        view.layer?.contentsScale = max(1, view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = self
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    public func setImage(_ cgImage: CGImage, crossfade: Bool = false) throws {
        // Normalize into an explicit sRGB byte texture. MTKTextureLoader can choose a
        // floating-point format for CGImages, bypassing the expected hardware sRGB decode.
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
            width: cgImage.width, height: cgImage.height, mipmapped: false)
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        guard let source = device.makeTexture(descriptor: inputDescriptor),
              let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pixels = context.data else {
            throw RenderError.unavailable(L10n.text("The screen capture could not be converted to sRGB."))
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        source.replace(region: MTLRegionMake2D(0, 0, cgImage.width, cgImage.height), mipmapLevel: 0,
                       withBytes: pixels, bytesPerRow: cgImage.width * 4)
        try buildPyramid(source: source, crossfade:crossfade)
    }

    /// ScreenCaptureKit's IOSurface is directly visible to Metal; no CGImage/CPU pixel copy.
    public func setPixelBuffer(_ buffer: CVPixelBuffer, crossfade: Bool = false) throws {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              let textureCache else { throw RenderError.unavailable(L10n.text("No BGRA capture buffer available.")) }
        var reference: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer,
            nil, .bgra8Unorm_srgb, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &reference)
        guard status == kCVReturnSuccess, let reference, let texture = CVMetalTextureGetTexture(reference) else {
            throw RenderError.unavailable(L10n.format("The capture buffer could not be shared with Metal (%d).",status))
        }
        try buildPyramid(source: texture, retaining: [buffer, reference], crossfade:crossfade)
    }

    private func buildPyramid(source: MTLTexture, retaining resources: [AnyObject] = [], crossfade: Bool = false) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
            width: source.width, height: source.height, mipmapped: true)
        descriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
        descriptor.storageMode = .private
        guard let pyramid = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else {
            throw RenderError.unavailable(L10n.text("Not enough GPU memory for the screen capture."))
        }
        pyramid.label = "Desktop Gaussian pyramid"
        for level in 0..<pyramid.mipmapLevelCount {
            guard let target = pyramid.makeTextureView(pixelFormat: .rgba16Float, textureType: .type2D,
                levels: level..<(level+1), slices: 0..<1) else { throw RenderError.unavailable(L10n.text("No mip view available.")) }
            let input: MTLTexture
            if level == 0 { input = source }
            else {
                guard let previous = pyramid.makeTextureView(pixelFormat: .rgba16Float, textureType: .type2D,
                    levels: (level-1)..<level, slices: 0..<1) else { throw RenderError.unavailable(L10n.text("No mip view available.")) }
                input = previous
            }
            guard let encoder = command.makeComputeCommandEncoder() else { throw RenderError.unavailable(L10n.text("No compute encoder available.")) }
            encoder.setComputePipelineState(level == 0 ? copyPipeline : blurPipeline)
            encoder.setTexture(input, index: 0); encoder.setTexture(target, index: 1)
            encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
        }
        command.addCompletedHandler { [weak self, resources] result in
            // The CVMetalTexture wrapper and pixel buffer must survive until the GPU finishes reading.
            withExtendedLifetime(resources) {}
            if let error = result.error { DispatchQueue.main.async { self?.onFailure?(error.localizedDescription) } }
        }
        command.commit()
        // Subsequent frames use this same command queue, preserving upload -> draw ordering.
        previousImage = crossfade ? image : nil
        sourceBlend = previousImage == nil ? 1 : 0
        image = pyramid
        presentationGeneration = UUID(); presentedFrames = 0; firstPresentation = 0
    }

    public func setSourceBlend(_ value: Double) {
        sourceBlend = min(1,max(0,value))
        if sourceBlend == 1 { previousImage = nil }
    }
    public func clearImage() { previousImage = nil; sourceBlend = 1; image = nil; presentationGeneration = UUID(); if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) } }
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    public func draw(in view: MTKView) {
        guard image != nil, inFlight.wait(timeout: .now()) == .success else { return }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { onDebug?("NO DRAWABLE"); inFlight.signal(); return }
        encode(pass: pass, command: command)
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] result in
            semaphore.signal()
            let elapsed = max(0, result.gpuEndTime - result.gpuStartTime)
            DispatchQueue.main.async {
                self?.lastGPUTime = elapsed
                if let error = result.error { self?.onFailure?(error.localizedDescription) }
            }
        }
        let token = presentationGeneration
        drawable.addPresentedHandler { [weak self] drawable in
            let time = drawable.presentedTime
            DispatchQueue.main.async {
                guard let self, self.presentationGeneration == token, time > 0 else { return }
                if self.presentedFrames == 0 { self.firstPresentation = time }
                self.presentedFrames += 1
                if self.presentedFrames == 120, time > self.firstPresentation {
                    self.onDebug?(String(format: "presentation: %.1f fps, GPU %.3f ms", 119 / (time - self.firstPresentation), self.lastGPUTime * 1000))
                    self.presentedFrames = 1; self.firstPresentation = time
                }
            }
        }
        command.present(drawable); command.commit()
    }
    private func encode(pass: MTLRenderPassDescriptor, command: MTLCommandBuffer) {
        guard let image, let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = Uniforms(tilt: Float(settings.tilt(degrees: foldDegrees)),
                         eyeDistance: Float(max(1.15, settings.eyeDistance)),
                         blurSigma: Float(max(0, settings.blur)), darkness: Float(min(1, max(0, settings.darkness))),
                         progress: Float(settings.progress(degrees: foldDegrees)), sourceHeight: Float(image.height),
                         perspective: Float(min(1.3, max(0, settings.perspective))), sourceBlend:Float(sourceBlend))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(image, index: 0)
        encoder.setFragmentTexture(previousImage ?? image, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Runs the real Metal pipeline into a CPU-readable target for regression tests and exports.
    /// Produces a texture for the 3D display without copying pixels back to the CPU.
    /// Completion runs on the main queue after Metal has finished writing the texture.
    public func renderTexture(width: Int, height: Int, completion: @escaping (Result<MTLTexture, Error>) -> Void) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .private
        guard image != nil, let target = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else {
            completion(.failure(RenderError.unavailable(L10n.text("No 3D screen texture available.")))); return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        encode(pass: pass, command: command)
        command.addCompletedHandler { result in
            let error = result.error
            DispatchQueue.main.async {
                if let error { completion(.failure(error)) } else { completion(.success(target)) }
            }
        }
        command.commit()
    }

    /// Runs the real Metal pipeline into a CPU-readable target for regression tests and exports.
    public func renderOffscreen(width: Int, height: Int) throws -> CGImage {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]; d.storageMode = .shared
        guard image != nil, let target = device.makeTexture(descriptor: d), let command = queue.makeCommandBuffer() else {
            throw RenderError.unavailable(L10n.text("No offscreen render target available."))
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        encode(pass: pass, command: command)
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        lastGPUTime = max(0, command.gpuEndTime - command.gpuStartTime)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
