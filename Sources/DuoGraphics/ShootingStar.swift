import AppKit
import QuartzCore

/// A sparse schedule on the sky's local (pausable) clock; no timer or continuous SwiftUI updates.
struct ShootingStar {
    let start: Double
    let duration: Double
    let x: Double, y: Double
    let direction: Double
    let length: Double

    static func schedule(seed: UInt64) -> (stars: [Self], duration: Double) {
        var state = seed
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 40)/Double(1 << 24)
        }
        var start = 8+random()*6
        var result: [Self] = []
        for _ in 0..<7 {
            let direction = random() < 0.5 ? -1.0 : 1.0
            result.append(Self(start:start,duration:0.65+random()*0.3,
                x:0.30+random()*0.40,y:0.12+random()*0.38,direction:direction,length:0.16+random()*0.09))
            start += 24+random()*18
        }
        return (result,start-result[0].start)
    }
    /// Both ends are inside the visible sky, above the highest mountain even in wide windows.
    func path(wallpaper: CGRect, viewport: CGSize) -> (start: CGPoint, end: CGPoint)? {
        let visibleSky = CGRect(x:wallpaper.minX,y:wallpaper.minY+wallpaper.height*0.025,
                                width:wallpaper.width,height:wallpaper.height*0.315)
            .intersection(CGRect(origin:.zero,size:viewport))
        guard visibleSky.width > 100, visibleSky.height > 45 else { return nil }
        let a = CGPoint(x:visibleSky.minX+x*visibleSky.width,y:viewport.height-(visibleSky.minY+y*visibleSky.height))
        let b = CGPoint(x:a.x+direction*length*visibleSky.width,y:a.y-visibleSky.height*0.26)
        return (a,b)
    }
}

final class ShootingStarLayer: CALayer {
    private static let streak: CGImage = {
        let width = 256, height = 32
        var pixels = [UInt8](repeating:0,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let u = Double(x)/Double(width-1)
            let v = (Double(y)+0.5-Double(height)/2)/(Double(height)/2)
            let tail = pow(u,2.5)*exp(-v*v*100)*0.72
            let head = exp(-pow((u-0.97)/0.025,2)-v*v*18)
            let glow = pow(u,5)*exp(-v*v*8)*0.12
            let alpha = UInt8(min(1,tail+head+glow)*255)
            let i = (y*width+x)*4
            pixels[i] = UInt8(Double(alpha)*0.90); pixels[i+1] = UInt8(Double(alpha)*0.95)
            pixels[i+2] = alpha; pixels[i+3] = alpha
        } }
        let data = Data(pixels) as CFData
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:CGDataProvider(data:data)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
    }()
    override init() { super.init(); contents = Self.streak; anchorPoint = CGPoint(x:0.97,y:0.5); opacity = 0 }
    override init(layer: Any) { super.init(layer:layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ star: ShootingStar, cycle: Double, wallpaper: CGRect, viewport: CGSize) {
        guard let path = star.path(wallpaper:wallpaper,viewport:viewport) else {
            isHidden = true; removeAllAnimations(); return
        }
        isHidden = false
        bounds = CGRect(x:0,y:0,width:min(95,max(40,wallpaper.width*0.07)),height:7)
        transform = CATransform3DMakeRotation(atan2(path.end.y-path.start.y,path.end.x-path.start.x),0,0,1)
        let movement = CAKeyframeAnimation(keyPath:"position")
        movement.values = [path.start,path.start,path.end,path.end].map { NSValue(point:$0) }
        movement.keyTimes = [0,star.start/cycle,(star.start+star.duration)/cycle,1].map(NSNumber.init(value:))
        let fade = CAKeyframeAnimation(keyPath:"opacity")
        fade.values = [0,0,0.9,0.75,0,0]
        fade.keyTimes = [0,star.start/cycle,(star.start+star.duration*0.12)/cycle,
                         (star.start+star.duration*0.5)/cycle,(star.start+star.duration)/cycle,1].map(NSNumber.init(value:))
        movement.duration = cycle; fade.duration = cycle
        let group = CAAnimationGroup()
        group.animations = [movement,fade]; group.duration = cycle
        // Fixed epoch survives relayout; resizing does not restart the schedule.
        group.beginTime = 0.000001; group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        add(group,forKey:"shootingStar")
    }
}
