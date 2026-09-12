import AppKit
import SwiftUI
import QuartzCore

/// Stable image-space positions: resizing crops the sky together with the wallpaper.
struct SkyStar {
    let x: Double, y: Double, radius: Double, brightness: Double
    let period: Double, phase: Double
    func opacity(at time: Double) -> Double {
        let t = time/period * 2 * .pi + phase
        // Independent, slow harmonics. Stars never blink off or pulse in unison.
        return brightness * (0.59 + 0.29*sin(t) + 0.12*sin(2*t+1.3))
    }
    static func makeSky() -> [Self] {
        var seed: UInt64 = 0xD00_57A2
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 40)/Double(1 << 24)
        }
        return (0..<165).map { _ in
            let x = 0.01+random()*0.98, y = 0.012+random()*0.36
            let size = random(), horizonFade = min(1,(0.385-y)/0.09)
            return Self(x:x,y:y,radius:0.52+pow(size,3)*0.78,
                        brightness:(0.28+pow(size,2)*0.68)*horizonFade,
                        period:2.8+random()*4.2,phase:random()*2 * .pi)
        }
    }
    static func wallpaperRect(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let scale = max(viewSize.width/max(1,imageSize.width),viewSize.height/max(1,imageSize.height))
        let size = CGSize(width:imageSize.width*scale,height:imageSize.height*scale)
        return CGRect(x:(viewSize.width-size.width)/2,y:(viewSize.height-size.height)/2,width:size.width,height:size.height)
    }
}

public struct ProceduralNightSky: NSViewRepresentable {
    public var imageSize: CGSize
    public var animating: Bool
    public init(imageSize: CGSize, animating: Bool) { self.imageSize = imageSize; self.animating = animating }
    public func makeNSView(context: Context) -> NSView { StarSkyView(frame:.zero) }
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? StarSkyView else { return }
        view.imageSize = imageSize
        view.animationRequested = animating
        view.updatePlayback()
    }
    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? StarSkyView)?.stop()
    }
}

final class StarSkyView: NSView {
    let stars = SkyStar.makeSky()
    let sky = CALayer()
    let shootingSky = CALayer()
    let shootingSchedule = ShootingStar.schedule(seed:UInt64.random(in:1...UInt64.max))
    var imageSize = CGSize(width:6016,height:3900) { didSet { if oldValue != imageSize { needsLayout = true } } }
    var animationRequested = false
    private var observer: NSObjectProtocol?
    private static let sprite: CGImage = {
        let ctx = CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:0,
                            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[
            CGColor(gray:1,alpha:1),CGColor(gray:1,alpha:0.82),CGColor(gray:1,alpha:0.09),CGColor(gray:1,alpha:0)
        ] as CFArray,locations:[0,0.12,0.40,1])!
        ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:32,y:32),startRadius:0,
                               endCenter:CGPoint(x:32,y:32),endRadius:32,options:[])
        return ctx.makeImage()!
    }()
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        wantsLayer = true; layer?.masksToBounds = true
        setAccessibilityElement(false)
        sky.speed = 0; sky.timeOffset = 0
        layer?.addSublayer(sky)
        for star in stars {
            let dot = CALayer()
            dot.contents = Self.sprite
            dot.minificationFilter = .trilinear; dot.magnificationFilter = .linear
            dot.opacity = Float(star.opacity(at:0))
            let shimmer = CAKeyframeAnimation(keyPath:"opacity")
            shimmer.values = (0...64).map { star.opacity(at:Double($0)/64*star.period) }
            shimmer.duration = star.period; shimmer.repeatCount = .infinity
            // All timings are local to the paused/resumed sky, with independent phases and periods.
            shimmer.beginTime = 0; shimmer.isRemovedOnCompletion = false
            dot.add(shimmer,forKey:"twinkle")
            sky.addSublayer(dot)
        }
        sky.addSublayer(shootingSky)
        for _ in shootingSchedule.stars { shootingSky.addSublayer(ShootingStarLayer()) }
        layoutStars()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); layoutStars() }
    private func layoutStars() {
        let rect = SkyStar.wallpaperRect(imageSize:imageSize,viewSize:bounds.size)
        // Keep subpixel points gently antialiased at every Retina scale; no snapping/shifting.
        let sizeScale = max(0.75,min(1.6,rect.width/1100))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sky.frame = bounds
        for (star,dot) in zip(stars,sky.sublayers ?? []) {
            dot.position = CGPoint(x:rect.minX+star.x*rect.width,y:bounds.height-(rect.minY+star.y*rect.height))
            let diameter = star.radius*4*sizeScale
            dot.bounds = CGRect(x:0,y:0,width:diameter,height:diameter)
        }
        shootingSky.frame = bounds
        for (star,layer) in zip(shootingSchedule.stars,shootingSky.sublayers ?? []) {
            (layer as? ShootingStarLayer)?.configure(star,cycle:shootingSchedule.duration,wallpaper:rect,viewport:bounds.size)
        }
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        if let window {
            observer = NotificationCenter.default.addObserver(forName:NSWindow.didChangeOcclusionStateNotification,
                object:window,queue:.main) { [weak self] _ in self?.updatePlayback() }
        }
        updatePlayback()
    }
    override func viewDidHide() { super.viewDidHide(); updatePlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); updatePlayback() }
    func updatePlayback() {
        setRunning(animationRequested && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor)
    }
    func setRunning(_ running: Bool) {
        guard running != (sky.speed != 0) else { return }
        if running {
            let paused = sky.timeOffset
            sky.speed = 1; sky.timeOffset = 0; sky.beginTime = 0
            sky.beginTime = sky.convertTime(CACurrentMediaTime(),from:nil)-paused
        } else {
            let paused = sky.convertTime(CACurrentMediaTime(),from:nil)
            sky.speed = 0; sky.timeOffset = paused
        }
    }
    func stop() { animationRequested = false; setRunning(false) }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
