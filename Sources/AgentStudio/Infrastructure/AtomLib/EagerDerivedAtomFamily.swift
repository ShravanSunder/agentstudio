@MainActor
package final class EagerDerivedAtomFamily<
    Key: Hashable & Sendable,
    Intent: Sendable,
    IntentIdentity: Equatable & Sendable,
    Work: Sendable,
    Candidate: Sendable,
    Value: Sendable
> {
    package typealias Atom = EagerDerivedAtom<Intent, IntentIdentity, Work, Candidate, Value>

    private struct Slot {
        let id: UInt64
        let atom: Atom
        var admittedIdentity: IntentIdentity?
        var readyIdentity: IntentIdentity?
    }

    private let intentIdentity: @Sendable (Intent) -> IntentIdentity
    private let combinePendingIntents: @Sendable (Intent, Intent) -> Intent
    private let telemetryLabel: String?
    private let performanceOutcome: @MainActor @Sendable (String, String) -> Void
    private let prepare: @MainActor @Sendable (Intent, UInt64) -> Atom.PreparationDisposition
    private let project: @Sendable (Work) throws(CancellationError) -> Candidate
    private let classify: @MainActor @Sendable (Candidate, Value?) -> Atom.CandidateDisposition
    private let onAwaitingOwner: @MainActor @Sendable (Key, Atom.CandidateToken, Candidate, Value) -> Void
    private let onProjectionCompletion: @MainActor @Sendable (Key, Atom.ProjectionCompletion) -> Void
    private var slotByKey: [Key: Slot] = [:]
    private var stoppedInFlightAtomBySlotID: [UInt64: Atom] = [:]
    private var stoppedInFlightSlotIDsByKey: [Key: Set<UInt64>] = [:]
    private var drainRequestedSlotIDs: Set<UInt64> = []
    private var nextSlotID: UInt64 = 0
    private var hasStopped = false

    package init(
        telemetryLabel: String? = nil,
        performanceOutcome: @escaping @MainActor @Sendable (String, String) -> Void = { _, _ in },
        intentIdentity: @escaping @Sendable (Intent) -> IntentIdentity,
        combinePendingIntents: @escaping @Sendable (Intent, Intent) -> Intent,
        prepare: @escaping @MainActor @Sendable (Intent, UInt64) -> Atom.PreparationDisposition,
        project: @escaping @Sendable (Work) throws(CancellationError) -> Candidate,
        classify:
            @escaping @MainActor @Sendable (Candidate, Value?) -> Atom.CandidateDisposition,
        onAwaitingOwner:
            @escaping @MainActor @Sendable (
                Key,
                Atom.CandidateToken,
                Candidate,
                Value
            ) -> Void = { _, _, _, _ in },
        onProjectionCompletion:
            @escaping @MainActor @Sendable (Key, Atom.ProjectionCompletion) -> Void = { _, _ in }
    ) {
        self.telemetryLabel = telemetryLabel
        self.performanceOutcome = performanceOutcome
        self.intentIdentity = intentIdentity
        self.combinePendingIntents = combinePendingIntents
        self.prepare = prepare
        self.project = project
        self.classify = classify
        self.onAwaitingOwner = onAwaitingOwner
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
            intentIdentity: intentIdentity,
            combinePendingIntents: combinePendingIntents,
            prepare: prepare,
            project: project,
            classify: classify,
            onAwaitingOwner: { [weak self] token, candidate, proposedValue in
                self?.onAwaitingOwner(key, token, candidate, proposedValue)
            },
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

    package func admit(_ intent: Intent, for key: Key) {
        guard !hasStopped, let atom = materialize(for: key) else { return }
        performanceOutcome("eager_admission", "admitted")
        if let telemetryLabel {
            AtomPerformanceTelemetry.shared.recordEagerDerivedFamily(
                label: telemetryLabel,
                operation: "admit"
            )
        }
        let identity = intentIdentity(intent)
        let preservesReadiness =
            slotByKey[key]?.admittedIdentity == identity
            && slotByKey[key]?.readyIdentity == identity
            && atom.isCurrent(identity)
        slotByKey[key]?.admittedIdentity = identity
        if !preservesReadiness {
            slotByKey[key]?.readyIdentity = nil
        }
        atom.admit(intent)
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

    package func latestAcceptedValue(for key: Key) -> Value? {
        guard let slot = slotByKey[key],
            let admittedIdentity = slot.admittedIdentity,
            slot.readyIdentity == admittedIdentity,
            slot.atom.isCurrent(admittedIdentity)
        else {
            return nil
        }
        return slot.atom.latestAcceptedValue
    }

    package func remove(for key: Key) {
        guard let slot = slotByKey[key] else { return }
        stopAndRetainInFlightAtomIfNeeded(slot, for: key)
        slotByKey.removeValue(forKey: key)
    }

    package func removeAndDrain(for key: Key) async {
        var atomsToDrain = stoppedInFlightAtoms(for: key)
        if let slot = slotByKey[key] {
            atomsToDrain[slot.id] = slot.atom
            drainRequestedSlotIDs.insert(slot.id)
            stopAndRetainInFlightAtomIfNeeded(slot, for: key)
            slotByKey.removeValue(forKey: key)
        }
        drainRequestedSlotIDs.formUnion(atomsToDrain.keys)
        for (slotID, atom) in atomsToDrain {
            await atom.stopAndDrain()
            drainRequestedSlotIDs.remove(slotID)
            releaseStoppedAtom(slotID: slotID, for: key, expectedAtom: atom)
        }
    }

    package func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        let slots = Array(slotByKey)
        for (key, slot) in slots {
            stopAndRetainInFlightAtomIfNeeded(slot, for: key)
        }
        slotByKey.removeAll()
    }

    package func stopAndDrain() async {
        var atomsToDrain = stoppedInFlightAtomBySlotID
        for slot in slotByKey.values {
            atomsToDrain[slot.id] = slot.atom
        }
        drainRequestedSlotIDs.formUnion(atomsToDrain.keys)
        stop()
        for (slotID, atom) in atomsToDrain {
            await atom.stopAndDrain()
            drainRequestedSlotIDs.remove(slotID)
            releaseStoppedAtom(slotID: slotID, expectedAtom: atom)
        }
    }

    private func handleProjectionCompletion(
        _ completion: Atom.ProjectionCompletion,
        for key: Key,
        slotID: UInt64
    ) {
        performanceOutcome("projection_worker", Self.telemetryOutcome(for: completion))
        if let telemetryLabel {
            AtomPerformanceTelemetry.shared.recordEagerDerivedFamily(
                label: telemetryLabel,
                operation: "completion",
                outcome: Self.telemetryOutcome(for: completion)
            )
        }
        defer {
            if let stoppedAtom = stoppedInFlightAtomBySlotID[slotID],
                !stoppedAtom.hasUnsettledProjectionTasks,
                !drainRequestedSlotIDs.contains(slotID)
            {
                releaseStoppedAtom(slotID: slotID, expectedAtom: stoppedAtom)
            }
            onProjectionCompletion(key, completion)
        }
        guard var slot = slotByKey[key], slot.id == slotID else { return }

        let completedIdentity: IntentIdentity
        switch completion {
        case .published(let identity), .equal(let identity):
            completedIdentity = identity
        case .rejected, .superseded, .cancelled:
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

    private static func telemetryOutcome(for completion: Atom.ProjectionCompletion) -> String {
        switch completion {
        case .published:
            "published"
        case .equal:
            "equal"
        case .rejected:
            "rejected"
        case .superseded:
            "superseded"
        case .cancelled:
            "cancelled"
        }
    }

    private func stopAndRetainInFlightAtomIfNeeded(_ slot: Slot, for key: Key) {
        let hasInFlightProjection = slot.atom.hasUnsettledProjectionTasks
        if hasInFlightProjection {
            stoppedInFlightAtomBySlotID[slot.id] = slot.atom
            stoppedInFlightSlotIDsByKey[key, default: []].insert(slot.id)
        }
        slot.atom.stop()
        if !slot.atom.hasUnsettledProjectionTasks {
            stoppedInFlightAtomBySlotID.removeValue(forKey: slot.id)
            stoppedInFlightSlotIDsByKey[key]?.remove(slot.id)
            if stoppedInFlightSlotIDsByKey[key]?.isEmpty == true {
                stoppedInFlightSlotIDsByKey.removeValue(forKey: key)
            }
        }
    }

    private func releaseStoppedAtom(
        slotID: UInt64,
        for key: Key? = nil,
        expectedAtom: Atom
    ) {
        guard stoppedInFlightAtomBySlotID[slotID] === expectedAtom else { return }
        stoppedInFlightAtomBySlotID.removeValue(forKey: slotID)
        if let key {
            stoppedInFlightSlotIDsByKey[key]?.remove(slotID)
            if stoppedInFlightSlotIDsByKey[key]?.isEmpty == true {
                stoppedInFlightSlotIDsByKey.removeValue(forKey: key)
            }
            return
        }
        for trackedKey in Array(stoppedInFlightSlotIDsByKey.keys) {
            stoppedInFlightSlotIDsByKey[trackedKey]?.remove(slotID)
            if stoppedInFlightSlotIDsByKey[trackedKey]?.isEmpty == true {
                stoppedInFlightSlotIDsByKey.removeValue(forKey: trackedKey)
            }
        }
    }

    private func stoppedInFlightAtoms(for key: Key) -> [UInt64: Atom] {
        let slotIDs = stoppedInFlightSlotIDsByKey[key] ?? []
        return slotIDs.reduce(into: [:]) { result, slotID in
            result[slotID] = stoppedInFlightAtomBySlotID[slotID]
        }
    }
}
