import AVFoundation
import OSLog

/// Edge detection uses the presented angle, after interpolation, rather than the input target.
public struct LidClosureContact {
    private var armed = false
    private var rearmFrom: Double?
    public static let leadTime = 0.2
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func receive(angle: Double, closingSoon: Bool = false) -> Bool {
        guard angle.isFinite, (0...130).contains(angle) else { return false }
        if let floor = rearmFrom {
            rearmFrom = min(floor,angle)
            guard angle > floor+0.5 else { return false }
            rearmFrom = nil
        }
        if angle > 0.5 { armed = true }
        guard armed, angle == 0 || closingSoon else { return false }
        armed = false; rearmFrom = angle
        return true
    }
    /// Look ahead through the same presentation filter. Manual input is only anticipated
    /// once its target reaches the closed stop; incomplete drags must not produce a snap.
    public static func closingSoon(presented: Double, target: Double, transition: LidTransition?, at time: Double) -> Bool {
        guard (transition?.target ?? target) == 0 else { return false }
        var projected = presented
        let dt = leadTime/12
        for step in 1...12 {
            let nextTarget = transition?.angle(at:time+Double(step)*dt) ?? target
            projected += (nextTarget-projected)*(1-exp(-dt/0.018))
            if abs(projected-nextTarget) < 0.005 { projected = nextTarget }
        }
        return projected == 0
    }

}

/// Audio device startup and scheduling never run on the animation's main actor.
@MainActor
public final class LidSnapSound {
    private let queue = DispatchQueue(label:"be.elevenways.MacBookDuo.snap",qos:.userInitiated)
    private let playback: Playback
    public init(volume: Float = 1) throws {
        guard let url = Bundle.module.url(forResource:"snap",withExtension:"aiff") else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Decode this short clip once. No file I/O or decoding at the moment of contact.
        let file = try AVAudioFile(forReading:url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into:buffer)
        playback = Playback(buffer:buffer,volume:min(1,max(0,volume)))
        activate()
    }
    public func activate() {
        queue.async { [playback] in playback.activate() }
    }
    public func play() {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async { [playback] in playback.play(requestedAt:requested) }
    }
    public func stop() {
        queue.async { [playback] in playback.stop() }
    }
    deinit {
        queue.async { [playback] in playback.stop() }
    }
    /// Queue barrier for silent resource/lifecycle verification; callers suspend, never block.
    func isPrepared() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [playback] in continuation.resume(returning:playback.isReady) }
        }
    }

    /// Accessed exclusively on `queue`; AVFoundation objects never cross executors.
    private final class Playback: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private let volume: Float
        private var engine: AVAudioEngine?
        private var node: AVAudioPlayerNode?
        private var active = false
        private let logger = Logger(subsystem:"be.elevenways.MacBookDuo",category:"audio")
        var isReady: Bool { active && engine?.isRunning == true && node?.isPlaying == true }
        init(buffer: AVAudioPCMBuffer, volume: Float) { self.buffer = buffer; self.volume = volume }
        func activate() {
            active = true
            guard !isReady else { return }
            do {
                if engine == nil {
                    let engine = AVAudioEngine()
                    let node = AVAudioPlayerNode()
                    engine.attach(node)
                    engine.mainMixerNode.outputVolume = volume
                    #if compiler(>=6.4)
                    if #available(macOS 27.0, *) {
                        try engine.connectNode(node,to:engine.mainMixerNode,format:buffer.format)
                    } else { engine.connect(node,to:engine.mainMixerNode,format:buffer.format) }
                    #else
                    engine.connect(node,to:engine.mainMixerNode,format:buffer.format)
                    #endif
                    self.engine = engine; self.node = node
                }
                guard let engine, let node else { return }
                engine.prepare()
                if !engine.isRunning { try engine.start() }
                if !node.isPlaying {
                    #if compiler(>=6.4)
                    if #available(macOS 27.0, *) { try node.playAudio() }
                    else { node.play() }
                    #else
                    node.play()
                    #endif
                }
            } catch {
                logger.error("Snap audio preparation failed: \(error.localizedDescription,privacy:.public)")
            }
        }
        func play(requestedAt time: Double) {
            guard active else { return }
            if !isReady { activate() }
            // A device reconnect must not emit a stale click long after the lid has closed.
            guard isReady, ProcessInfo.processInfo.systemUptime-time < 0.15 else { return }
            node?.scheduleBuffer(buffer,at:nil,options:.interrupts)
        }
        func stop() {
            active = false
            node?.stop()
            engine?.pause()
        }
    }
}
