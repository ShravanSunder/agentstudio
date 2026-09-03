import Foundation

struct DarwinSharedExactItemAncestorUnresolvedEntry: Equatable, Sendable {
    var observedEpoch: UInt64
    var latestEventId: FSEventStreamEventId
    var canonicalItemPaths: Set<String>

    mutating func merge(
        observedEpoch: UInt64,
        latestEventId: FSEventStreamEventId,
        canonicalItemPaths: Set<String>
    ) {
        self.observedEpoch = observedEpoch
        self.latestEventId = max(self.latestEventId, latestEventId)
        self.canonicalItemPaths.formUnion(canonicalItemPaths)
    }
}

struct DarwinSharedExactItemAncestorRecheckEntry: Equatable, Sendable {
    let worktreeId: UUID
    let observedEpoch: UInt64
    let latestEventId: FSEventStreamEventId
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
    let parentKey: DarwinSharedExactItemParentKey
    let streamGeneration: UInt64
    let activityObservationBatch: FSEventActivityObservationBatch
    let mutationEventsByWorktreeId: [UUID: [DarwinFSEventClassifiedRawEvent]]
    let uncertainWorktreeIds: Set<UUID>
    let exactSubscriberWorktreeIds: Set<UUID>
    let fullGitRefreshWorktreeIds: Set<UUID>
    let retiredStreamLifetime: (any DarwinSharedExactItemStreamLifetime)?
    let ancestorRecheckToStart: DarwinSharedExactItemAncestorRecheckSnapshot?
}

private enum DarwinSharedExactItemAncestorActivityDisposition {
    case equal
    case qualifyingChange
    case coverageLost
}

extension DarwinSharedExactItemObserverRegistry {
    static func makeActivityObservationBatch(
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64,
        rawEvents: [DarwinSharedExactItemRawEvent],
        participantWorktreeIds: Set<UUID>,
        qualifyingWorktreeIds: Set<UUID>,
        coverageLostWorktreeIds: Set<UUID>
    ) -> FSEventActivityObservationBatch {
        let processedThroughEventID = rawEvents.map(\.eventId).max() ?? 0
        return FSEventActivityObservationBatch(
            participant: FSEventParticipant(
                scopeKey: "shared:\(parentKey.volumeSystemNumber):\(parentKey.parentPath)",
                generation: streamGeneration,
                volumeIdentifier: String(parentKey.volumeSystemNumber)
            ),
            processedThroughEventID: UInt64(processedThroughEventID),
            participantWorktreeIds: participantWorktreeIds,
            qualifyingWorktreeIds: qualifyingWorktreeIds,
            coverageLostWorktreeIds: coverageLostWorktreeIds
        )
    }

    func emitReceiveEffects(_ effects: DarwinSharedExactItemReceiveEffects) {
        performanceAccumulator.recordSharedFanout(
            exactSubscriberCount: effects.exactSubscriberWorktreeIds.count,
            uncertaintySubscriberCount: effects.uncertainWorktreeIds.count,
            fullRefreshEmissionCount: effects.fullGitRefreshWorktreeIds.count
        )
        yieldActivityObservations(effects.activityObservationBatch)
        completeActivityDelivery(
            parentKey: effects.parentKey,
            streamGeneration: effects.streamGeneration
        )
        for worktreeId in effects.mutationEventsByWorktreeId.keys.sorted(by: Self.sortWorktreeIds) {
            guard let events = effects.mutationEventsByWorktreeId[worktreeId] else { continue }
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
                        latestEventId: unresolvedEntry.latestEventId,
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
        var qualifyingActivityWorktreeIds: Set<UUID> = []
        for worktreeId in recheck.entriesByWorktreeId.keys.sorted(by: Self.sortWorktreeIds) {
            guard let recheckEntry = recheck.entriesByWorktreeId[worktreeId],
                let unresolvedEntry = observer.unresolvedAncestorEntriesByWorktreeId[worktreeId]
            else {
                continue
            }
            guard unresolvedEntry.observedEpoch == recheckEntry.observedEpoch,
                unresolvedEntry.latestEventId == recheckEntry.latestEventId,
                unresolvedEntry.canonicalItemPaths == recheckEntry.canonicalItemPaths
            else {
                fallbackWorktreeIds.insert(worktreeId)
                continue
            }
            switch activityDisposition(recheckEntry, outcome: outcome) {
            case .equal:
                observer.unresolvedAncestorEntriesByWorktreeId.removeValue(forKey: worktreeId)
                equalWorktreeIds.insert(worktreeId)
            case .qualifyingChange:
                observer.unresolvedAncestorEntriesByWorktreeId.removeValue(forKey: worktreeId)
                qualifyingActivityWorktreeIds.insert(worktreeId)
                fallbackWorktreeIds.insert(worktreeId)
            case .coverageLost:
                observer.unresolvedAncestorEntriesByWorktreeId.removeValue(forKey: worktreeId)
                fallbackWorktreeIds.insert(worktreeId)
            }
        }
        observerByParent[recheck.parentKey] = observer
        resolveCompletedEqualWorktreesLocked(equalWorktreeIds, fallback: &fallbackWorktreeIds)

        let coverageLostWorktreeIds = fallbackWorktreeIds.subtracting(
            qualifyingActivityWorktreeIds
        )
        let terminalWorktreeIds =
            equalWorktreeIds
            .union(qualifyingActivityWorktreeIds)
            .union(coverageLostWorktreeIds)
        let activityObservationBatch = makeAncestorCompletionActivityObservationBatch(
            recheck,
            participantWorktreeIds: terminalWorktreeIds,
            qualifyingWorktreeIds: qualifyingActivityWorktreeIds,
            coverageLostWorktreeIds: coverageLostWorktreeIds
        )
        if activityObservationBatch != nil,
            var currentObserver = observerByParent[recheck.parentKey],
            currentObserver.generation == recheck.streamGeneration
        {
            currentObserver.pendingActivityDeliveryCount += 1
            observerByParent[recheck.parentKey] = currentObserver
        }
        let successorRechecks = beginAllReadyAncestorRechecksLocked()
        let admittedFallbackWorktreeIds = admitFullRefreshLocked(fallbackWorktreeIds)
        lifecycleCondition.unlock()

        if let activityObservationBatch {
            yieldActivityObservations(activityObservationBatch)
            completeActivityDelivery(
                parentKey: recheck.parentKey,
                streamGeneration: recheck.streamGeneration
            )
        }
        emitAncestorFallbacks(
            fallbackWorktreeIds,
            admittedWorktreeIds: admittedFallbackWorktreeIds
        )
        for successor in successorRechecks {
            startAncestorRecheck(successor)
        }
    }

    func completeActivityDelivery(
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64
    ) {
        lifecycleCondition.withLock {
            guard var observer = observerByParent[parentKey],
                observer.generation == streamGeneration,
                observer.pendingActivityDeliveryCount > 0
            else {
                return
            }
            observer.pendingActivityDeliveryCount -= 1
            if observer.pendingActivityDeliveryCount == 0,
                observer.unresolvedAncestorEntriesByWorktreeId.isEmpty
            {
                observer.latestActivitySettledEventId = observer.latestEventId
            }
            observerByParent[parentKey] = observer
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

    private func activityDisposition(
        _ recheckEntry: DarwinSharedExactItemAncestorRecheckEntry,
        outcome: DarwinSharedExactItemFingerprintOutcome?
    ) -> DarwinSharedExactItemAncestorActivityDisposition {
        guard let baseline = recheckEntry.baseline,
            currentAuthorityBaselineLocked(worktreeId: recheckEntry.worktreeId) == baseline,
            authorityIsCurrentForAncestorRecheck(baseline.authority),
            let fingerprints = outcome?.snapshot?.fingerprintsByCanonicalPath
        else {
            return .coverageLost
        }

        let changedPaths = recheckEntry.canonicalItemPaths.filter {
            fingerprints[$0] != baseline.fingerprintsByCanonicalPath[$0]
        }
        guard !changedPaths.isEmpty else {
            let baselineMissingPath = recheckEntry.canonicalItemPaths.contains {
                baseline.fingerprintsByCanonicalPath[$0]?.kind == .missing
            }
            return baselineMissingPath ? .coverageLost : .equal
        }
        return changedPaths.contains(where: RepositoryLocalActivityPathClassifier.qualifiesGitMetadataPath)
            ? .qualifyingChange : .coverageLost
    }

    private func makeAncestorCompletionActivityObservationBatch(
        _ recheck: DarwinSharedExactItemAncestorRecheckSnapshot,
        participantWorktreeIds: Set<UUID>,
        qualifyingWorktreeIds: Set<UUID>,
        coverageLostWorktreeIds: Set<UUID>
    ) -> FSEventActivityObservationBatch? {
        guard !participantWorktreeIds.isEmpty else { return nil }
        let processedThroughEventID =
            participantWorktreeIds.compactMap {
                recheck.entriesByWorktreeId[$0]?.latestEventId
            }.max() ?? 0
        return FSEventActivityObservationBatch(
            participant: FSEventParticipant(
                scopeKey:
                    "shared:\(recheck.parentKey.volumeSystemNumber):\(recheck.parentKey.parentPath)",
                generation: recheck.streamGeneration,
                volumeIdentifier: String(recheck.parentKey.volumeSystemNumber)
            ),
            processedThroughEventID: UInt64(processedThroughEventID),
            participantWorktreeIds: participantWorktreeIds,
            qualifyingWorktreeIds: qualifyingWorktreeIds,
            coverageLostWorktreeIds: coverageLostWorktreeIds
        )
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
