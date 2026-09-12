import Foundation

/// Quintic easing with an optional small opening overshoot and a soft settle.
public struct LidTransition {
    public let from: Double
    public let target: Double
    public let startedAt: Double
    private let overshoot: Double
    private let slowMotion: Bool
    public var duration: Double { (overshoot > 0 ? 0.95 : 0.85) * 1.25 * (slowMotion ? 3 : 1) }
    public init(from: Double, target: Double, at time: Double, openingOvershoot: Double = 0, slowMotion: Bool = false) {
        self.slowMotion = slowMotion
        self.from = min(130,max(0,from)); self.target = min(130,max(0,target)); startedAt = time
        // Keep short moves gentle and leave the physical range intact.
        overshoot = min(max(0,openingOvershoot),max(0,(self.target-self.from)*0.08),130-self.target)
    }
    public func isComplete(at time: Double) -> Bool { time >= startedAt+duration }
    public func angle(at time: Double) -> Double {
        let t = min(1,max(0,(time-startedAt)/duration))
        if overshoot > 0 {
            let peak = target+overshoot
            if t < 0.7 { return from+(peak-from)*Self.ease(t/0.7) }
            return peak+(target-peak)*Self.ease((t-0.7)/0.3)
        }
        return from+(target-from)*Self.ease(t)
    }
    private static func ease(_ t: Double) -> Double {
        let t = min(1,max(0,t))
        return t*t*t*(t*(t*6-15)+10)
    }
}
