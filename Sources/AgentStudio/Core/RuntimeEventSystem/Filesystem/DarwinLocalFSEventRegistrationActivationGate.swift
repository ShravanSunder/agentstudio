import Foundation

/// Holds callbacks until the client publishes the logical registration that
/// owns them, then drains them in arrival order before admitting live delivery.
final class DarwinLocalFSEventRegistrationActivationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let deliver: @Sendable ([DarwinLocalFSEventRawEvent]) -> Void
    private var pendingEvents: [DarwinLocalFSEventRawEvent] = []
    private var isActive = false
    private var isCancelled = false

    init(deliver: @escaping @Sendable ([DarwinLocalFSEventRawEvent]) -> Void) {
        self.deliver = deliver
    }

    func receive(_ events: [DarwinLocalFSEventRawEvent]) {
        guard !events.isEmpty else { return }
        let shouldDeliverImmediately = lock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            guard !isActive else { return true }
            pendingEvents.append(contentsOf: events)
            return false
        }
        if shouldDeliverImmediately {
            deliver(events)
        }
    }

    func activate() {
        while let events = takePendingEventsOrActivate() {
            deliver(events)
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            pendingEvents.removeAll(keepingCapacity: false)
        }
    }

    var isDeliveringLiveEvents: Bool {
        lock.withLock { isActive && !isCancelled }
    }

    private func takePendingEventsOrActivate() -> [DarwinLocalFSEventRawEvent]? {
        lock.withLock {
            guard !isCancelled, !isActive else { return nil }
            guard !pendingEvents.isEmpty else {
                isActive = true
                return nil
            }
            let events = pendingEvents
            pendingEvents.removeAll(keepingCapacity: true)
            return events
        }
    }
}
