import Foundation

/// Reject isolated sensor spikes and boundary chatter before they can restart
/// the motion/idle timer. Visual interpolation happens separately on display frames.
public struct HingeMotionFilter {
    private var samples = [Double]()
    private var accepted: Double?
    private var lastTimestamp: Double?
    private var candidateDirection = 0.0
    private var candidateSince = 0.0
    private var lastDirection = 0.0
    public init() {}
    public mutating func reset() { self = HingeMotionFilter() }

    public mutating func receive(angle: Double?, at now: Double) -> Double? {
        guard let angle, angle.isFinite, (0...180).contains(angle), now.isFinite else {
            reset(); return nil
        }
        if let lastTimestamp, now <= lastTimestamp { return accepted }
        lastTimestamp = now
        guard let previous = accepted else {
            accepted = angle; samples = [angle, angle, angle]; return angle
        }
        samples.removeFirst(); samples.append(angle)
        let median = samples.sorted()[1]
        let delta = median - previous
        guard abs(delta) >= 0.75 else { candidateDirection = 0; return previous }
        let direction = delta > 0 ? 1.0 : -1.0
        if direction != candidateDirection { candidateDirection = direction; candidateSince = now }
        // A real multi-degree movement passes after the median's one-sample delay.
        // Tiny steps must persist 40 ms; tiny reversals need 100 ms to reject chatter.
        let dwell = lastDirection != 0 && direction != lastDirection ? 0.100 : 0.040
        guard abs(delta) >= 2 || now - candidateSince >= dwell else { return previous }
        accepted = median; lastDirection = direction; candidateDirection = 0
        return median
    }
}
