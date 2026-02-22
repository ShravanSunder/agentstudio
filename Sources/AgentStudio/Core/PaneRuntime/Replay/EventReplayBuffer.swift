import Foundation

@MainActor
final class EventReplayBuffer {
    private let capacity: Int
    private var storage: [PaneEventEnvelope] = []

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    func append(_ envelope: PaneEventEnvelope) {
        storage.append(envelope)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    var count: Int {
        storage.count
    }

    func events() -> [PaneEventEnvelope] {
        storage
    }
}
