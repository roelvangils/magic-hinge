import Foundation

/// Closing angular momentum gives the floating chassis a brief downward impulse at contact.
public struct LidImpactResponse {
    public private(set) var offset = 0.0
    public private(set) var velocity = 0.0
    public var isActive: Bool { offset != 0 || velocity != 0 }
    private var previousAngle: Double?
    private var previousTime: Double?
    private var recentClosingSpeed = 0.0
    private var armed = false
    public init() {}
    /// Minimum weight for an Anvil closure; preserve a stronger velocity from a fast manual slam.
    public mutating func strike() { velocity = min(velocity,-2.1) }
    public mutating func reset() { self = Self() }

    public mutating func frame(angle: Double, at time: Double) -> Double {
        let elapsed = max(0,time-(previousTime ?? time))
        var remaining = min(0.1,elapsed)
        while remaining > 0 {
            let dt = min(remaining,1.0/240)
            velocity += (-280*offset-22*velocity)*dt
            offset += velocity*dt
            if offset < -0.1 { offset = -0.1; velocity = max(0,velocity) }
            remaining -= dt
        }
        if abs(offset)<0.00003 && abs(velocity)<0.0005 { offset = 0; velocity = 0 }
        recentClosingSpeed *= exp(-elapsed/0.12)
        if let previousAngle, elapsed > 0, elapsed < 0.2 {
            let closingSpeed = max(0,(previousAngle-angle)/elapsed)
            recentClosingSpeed = max(recentClosingSpeed,min(2400,closingSpeed))
        }
        if angle > 4 { armed = true }
        // Trigger once, when the rendered lid actually meets the base. Retain recent speed
        // because the visual interpolation slows down in its last fraction of a degree.
        if armed && angle == 0 {
            armed = false
            if recentClosingSpeed > 180 {
                velocity -= min(2.8,(recentClosingSpeed-180)*0.0028)
            }
            recentClosingSpeed = 0
        }
        previousAngle = angle; previousTime = time
        return offset
    }
}
