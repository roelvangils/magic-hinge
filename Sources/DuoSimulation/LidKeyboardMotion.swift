import Foundation

/// Retargetable, critically damped step motion. Key repeats accumulate against the target,
/// preserving velocity instead of restarting an ease curve on every key-down.
public struct LidKeyboardMotion {
    public private(set) var angle: Double
    public private(set) var target: Double
    public private(set) var velocity = 0.0
    public var isComplete: Bool { angle == target && velocity == 0 }
    public init(angle: Double) { self.angle = min(130,max(0,angle)); target = self.angle }
    public mutating func step(by delta: Double) {
        guard delta.isFinite else { return }
        target = min(130,max(0,target+delta))
    }
    public mutating func advance(by elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return angle }
        let omega = 24.0, dt = min(elapsed,0.1)
        let displacement = angle-target
        let c = velocity+omega*displacement
        let decay = exp(-omega*dt)
        angle = target+(displacement+c*dt)*decay
        velocity = (velocity-omega*c*dt)*decay
        if angle < 0 { angle = 0; velocity = max(0,velocity) }
        if angle > 130 { angle = 130; velocity = min(0,velocity) }
        if abs(angle-target) < 0.002 && abs(velocity) < 0.025 { angle = target; velocity = 0 }
        return angle
    }
}
