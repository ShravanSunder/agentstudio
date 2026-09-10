struct BridgeProductCommittedUpdateHistory: Sendable {
    private typealias Identity = BridgeProductSubscriptionExactUTF8Identity

    private let capacity: Int
    private var members: Set<Identity> = []
    private var slots: [Identity] = []
    private var nextEvictionIndex = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { members.count }
    var isEmpty: Bool { members.isEmpty }

    func contains(_ identifier: BridgeProductSubscriptionExactUTF8Identity) -> Bool {
        members.contains(identifier)
    }

    mutating func insert(_ identifier: BridgeProductSubscriptionExactUTF8Identity) {
        guard !members.contains(identifier) else { return }
        if slots.count < capacity {
            slots.append(identifier)
        } else {
            members.remove(slots[nextEvictionIndex])
            slots[nextEvictionIndex] = identifier
            nextEvictionIndex = (nextEvictionIndex + 1) % capacity
        }
        members.insert(identifier)
    }

    mutating func removeAll() {
        members.removeAll(keepingCapacity: false)
        slots.removeAll(keepingCapacity: false)
        nextEvictionIndex = 0
    }
}
