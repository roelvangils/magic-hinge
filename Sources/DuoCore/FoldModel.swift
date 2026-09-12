import Foundation

public struct FoldSettings: Equatable, Codable, Sendable {
    public var eyeDistance: Double = 2.4
    /// Gaussian sigma at the top edge, as a fraction of screen height.
    public var blur: Double = 0.11
    public var darkness: Double = 0.66
    public var perspective: Double = 1
    public var hideCursor: Bool = false
    public var animateOnOpen: Bool = true
    public var animateOnClose: Bool = true
    public init() {}
    private enum CodingKeys: String, CodingKey { case eyeDistance, blur, darkness, perspective, hideCursor, animateOnOpen, animateOnClose }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        eyeDistance = try values.decodeIfPresent(Double.self, forKey: .eyeDistance) ?? 2.4
        blur = try values.decodeIfPresent(Double.self, forKey: .blur) ?? 0.11
        darkness = try values.decodeIfPresent(Double.self, forKey: .darkness) ?? 0.66
        perspective = try values.decodeIfPresent(Double.self, forKey: .perspective) ?? 1
        hideCursor = try values.decodeIfPresent(Bool.self, forKey: .hideCursor) ?? false
        animateOnClose = try values.decodeIfPresent(Bool.self, forKey: .animateOnClose) ?? true
        animateOnOpen = try values.decodeIfPresent(Bool.self, forKey: .animateOnOpen) ?? true
    }

    public func tilt(degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        return min(85, max(-85, degrees)) * .pi / 180
    }
    public func progress(degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        return min(1, abs(degrees) / 85)
    }
}

public enum HingeReport {
    /// Apple LAS HID feature report 1: report ID, then an unsigned LE angle in degrees.
    public static func decode(_ bytes: [UInt8], length: Int) -> Double? {
        guard length >= 3, length <= bytes.count, bytes[0] == 1 else { return nil }
        let angle = Int(bytes[1]) | (Int(bytes[2]) << 8)
        guard (0...180).contains(angle) else { return nil }
        return Double(angle)
    }
}

/// Sensor events establish motion; display frames independently interpolate its presentation.
/// Closing builds a positive fold; opening releases it without crossing the flat pose.
public struct FoldSession {
    public enum Phase: Equatable { case idle, moving, returning }
    public enum Action: Equatable { case none, capture, dismiss }
    public struct Frame {
        public var degrees: Double
        public var phase: Phase
        public var action: Action
    }
    public private(set) var phase: Phase = .idle
    public private(set) var degrees: Double = 0
    public static let idleDelay = 0.4
    public static let returnDuration = 0.45
    private var lastAngle: Double?
    private var lastMotion = 0.0
    private var lastFrame: Double?
    private var target = 0.0
    private var returnFrom = 0.0
    private var returnStart = 0.0
    private var velocity = 0.0
    private var revealingAfterSleep = false
    public init() {}
    public mutating func reset() { self = FoldSession() }

    /// The lid can move while the app is asleep. Seed a modest opening pose on the
    /// first available frame; real motion then takes over and the normal idle return applies.
    public mutating func beginOpening(angle: Double, at now: Double) -> Action {
        guard angle.isFinite, (0...180).contains(angle), now.isFinite else { return .none }
        reset()
        lastAngle = angle; lastFrame = now; lastMotion = now
        // If the screen is already open, don't invent a new fold on wake.
        guard angle < 45 else { return .none }
        target = 85 * (1 - angle / 45); degrees = target; phase = .moving
        revealingAfterSleep = true
        return .capture
    }

    public mutating func receive(angle: Double?, at now: Double, enabled: Bool = true, animateOpening: Bool = true, animateClosing: Bool = true) -> Action {
        guard enabled, let angle, angle.isFinite, now.isFinite, (0...180).contains(angle) else {
            let active = phase != .idle
            reset()
            return active ? .dismiss : .none
        }
        // Advance first: restarting during the return must continue from the visible pose.
        let frameAction = frame(at: now).action
        guard let previous = lastAngle else { lastAngle = angle; return frameAction }
        let delta = previous - angle
        // The sensor resolves whole degrees. Trigger on its very first step, in either direction.
        guard abs(delta) >= 0.75 else { return frameAction }
        lastAngle = angle
        if (delta > 0 && !animateClosing) || (delta < 0 && !animateOpening) {
            if phase == .moving {
                phase = .returning; returnFrom = degrees; returnStart = now; velocity = 0
            }
            return frameAction
        }
        lastMotion = now
        switch phase {
        case .idle:
            guard delta > 0 else {
                if previous <= 3 && angle < 45 { return beginOpening(angle:angle,at:now) }
                return frameAction
            }
            target = delta; degrees = 0; velocity = 0; lastFrame = now; phase = .moving
            return .capture
        case .moving:
            if revealingAfterSleep && delta < 0 {
                target = min(target, max(0, 85 * (1 - angle / 45)))
            } else {
                revealingAfterSleep = false
                target = max(0, target + delta)
            }
        case .returning:
            revealingAfterSleep = false
            target = max(0, degrees + delta)
            velocity = 0
            phase = .moving
        }
        return .none
    }

    public mutating func frame(at now: Double) -> Frame {
        guard now.isFinite else { return .init(degrees: degrees, phase: phase, action: .none) }
        guard now >= (lastFrame ?? now) else { return .init(degrees: degrees, phase: phase, action: .none) }
        let dt = max(0, now - (lastFrame ?? now))
        lastFrame = now
        if phase == .moving {
            // Exact critically damped interpolation: continuous position AND
            // velocity between integer HID readings, independent of frame rate.
            let omega = 1.0 / 0.020
            let offset = degrees - target
            let c = velocity + omega * offset
            let decay = exp(-omega * dt)
            degrees = target + (offset + c * dt) * decay
            velocity = (velocity - omega * c * dt) * decay
            if degrees < 0 { degrees = 0; velocity = 0 }
            if abs(target - degrees) < 0.002 && abs(velocity) < 0.02 { degrees = target; velocity = 0 }
            if target == 0 && degrees == 0 {
                phase = .idle; revealingAfterSleep = false
                return .init(degrees: 0, phase: phase, action: .dismiss)
            }
            if now - lastMotion >= Self.idleDelay {
                phase = .returning
                returnStart = lastMotion + Self.idleDelay
                returnFrom = degrees
            }
        }
        if phase == .returning {
            let t = min(1, max(0, (now - returnStart) / Self.returnDuration))
            // Quintic smoothstep: the inverse animation begins and ends with zero velocity.
            let ease = t * t * t * (t * (t * 6 - 15) + 10)
            degrees = returnFrom * (1 - ease)
            if t >= 1 {
                degrees = 0; target = 0; velocity = 0; phase = .idle
                // Retain lastAngle: the newly stationary pose is now the next origin.
                return .init(degrees: 0, phase: phase, action: .dismiss)
            }
        }
        return .init(degrees: degrees, phase: phase, action: .none)
    }
}

public enum FoldProjection {
    /// CPU reference for the shader, origin top-left; the physical hinge is at y=1.
    public static func sampleUV(x: Double, y: Double, tilt: Double, eyeDistance: Double) -> (x: Double, y: Double) {
        let tilt = min(1.48, abs(tilt))
        let distanceFromHinge = 1 - y
        let z = distanceFromHinge * sin(tilt)
        let glassY = 1 - distanceFromHinge * cos(tilt)
        let t = max(1.15, eyeDistance) / max(0.01, max(1.15, eyeDistance) - z)
        return (0.5 + (x - 0.5) * t, 0.5 + (glassY - 0.5) * t)
    }
}
