import Foundation

/// Small vertical drift after a quiet delay, at any stationary lid angle.
public struct ClosedLidFloat {
    public static let maximumOffset = 0.06
    public static let period = 4.4
    public private(set) var offset: Double = 0
    private var restingSince: Double?
    private var previousTime: Double?
    private var previousAngle: Double?
    public var isWaitingOrFloating: Bool { restingSince != nil || offset > 0 }
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func frame(angle: Double, at time: Double, enabled: Bool = true, resting: Bool? = nil) -> Double {
        let dt = max(0, time-(previousTime ?? time))
        previousTime = time
        guard enabled else { reset(); return 0 }
        let settled = resting ?? (previousAngle == nil || previousAngle == angle)
        previousAngle = angle
        if settled {
            if restingSince == nil { restingSince = time }
            let elapsed = max(0, time-(restingSince ?? time)-1)
            let ramp = min(1, elapsed/1.5)
            let envelope = ramp*ramp*(3-2*ramp)
            let target = Self.maximumOffset * envelope * (1-cos(elapsed * 2 * .pi / Self.period))/2
            offset += (target-offset)*(1-exp(-dt/0.12))
        } else {
            restingSince = nil
            offset *= exp(-dt/0.22)
            if offset < 0.00005 { offset = 0 }
        }
        return offset
    }
}
