import AppKit
import QuartzCore

/// A bounded, deterministic burst, composited by Core Animation from cached soft sprites.
/// Its clock is the simulator's existing frame clock; no emitter or timer survives the burst.
final class AnvilBurstView: NSView {
    struct Particle {
        let spark: Bool
        let origin: CGPoint
        let travel: CGSize
        let diameter: CGFloat
        let delay: Double
        let lifetime: Double
        let opacity: Double
        let rotation: Double

        func sample(at time: Double) -> (position: CGPoint, scale: CGFloat, opacity: Float, rotation: CGFloat) {
            let age = (time-delay)/lifetime
            guard age > 0, age < 1 else { return (origin,1,0,0) }
            let t = CGFloat(age)
            // Dust loses horizontal speed as it rolls out and lifts; sparks are ballistic.
            let spread = spark ? t : 1-pow(1-t,3)
            let rise = spark ? 4*t*(1-t)-0.4*t : sin(t * .pi * 0.7)
            let position = CGPoint(x:origin.x+travel.width*spread, y:origin.y+travel.height*rise)
            let envelope = min(1,age/(spark ? 0.035 : 0.09))*pow(1-age,spark ? 0.75 : 1.4)
            let twinkle = spark ? 0.4+0.6*pow(sin(age*18+rotation),2) : 1
            return (position, spark ? 0.55+0.65*sin(t * .pi) : 0.35+1.65*t,
                    Float(opacity*envelope*twinkle),CGFloat(rotation)*(spark ? t*0.5 : t*0.25))
        }
    }
    private(set) var particles: [Particle] = []
    private var particleLayers: [CALayer] = []
    private var started: Double?
    var isActive: Bool { started != nil }
    static let duration = 1.65
    // Prepared when the simulator view is created, never at the contact frame.
    private let dustImages = (0..<3).map { makeDust(seed:UInt64($0+11)) }
    private let sparkImage = makeSpark()

    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func begin(left: CGPoint, right: CGPoint, at time: Double) {
        cancel()
        guard right.x-left.x > 20 else { return }
        let width = right.x-left.x
        var random = Random(seed:42)
        // A low rolling cloud along the contact edge, with larger outward plumes at each corner.
        for i in 0..<38 {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let edge = i < 26
            let along: CGFloat = edge ? (side < 0 ? random.value()*0.16 : 0.84+random.value()*0.16) : random.value()
            let origin = CGPoint(x:left.x+width*along,y:left.y+(right.y-left.y)*along-2)
            particles.append(Particle(spark:false,origin:origin,
                travel:CGSize(width:side*width*(edge ? 0.06+random.value()*0.16 : 0.015+random.value()*0.06),
                              height:width*(0.012+random.value()*0.045)),
                diameter:width*(0.055+random.value()*0.055),delay:Double(random.value())*0.055,
                lifetime:1.05+Double(random.value())*0.5,opacity:edge ? 0.48 : 0.26,
                rotation:Double(random.value())*6.28))
        }
        for _ in 0..<24 {
            let along = random.value()
            let side: CGFloat = along < 0.5 ? -1 : 1
            particles.append(Particle(spark:true,
                origin:CGPoint(x:left.x+width*along,y:left.y+(right.y-left.y)*along),
                travel:CGSize(width:side*width*(0.025+random.value()*0.13),height:width*(0.022+random.value()*0.075)),
                diameter:max(3,min(7,width*(0.004+random.value()*0.003))),delay:Double(random.value())*0.09,
                lifetime:0.35+Double(random.value())*0.55,opacity:0.65+Double(random.value())*0.35,
                rotation:Double(random.value())*6.28))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index,particle) in particles.enumerated() {
            let sprite = CALayer()
            sprite.bounds = CGRect(x:0,y:0,width:particle.diameter,height:particle.diameter)
            sprite.contents = particle.spark ? sparkImage : dustImages[index % dustImages.count]
            sprite.contentsGravity = .resize
            sprite.minificationFilter = .trilinear; sprite.magnificationFilter = .linear
            sprite.opacity = 0
            layer?.addSublayer(sprite); particleLayers.append(sprite)
        }
        CATransaction.commit()
        started = time; isHidden = false
    }
    func advance(at time: Double) {
        guard let started else { return }
        let elapsed = max(0,time-started)
        guard elapsed < Self.duration else { cancel(); return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (particle,sprite) in zip(particles,particleLayers) {
            let state = particle.sample(at:elapsed)
            sprite.position = state.position; sprite.opacity = state.opacity
            sprite.transform = CATransform3DRotate(CATransform3DMakeScale(state.scale,state.scale,1),state.rotation,0,0,1)
        }
        CATransaction.commit()
    }
    func cancel() {
        particleLayers.forEach { $0.removeFromSuperlayer() }
        particleLayers.removeAll(keepingCapacity:true); particles.removeAll(keepingCapacity:true)
        started = nil; isHidden = true
    }

    private struct Random {
        var seed: UInt64
        mutating func value() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 40)/CGFloat(1 << 24)
        }
    }
    private static func makeDust(seed: UInt64) -> CGImage {
        let size = 160
        let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        var random = Random(seed:seed)
        // Overlapping translucent lobes create irregular, feathery billows rather than discs.
        for _ in 0..<32 {
            let angle = random.value()*2 * .pi, distance = sqrt(random.value())*39
            let center = CGPoint(x:80+cos(angle)*distance,y:80+sin(angle)*distance*0.66)
            let radius = 16+random.value()*30
            let shade = 0.80+random.value()*0.19
            let colors = [CGColor(gray:shade,alpha:0.19),CGColor(gray:shade,alpha:0.07),CGColor(gray:shade,alpha:0)] as CFArray
            let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.42,1])!
            context.drawRadialGradient(gradient,startCenter:center,startRadius:0,endCenter:center,endRadius:radius,options:[])
        }
        return context.makeImage()!
    }
    private static func makeSpark() -> CGImage {
        let context = CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red:1,green:0.96,blue:0.85,alpha:0.65),CGColor(gray:1,alpha:0)] as CFArray
        let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
        context.drawRadialGradient(gradient,startCenter:CGPoint(x:32,y:32),startRadius:0,
                                   endCenter:CGPoint(x:32,y:32),endRadius:31,options:[])
        context.setFillColor(CGColor(red:1,green:0.98,blue:0.91,alpha:1))
        context.move(to:CGPoint(x:32,y:3))
        for point in [CGPoint(x:35,y:28),CGPoint(x:58,y:32),CGPoint(x:35,y:36),
                      CGPoint(x:32,y:61),CGPoint(x:29,y:36),CGPoint(x:6,y:32),CGPoint(x:29,y:28)] {
            context.addLine(to:point)
        }
        context.closePath(); context.fillPath()
        return context.makeImage()!
    }
}
