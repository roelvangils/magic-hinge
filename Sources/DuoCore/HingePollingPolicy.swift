import Foundation

/// Wake slowly at rest; switch immediately to fast reads when any movement is seen.
public struct HingePollingPolicy {
    public private(set) var frequency = 30
    private var previousAngle: Double?
    private var lastMotion = -Double.infinity
    public init() {}
    public mutating func receive(angle: Double, at now: Double) -> Int {
        if let previousAngle, angle != previousAngle { lastMotion = now }
        previousAngle = angle
        frequency = now - lastMotion < 1 ? 120 : 30
        return frequency
    }
}
