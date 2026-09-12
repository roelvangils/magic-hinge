import Foundation
import IOKit.hid
import DuoCore

/// All IOHID ownership and synchronous feature reads stay on a dedicated serial queue.
public final class HingeSensor: @unchecked Sendable {
    public struct Reading: Sendable {
        public var angle: Double?
        public var message: String
        public var timestamp: TimeInterval
    }
    private let queue = DispatchQueue(label: "be.elevenways.macbookduo.hinge", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var failures = 0
    private var polling = HingePollingPolicy()
    private var lastDiscovery: TimeInterval = -10
    private var handler: (@Sendable (Reading) -> Void)?
    public init() {}
    public static func lidIsClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return (IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool) ?? false
    }

    public func start(handler: @escaping @Sendable (Reading) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            self.handler = handler
            let timer = DispatchSource.makeTimerSource(queue: queue)
            polling = HingePollingPolicy()
            timer.schedule(deadline: .now(), repeating: 1.0 / 30.0, leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }
    public func stop() { queue.async { [self] in stopOnQueue() } }

    private func stopOnQueue() {
        timer?.cancel(); timer = nil
        closeDevice(); handler = nil; lastDiscovery = -10
    }
    private func closeDevice() {
        if let device { IOHIDDeviceClose(device, 0) }
        if let manager { IOHIDManagerClose(manager, 0) }
        device = nil; manager = nil; failures = 0
    }
    private func discover() -> Bool {
        closeDevice()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        // Match only the LAS interface, not the accelerometer/gyro sharing the product ID.
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return false }
        self.manager = manager
        for candidate in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []) {
            if IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess { device = candidate; return true }
        }
        return false
    }
    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        if device == nil {
            guard now - lastDiscovery >= 3 else { return }
            lastDiscovery = now
            guard discover() else {
                handler?(.init(angle: nil, message: L10n.text("No readable hinge sensor found."), timestamp: now))
                return
            }
        }
        guard let device else { return }
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = bytes.count
        let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard status == kIOReturnSuccess, let angle = HingeReport.decode(bytes, length: length) else {
            failures += 1
            if failures >= 5 {
                handler?(.init(angle: nil, message: L10n.format("Sensor temporarily unavailable (%d).",status), timestamp: now))
                closeDevice()
            }
            return
        }
        failures = 0
        let previousRate = polling.frequency
        let rate = polling.receive(angle: angle, at: now)
        if rate != previousRate {
            timer?.schedule(deadline: .now() + 1.0 / Double(rate), repeating: 1.0 / Double(rate),
                            leeway: .milliseconds(rate == 120 ? 1 : 3))
        }
        handler?(.init(angle: angle, message: L10n.text("Apple hinge sensor · 30 Hz idle / 120 Hz moving"), timestamp: now))
    }
}
