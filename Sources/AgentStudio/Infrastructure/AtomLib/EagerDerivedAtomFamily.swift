@MainActor
package final class EagerDerivedAtomFamily<
    Key: Hashable & Sendable,
    Request: Sendable,
    RequestIdentity: Equatable & Sendable,
    Value: Sendable
> {
    package typealias Atom = EagerDerivedAtom<Request, RequestIdentity, Value>

    private struct Slot {
        let id: UInt64
        let atom: Atom
        var admittedIdentity: RequestIdentity?
        var readyIdentity: RequestIdentity?
    }

    private let requestIdentity: @Sendable (Request) -> RequestIdentity
    private let isValueEqual: @Sendable (Value, Value) -> Bool
    private let project: @Sendable (Request) throws(CancellationError) -> Value
    private let onProjectionCompletion: @MainActor @Sendable (Key, Atom.ProjectionCompletion) -> Void
    private var slotByKey: [Key: Slot] = [:]
    private var stoppedInFlightAtomBySlotID: [UInt64: Atom] = [:]
    private var nextSlotID: UInt64 = 0
    private var hasStopped = false

    package init(
        requestIdentity: @escaping @Sendable (Request) -> RequestIdentity,
        isValueEqual: @escaping @Sendable (Value, Value) -> Bool,
        project: @escaping @Sendable (Request) throws(CancellationError) -> Value,
        onProjectionCompletion:
            @escaping @MainActor @Sendable (Key, Atom.ProjectionCompletion) -> Void = { _, _ in }
    ) {
        self.requestIdentity = requestIdentity
        self.isValueEqual = isValueEqual
        self.project = project
        self.onProjectionCompletion = onProjectionCompletion
    }

    package var atoms: [Atom] {
        slotByKey.values.map(\.atom)
    }

    package func materialize(for key: Key) -> Atom? {
        guard !hasStopped else { return nil }
        if let existing = slotByKey[key] {
            return existing.atom
        }

        nextSlotID &+= 1
        let slotID = nextSlotID
        let atom = Atom(
            requestIdentity: requestIdentity,
            isValueEqual: isValueEqual,
            project: project,
            onProjectionCompletion: { [weak self] completion in
                self?.handleProjectionCompletion(completion, for: key, slotID: slotID)
            }
        )
        slotByKey[key] = Slot(
            id: slotID,
            atom: atom,
            admittedIdentity: nil,
            readyIdentity: nil
        )
        return atom
    }

    package func atom(for key: Key) -> Atom? {
        slotByKey[key]?.atom
    }

    package func admit(_ request: Request, for key: Key) {
        guard !hasStopped, let atom = materialize(for: key) else { return }
        let identity = requestIdentity(request)
        let preservesReadiness =
            slotByKey[key]?.admittedIdentity == identity
            && slotByKey[key]?.readyIdentity == identity
            && atom.isCurrent(identity)
        slotByKey[key]?.admittedIdentity = identity
        if !preservesReadiness {
            slotByKey[key]?.readyIdentity = nil
        }
        atom.admit(request)
    }

    package func currentValue(for key: Key) -> Value? {
        guard let slot = slotByKey[key],
            let admittedIdentity = slot.admittedIdentity,
            slot.readyIdentity == admittedIdentity,
            slot.atom.isCurrent(admittedIdentity)
        else {
            return nil
        }
        return slot.atom.value
    }

    package func remove(for key: Key) {
        guard let slot = slotByKey[key] else { return }
        stopAndRetainInFlightAtomIfNeeded(slot)
        slotByKey.removeValue(forKey: key)
    }

    package func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        let slots = Array(slotByKey.values)
        for slot in slots {
            stopAndRetainInFlightAtomIfNeeded(slot)
        }
        slotByKey.removeAll()
    }

    private func handleProjectionCompletion(
        _ completion: Atom.ProjectionCompletion,
        for key: Key,
        slotID: UInt64
    ) {
        defer {
            if let stoppedAtom = stoppedInFlightAtomBySlotID[slotID],
                !stoppedAtom.hasUnsettledProjectionTasks
            {
                stoppedInFlightAtomBySlotID.removeValue(forKey: slotID)
            }
            onProjectionCompletion(key, completion)
        }
        guard var slot = slotByKey[key], slot.id == slotID else { return }

        let completedIdentity: RequestIdentity
        switch completion {
        case .published(let identity), .equal(let identity):
            completedIdentity = identity
        case .superseded, .cancelled:
            return
        }
        guard slot.admittedIdentity == completedIdentity,
            slot.atom.isCurrent(completedIdentity)
        else {
            return
        }
        slot.readyIdentity = completedIdentity
        slotByKey[key] = slot
    }

    private func stopAndRetainInFlightAtomIfNeeded(_ slot: Slot) {
        let hasInFlightProjection = slot.atom.hasUnsettledProjectionTasks
        slot.atom.stop()
        if hasInFlightProjection {
            stoppedInFlightAtomBySlotID[slot.id] = slot.atom
        }
    }
}
