import Foundation

struct DarwinSharedExactItemAncestorUnresolvedEntry: Equatable, Sendable {
    var observedEpoch: UInt64
    var canonicalItemPaths: Set<String>

    mutating func merge(observedEpoch: UInt64, canonicalItemPaths: Set<String>) {
        self.observedEpoch = observedEpoch
        self.canonicalItemPaths.formUnion(canonicalItemPaths)
    }
}

struct DarwinSharedExactItemAncestorRecheckEntry: Equatable, Sendable {
    let worktreeId: UUID
    let observedEpoch: UInt64
    let canonicalItemPaths: Set<String>
    let baseline: DarwinSharedExactItemAuthorityBaseline?
}

struct DarwinSharedExactItemAncestorRecheckSnapshot: Equatable, Sendable {
    let recheckGeneration: UInt64
    let parentKey: DarwinSharedExactItemParentKey
    let streamGeneration: UInt64
    let entriesByWorktreeId: [UUID: DarwinSharedExactItemAncestorRecheckEntry]

    var canonicalItemPaths: [String] {
        Array(Set(entriesByWorktreeId.values.flatMap(\.canonicalItemPaths))).sorted()
    }

    var hasCompleteBaselines: Bool {
        entriesByWorktreeId.values.allSatisfy { $0.baseline != nil }
    }
}

struct DarwinSharedExactItemReceiveEffects {
    let mutationEventsByWorktreeId: [UUID: [DarwinFSEventClassifiedRawEvent]]
    let uncertainWorktreeIds: Set<UUID>
    let exactSubscriberWorktreeIds: Set<UUID>
    let fullGitRefreshWorktreeIds: Set<UUID>
    let retiredStreamLifetime: (any DarwinSharedExactItemStreamLifetime)?
    let ancestorRecheckToStart: DarwinSharedExactItemAncestorRecheckSnapshot?
}

extension DarwinSharedExactItemObserverRegistry {
    func emitReceiveEffects(_ effects: DarwinSharedExactItemReceiveEffects) {
        performanceAccumulator.recordSharedFanout(
            exactSubscriberCount: effects.exactSubscriberWorktreeIds.count,
            uncertaintySubscriberCount: effects.uncertainWorktreeIds.count,
            fullRefreshEmissionCount: effects.fullGitRefreshWorktreeIds.count
        )
        for worktreeId in effects.mutationEventsByWorktreeId.keys.sorted(by: Self.sortWorktreeIds) {
            guard let events = effects.mutationEventsByWorktreeId[worktreeId] else { continue }
            yieldObservations(
                worktreeId,
                events.map { event in
                    FSEventObservation(
                        path: event.path,
                        eventID: UInt64(event.eventId),
                        flags: UInt32(event.flags)
                    )
                }
            )
            recordRawEvents(worktreeId, events)
        }
        for worktreeId in effects.uncertainWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            markUncertain(worktreeId)
        }
        for worktreeId in effects.fullGitRefreshWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            yieldFullGitRefresh(
                worktreeId,
                effects.uncertainWorktreeIds.contains(worktreeId) ? .sharedUncertainty : .sharedExact
            )
        }
        effects.retiredStreamLifetime?.retire()
        if let ancestorRecheckToStart = effects.ancestorRecheckToStart {
            startAncestorRecheck(ancestorRecheckToStart)
        }
    }

    func admitFullRefreshLocked(_ candidateWorktreeIds: Set<UUID>) -> Set<UUID> {
        let admittedWorktreeIds = candidateWorktreeIds.subtracting(
            fullRefreshDeliveryOutstandingWorktreeIds
        )
        fullRefreshDeliveryOutstandingWorktreeIds.formUnion(admittedWorktreeIds)
        return admittedWorktreeIds
    }

    func beginNextAncestorRecheckLocked(
        parentKey: DarwinSharedExactItemParentKey
    ) -> DarwinSharedExactItemAncestorRecheckSnapshot? {
        guard var observer = observerByParent[parentKey],
            observer.activeAncestorRecheckGeneration == nil,
            !observer.unresolvedAncestorEntriesByWorktreeId.isEmpty
        else {
            return nil
        }
        nextAncestorRecheckGeneration &+= 1
        let recheckGeneration = nextAncestorRecheckGeneration
        let entries = Dictionary(
            uniqueKeysWithValues: observer.unresolvedAncestorEntriesByWorktreeId.map { worktreeId, unresolvedEntry in
                (
                    worktreeId,
                    DarwinSharedExactItemAncestorRecheckEntry(
                        worktreeId: worktreeId,
                        observedEpoch: unresolvedEntry.observedEpoch,
                        canonicalItemPaths: unresolvedEntry.canonicalItemPaths,
                        baseline: currentAuthorityBaselineLocked(worktreeId: worktreeId)
                    )
                )
            }
        )
        observer.activeAncestorRecheckGeneration = recheckGeneration
        observerByParent[parentKey] = observer
        return DarwinSharedExactItemAncestorRecheckSnapshot(
            recheckGeneration: recheckGeneration,
            parentKey: parentKey,
            streamGeneration: observer.generation,
            entriesByWorktreeId: entries
        )
    }

    func startAncestorRecheck(_ recheck: DarwinSharedExactItemAncestorRecheckSnapshot) {
        let fingerprintReader = fingerprintReader
        Task { [weak self] in
            let outcome: DarwinSharedExactItemFingerprintOutcome?
            if recheck.hasCompleteBaselines {
                outcome = await fingerprintReader.read(
                    canonicalItemPaths: recheck.canonicalItemPaths
                )
            } else {
                outcome = nil
            }
            self?.completeAncestorRecheck(recheck, outcome: outcome)
        }
    }

    func completeAncestorRecheck(
        _ recheck: DarwinSharedExactItemAncestorRecheckSnapshot,
        outcome: DarwinSharedExactItemFingerprintOutcome?
    ) {
        lifecycleCondition.lock()
        guard !hasShutdown,
            var observer = observerByParent[recheck.parentKey],
            observer.generation == recheck.streamGeneration,
            observer.activeAncestorRecheckGeneration == recheck.recheckGeneration
        else {
            lifecycleCondition.unlock()
            return
        }
        observer.activeAncestorRecheckGeneration = nil

        var fallbackWorktreeIds: Set<UUID> = []
        var equalWorktreeIds: Set<UUID> = []
        for worktreeId in recheck.entriesByWorktreeId.keys.sorted(by: Self.sortWorktreeIds) {
            guard let recheckEntry = recheck.entriesByWorktreeId[worktreeId],
                let unresolvedEntry = observer.unresolvedAncestorEntriesByWorktreeId[worktreeId]
            else {
                continue
            }
            guard unresolvedEntry.observedEpoch == recheckEntry.observedEpoch,
                unresolvedEntry.canonicalItemPaths == recheckEntry.canonicalItemPaths
            else {
                fallbackWorktreeIds.insert(worktreeId)
                continue
            }
            guard recheckEntryMatchesBaseline(recheckEntry, outcome: outcome) else {
                observer.unresolvedAncestorEntriesByWorktreeId.removeValue(forKey: worktreeId)
                fallbackWorktreeIds.insert(worktreeId)
                continue
            }
            observer.unresolvedAncestorEntriesByWorktreeId.removeValue(forKey: worktreeId)
            equalWorktreeIds.insert(worktreeId)
        }
        observerByParent[recheck.parentKey] = observer
        resolveCompletedEqualWorktreesLocked(equalWorktreeIds, fallback: &fallbackWorktreeIds)

        let successorRechecks = beginAllReadyAncestorRechecksLocked()
        let admittedFallbackWorktreeIds = admitFullRefreshLocked(fallbackWorktreeIds)
        lifecycleCondition.unlock()

        emitAncestorFallbacks(
            fallbackWorktreeIds,
            admittedWorktreeIds: admittedFallbackWorktreeIds
        )
        for successor in successorRechecks {
            startAncestorRecheck(successor)
        }
    }

    func currentAuthorityBaselineLocked(
        worktreeId: UUID
    ) -> DarwinSharedExactItemAuthorityBaseline? {
        guard let baseline = authorityBaselines.baseline(worktreeId: worktreeId),
            let bindingValidation = bindingValidationByWorktreeId[worktreeId],
            bindingValidation.generation == baseline.bindingGeneration,
            bindingValidation.observationIdentity == baseline.authority.observationIdentity,
            bindingValidation.isCurrent(),
            exactItemsByParentByWorktreeId[worktreeId] == baseline.exactItemsByParent,
            baseline.streamGenerationByParent.allSatisfy({ parentKey, generation in
                observerByParent[parentKey]?.generation == generation
                    && observerByParent[parentKey]?.exactPathsByWorktreeId[worktreeId]
                        == baseline.exactItemsByParent[parentKey]
            })
        else {
            return nil
        }
        return baseline
    }

    func worktreeHasUnresolvedAncestorInterestLocked(_ worktreeId: UUID) -> Bool {
        observerByParent.values.contains {
            $0.unresolvedAncestorEntriesByWorktreeId[worktreeId] != nil
        }
    }

    private func recheckEntryMatchesBaseline(
        _ recheckEntry: DarwinSharedExactItemAncestorRecheckEntry,
        outcome: DarwinSharedExactItemFingerprintOutcome?
    ) -> Bool {
        guard let baseline = recheckEntry.baseline,
            currentAuthorityBaselineLocked(worktreeId: recheckEntry.worktreeId) == baseline,
            authorityIsCurrentForAncestorRecheck(baseline.authority),
            let fingerprints = outcome?.snapshot?.fingerprintsByCanonicalPath
        else {
            return false
        }
        return recheckEntry.canonicalItemPaths.allSatisfy {
            fingerprints[$0] == baseline.fingerprintsByCanonicalPath[$0]
        }
    }

    private func resolveCompletedEqualWorktreesLocked(
        _ equalWorktreeIds: Set<UUID>,
        fallback fallbackWorktreeIds: inout Set<UUID>
    ) {
        for worktreeId in equalWorktreeIds.sorted(by: Self.sortWorktreeIds)
        where !worktreeHasUnresolvedAncestorInterestLocked(worktreeId) {
            guard let baseline = currentAuthorityBaselineLocked(worktreeId: worktreeId),
                let observedEpoch = currentObservedAncestorAmbiguityEpoch(baseline.authority),
                case .authoritative(let renewedAuthority) = resolveAncestorAmbiguity(
                    baseline.authority,
                    observedEpoch
                ),
                authorityBaselines.replaceAuthority(
                    worktreeId: worktreeId,
                    expectedAuthority: baseline.authority,
                    renewedAuthority: renewedAuthority
                )
            else {
                fallbackWorktreeIds.insert(worktreeId)
                continue
            }
        }
    }

    private func beginAllReadyAncestorRechecksLocked()
        -> [DarwinSharedExactItemAncestorRecheckSnapshot]
    {
        observerByParent.keys.sorted(by: Self.sortParentKeys).compactMap {
            beginNextAncestorRecheckLocked(parentKey: $0)
        }
    }

    private func emitAncestorFallbacks(
        _ fallbackWorktreeIds: Set<UUID>,
        admittedWorktreeIds: Set<UUID>
    ) {
        for worktreeId in fallbackWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            markUncertain(worktreeId)
        }
        for worktreeId in admittedWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            yieldFullGitRefresh(worktreeId, .sharedUncertainty)
        }
    }
}
