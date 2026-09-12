import AppKit

/// Own notification registrations with their originating centers, so shutdown is balanced.
@MainActor
final class SessionLifecycle {
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []
    private var localKeys: Any?
    func observe(_ name: Notification.Name, center: NotificationCenter = .default, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        registrations.append((center, token))
    }
    func monitorEscape(_ action: @escaping () -> Void) {
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { action() }
            return event
        }
    }
    func stop() {
        for (center, token) in registrations { center.removeObserver(token) }
        registrations.removeAll()
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        localKeys = nil
    }
}
