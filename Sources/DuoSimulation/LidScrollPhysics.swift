import Foundation

/// Velocity-sensitive direct manipulation, independent of trackpad event frequency.
public struct LidScrollPhysics {
    public private(set) var velocity = 0.0
    private var lastTime: Double?
    private var lastMotionTime: Double?
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func begin(at time: Double) { reset(); lastTime = time }
    public mutating func displacement(_ degrees: Double, at time: Double) -> Double {
        guard degrees.isFinite, time.isFinite, degrees != 0 else { return 0 }
        let elapsed = time-(lastTime ?? (time-1.0/60))
        let dt = min(0.1,max(1.0/240,elapsed > 0 ? elapsed : 1.0/60))
        if elapsed > 0.15 || velocity*degrees < 0 { velocity = 0 }
        let speed = min(1200,abs(degrees/dt))
        let gain = 1+min(1.25,max(0,speed-80)/400)
        let displacement = degrees*gain
        let measured = max(-900,min(900,displacement/dt))
        velocity += (measured-velocity)*(1-exp(-dt/0.035))
        lastTime = time; lastMotionTime = time
        return displacement
    }
    public func releaseVelocity(at time: Double) -> Double {
        guard let lastMotionTime else { return 0 }
        // A pause with the fingers still resting on the trackpad must cancel the flick.
        return velocity*exp(-max(0,time-lastMotionTime-0.025)/0.075)
    }
}

/// Damped spring about 90 degrees, carrying the user's release velocity into the motion.
public struct LidReleaseSpring {
    public private(set) var angle: Double
    public private(set) var velocity: Double
    public private(set) var isComplete = false
    public init(angle: Double, velocity: Double) {
        self.angle = min(130,max(0,angle)); self.velocity = min(900,max(-900,velocity))
    }
    public mutating func advance(by elapsed: Double) -> Double {
        guard !isComplete else { return angle }
        var remaining = max(0,min(0.1,elapsed))
        while remaining > 0 {
            let dt = min(remaining,1.0/240)
            velocity += (-80*(angle-90)-13*velocity)*dt
            angle += velocity*dt
            if angle > 130 { angle = 130; velocity = -abs(velocity)*0.12 }
            if angle < 0 { angle = 0; velocity = abs(velocity)*0.12 }
            remaining -= dt
        }
        if abs(angle-90)<0.015 && abs(velocity)<0.1 {
            angle = 90; velocity = 0; isComplete = true
        }
        return angle
    }
}
