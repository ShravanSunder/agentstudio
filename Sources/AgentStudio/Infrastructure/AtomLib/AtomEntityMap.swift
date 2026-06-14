import Observation

@MainActor
@Observable
private final class AtomEntitySlot<Value> {
    private(set) var value: Value?

    init(value: Value? = nil) {
        self.value = value
    }

    func setValue(_ newValue: Value?) {
        value = newValue
    }
}

@MainActor
final class AtomEntityMap<Key: Hashable, Value> {
    let membershipRevision = AtomRevision()
    private let isContentEqual: (Value, Value) -> Bool
    private var slots: [Key: AtomEntitySlot<Value>] = [:]
    private var cachedValues: [Key: Value] = [:]

    var storageSlotCount: Int {
        slots.count
    }

    init(isContentEqual: @escaping (Value, Value) -> Bool) {
        self.isContentEqual = isContentEqual
    }

    func value(for key: Key) -> Value? {
        let hadCachedValue = cachedValues[key] != nil
        let value = slot(for: key).value
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            operation: "value",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count,
            cacheHit: hadCachedValue
        )
        return value
    }

    func snapshotValue(for key: Key) -> Value? {
        let value = cachedValues[key]
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            operation: "snapshot_value",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count,
            cacheHit: value != nil
        )
        return value
    }

    func snapshot() -> [Key: Value] {
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            operation: "snapshot",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
        return cachedValues
    }

    func setValue(_ newValue: Value, for key: Key, mutation: AtomMutationContext) {
        mutation.assertMutable()
        let hadValue = cachedValues[key] != nil
        if let existingValue = cachedValues[key], isContentEqual(existingValue, newValue) {
            AtomPerformanceTelemetry.shared.recordMutation(
                kind: "entity_map",
                operation: "set_noop",
                acceptedChangeCount: 0,
                slotCount: slots.count,
                cachedKeyCount: cachedValues.count
            )
            return
        }

        cachedValues[key] = newValue
        let slot = slot(for: key)
        slot.setValue(newValue)
        mutation.recordAcceptedChange()
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            operation: "set",
            acceptedChangeCount: 1,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )

        if !hadValue {
            membershipRevision.bump()
        }
    }

    func removeValue(for key: Key, mutation: AtomMutationContext) {
        mutation.assertMutable()
        guard cachedValues.removeValue(forKey: key) != nil else {
            slots.removeValue(forKey: key)
            AtomPerformanceTelemetry.shared.recordMutation(
                kind: "entity_map",
                operation: "remove_missing",
                acceptedChangeCount: 0,
                slotCount: slots.count,
                cachedKeyCount: cachedValues.count
            )
            return
        }
        slots[key]?.setValue(nil)
        slots.removeValue(forKey: key)
        mutation.recordAcceptedChange()
        membershipRevision.bump()
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            operation: "remove",
            acceptedChangeCount: 1,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
    }

    func replaceAll(_ newValues: [Key: Value], mutation: AtomMutationContext) {
        mutation.assertMutable()
        let previousCachedKeys = Set(cachedValues.keys)
        let previousSlotKeys = Set(slots.keys)
        let newKeys = Set(newValues.keys)
        var hasAcceptedChange = false

        for removedKey in previousSlotKeys.subtracting(newKeys) {
            let removedCachedValue = cachedValues.removeValue(forKey: removedKey)
            slots[removedKey]?.setValue(nil)
            slots.removeValue(forKey: removedKey)
            if removedCachedValue != nil {
                hasAcceptedChange = true
            }
        }

        for (key, newValue) in newValues {
            if let existingValue = cachedValues[key],
                isContentEqual(existingValue, newValue)
            {
                continue
            }
            cachedValues[key] = newValue
            slot(for: key).setValue(newValue)
            hasAcceptedChange = true
        }

        if hasAcceptedChange {
            mutation.recordAcceptedChange()
        }
        if previousCachedKeys != newKeys {
            membershipRevision.bump()
        }
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            operation: "replace_all",
            acceptedChangeCount: hasAcceptedChange ? 1 : 0,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
    }

    func removeAll(mutation: AtomMutationContext) {
        mutation.assertMutable()
        guard !cachedValues.isEmpty || !slots.isEmpty else { return }
        let hadCachedValues = !cachedValues.isEmpty
        let keysToRemove = Array(slots.keys)
        cachedValues.removeAll()
        for key in keysToRemove {
            slots[key]?.setValue(nil)
            slots.removeValue(forKey: key)
        }
        if hadCachedValues {
            mutation.recordAcceptedChange()
            membershipRevision.bump()
        }
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            operation: "remove_all",
            acceptedChangeCount: hadCachedValues ? 1 : 0,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
    }

    @discardableResult
    func pruneNilSlots(excluding retainedKeys: Set<Key>) -> Int {
        let keysToPrune = slots.keys.filter { key in
            cachedValues[key] == nil && !retainedKeys.contains(key)
        }
        for key in keysToPrune {
            slots.removeValue(forKey: key)
        }
        if !keysToPrune.isEmpty {
            AtomPerformanceTelemetry.shared.recordMutation(
                kind: "entity_map",
                operation: "prune_nil_slots",
                acceptedChangeCount: 0,
                slotCount: slots.count,
                cachedKeyCount: cachedValues.count
            )
        }
        return keysToPrune.count
    }

    private func slot(for key: Key) -> AtomEntitySlot<Value> {
        if let existingSlot = slots[key] {
            return existingSlot
        }
        let createdSlot = AtomEntitySlot<Value>()
        slots[key] = createdSlot
        return createdSlot
    }
}
