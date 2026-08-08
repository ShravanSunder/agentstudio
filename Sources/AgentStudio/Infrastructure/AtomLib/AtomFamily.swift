@MainActor
private final class AtomFamilySlot<Value> {
    private let semanticRevision = AtomRevision()
    private var value: Value?

    init(value: Value? = nil) {
        self.value = value
    }

    func readValue() -> Value? {
        _ = semanticRevision.value
        return value
    }

    func readRevision() -> Int {
        semanticRevision.value
    }

    func acceptValue(_ newValue: Value?) {
        value = newValue
        semanticRevision.bump()
    }

}

@MainActor
package final class AtomFamily<Key: Hashable, Value> {
    private let membershipRevisionAtom = AtomRevision()
    private let telemetryLabel: String
    private let isContentEqual: (Value, Value) -> Bool
    private var slots: [Key: AtomFamilySlot<Value>] = [:]
    private var cachedValues: [Key: Value] = [:]

    package var storageSlotCount: Int {
        slots.count
    }

    package var membershipRevision: Int {
        membershipRevisionAtom.value
    }

    package init(
        telemetryLabel: String,
        isContentEqual: @escaping (Value, Value) -> Bool
    ) {
        self.telemetryLabel = telemetryLabel
        self.isContentEqual = isContentEqual
    }

    package func value(for key: Key) -> Value? {
        let hadCachedValue = cachedValues[key] != nil
        let value = slot(for: key).readValue()
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "value",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count,
            cacheHit: hadCachedValue
        )
        return value
    }

    package func revision(for key: Key) -> Int {
        slot(for: key).readRevision()
    }

    package func snapshotValue(for key: Key) -> Value? {
        let value = cachedValues[key]
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "snapshot_value",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count,
            cacheHit: value != nil
        )
        return value
    }

    package func membershipKeys() -> Set<Key> {
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "membership_keys",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
        return Set(cachedValues.keys)
    }

    package func snapshot() -> [Key: Value] {
        AtomPerformanceTelemetry.shared.recordRead(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "snapshot",
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
        return cachedValues
    }

    package func setValue(_ newValue: Value, for key: Key, mutation: AtomMutationContext) {
        mutation.assertMutable()
        let hadValue = cachedValues[key] != nil
        if let existingValue = cachedValues[key], isContentEqual(existingValue, newValue) {
            AtomPerformanceTelemetry.shared.recordMutation(
                kind: "entity_map",
                label: telemetryLabel,
                operation: "set_noop",
                acceptedChangeCount: 0,
                slotCount: slots.count,
                cachedKeyCount: cachedValues.count
            )
            return
        }

        cachedValues[key] = newValue
        let slot = slot(for: key)
        slot.acceptValue(newValue)
        mutation.recordAcceptedChange()
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "set",
            acceptedChangeCount: 1,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )

        if !hadValue {
            membershipRevisionAtom.bump()
        }
    }

    package func removeValue(for key: Key, mutation: AtomMutationContext) {
        mutation.assertMutable()
        guard cachedValues.removeValue(forKey: key) != nil else {
            AtomPerformanceTelemetry.shared.recordMutation(
                kind: "entity_map",
                label: telemetryLabel,
                operation: "remove_missing",
                acceptedChangeCount: 0,
                slotCount: slots.count,
                cachedKeyCount: cachedValues.count
            )
            return
        }
        slots[key]?.acceptValue(nil)
        mutation.recordAcceptedChange()
        membershipRevisionAtom.bump()
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "remove",
            acceptedChangeCount: 1,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
    }

    package func replaceAll(_ newValues: [Key: Value], mutation: AtomMutationContext) {
        mutation.assertMutable()
        let previousCachedKeys = Set(cachedValues.keys)
        let newKeys = Set(newValues.keys)
        var hasAcceptedChange = false

        for removedKey in previousCachedKeys.subtracting(newKeys) {
            cachedValues.removeValue(forKey: removedKey)
            slots[removedKey]?.acceptValue(nil)
            hasAcceptedChange = true
        }

        for (key, newValue) in newValues {
            if let existingValue = cachedValues[key],
                isContentEqual(existingValue, newValue)
            {
                continue
            }
            cachedValues[key] = newValue
            slot(for: key).acceptValue(newValue)
            hasAcceptedChange = true
        }

        if hasAcceptedChange {
            mutation.recordAcceptedChange()
        }
        if previousCachedKeys != newKeys {
            membershipRevisionAtom.bump()
        }
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "replace_all",
            acceptedChangeCount: hasAcceptedChange ? 1 : 0,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
    }

    package func removeAll(mutation: AtomMutationContext) {
        mutation.assertMutable()
        guard !cachedValues.isEmpty else { return }
        let keysToRemove = Array(cachedValues.keys)
        cachedValues.removeAll()
        for key in keysToRemove {
            slots[key]?.acceptValue(nil)
        }
        mutation.recordAcceptedChange()
        membershipRevisionAtom.bump()
        AtomPerformanceTelemetry.shared.recordMutation(
            kind: "entity_map",
            label: telemetryLabel,
            operation: "remove_all",
            acceptedChangeCount: 1,
            slotCount: slots.count,
            cachedKeyCount: cachedValues.count
        )
    }

    private func slot(for key: Key) -> AtomFamilySlot<Value> {
        if let existingSlot = slots[key] {
            return existingSlot
        }
        let createdSlot = AtomFamilySlot<Value>(value: cachedValues[key])
        slots[key] = createdSlot
        return createdSlot
    }
}
