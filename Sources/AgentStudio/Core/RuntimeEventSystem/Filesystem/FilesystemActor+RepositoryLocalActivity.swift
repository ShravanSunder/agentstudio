import Foundation

struct FilesystemPendingActivityCheckpoint: Sendable {
    var firstPendingTimestamp: Duration?
    var lastPendingTimestamp: Duration?

    var isPending: Bool {
        firstPendingTimestamp != nil && lastPendingTimestamp != nil
    }

    mutating func record(at timestamp: Duration) {
        if firstPendingTimestamp == nil {
            firstPendingTimestamp = timestamp
        }
        lastPendingTimestamp = timestamp
    }
}

extension FilesystemActor {
    package func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        let desiredRepositoryStableKeysByWorktreeId = assertion.repositoryStableKeysByWorktreeId.filter {
            assertion.contextsByWorktreeId[$0.key] != nil
        }
        let previousRepositoryStableKeysByWorktreeId = repositoryStableKeysByWorktreeId
        let activityTopologyChanged =
            previousRepositoryStableKeysByWorktreeId
            != desiredRepositoryStableKeysByWorktreeId
            || assertion.contextsByWorktreeId.count != roots.count
            || assertion.contextsByWorktreeId.contains { worktreeId, context in
                roots[worktreeId]?.repoId != context.repoId
                    || roots[worktreeId]?.rootPath != context.rootPath
            }
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        let removedWorktreeIds = Set(roots.keys).subtracting(desiredWorktreeIds)
        for worktreeId in removedWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            await unregister(worktreeId: worktreeId)
        }

        for (worktreeId, context) in assertion.contextsByWorktreeId.sorted(by: { lhs, rhs in
            Self.sortWorktreeIds(lhs.key, rhs.key)
        }) {
            let repositoryIdentityChanged =
                previousRepositoryStableKeysByWorktreeId[worktreeId]
                != desiredRepositoryStableKeysByWorktreeId[worktreeId]
            let filesystemIdentityChanged =
                roots[worktreeId]?.repoId != context.repoId
                || roots[worktreeId]?.rootPath != context.rootPath
            guard repositoryIdentityChanged || filesystemIdentityChanged else {
                continue
            }
            if repositoryIdentityChanged, roots[worktreeId] != nil {
                await unregister(worktreeId: worktreeId)
            }
            await register(worktreeId: worktreeId, repoId: context.repoId, rootPath: context.rootPath)
        }
        repositoryStableKeysByWorktreeId = desiredRepositoryStableKeysByWorktreeId
        if activityTopologyChanged {
            recordPendingActivityCheckpoint()
            scheduleDrainIfNeeded()
        }
    }

    func ingestSharedActivityObservations(
        _ batch: FSEventActivityObservationBatch
    ) async {
        await repositoryLocalActivityProjector?.ingest(
            RepositoryLocalActivityObservedEvent(
                scopeKey: batch.participant.scopeKey,
                generation: batch.participant.generation,
                eventID: batch.processedThroughEventID,
                qualifyingRepositoryStableKeys: Set(
                    batch.qualifyingWorktreeIds.compactMap {
                        repositoryStableKeysByWorktreeId[$0]
                    }
                ),
                coverageLostRepositoryStableKeys: Set(
                    batch.coverageLostWorktreeIds.compactMap {
                        repositoryStableKeysByWorktreeId[$0]
                    }
                ),
                observedAt: Date()
            )
        )
        recordPendingActivityCheckpoint()
    }

    func consumeActivityOverflowRecoveries() async {
        for recovery in fseventStreamClient.consumeActivityOverflowRecoveries() {
            await repositoryLocalActivityProjector?.ingest(
                RepositoryLocalActivityObservedEvent(
                    scopeKey: recovery.participant.scopeKey,
                    generation: recovery.participant.generation,
                    eventID: recovery.processedThroughEventID,
                    coverageLostRepositoryStableKeys: Set(
                        recovery.coverageLostWorktreeIds.compactMap {
                            repositoryStableKeysByWorktreeId[$0]
                        }
                    ),
                    observedAt: Date()
                )
            )
            recordPendingActivityCheckpoint()
        }
        let coarseCoverageLossRepositoryStableKeys = Set(
            fseventStreamClient.consumeCoarseActivityOverflowWorktreeIds().compactMap {
                repositoryStableKeysByWorktreeId[$0]
            }
        )
        if !coarseCoverageLossRepositoryStableKeys.isEmpty {
            pendingCoarseActivityCoverageLossRepositoryStableKeys.formUnion(
                coarseCoverageLossRepositoryStableKeys
            )
            recordPendingActivityCheckpoint()
        }
    }

    func recordPendingActivityCheckpoint() {
        guard repositoryLocalActivityProjector != nil else { return }
        pendingActivityCheckpoint.record(at: schedulingClock.now())
        activityCheckpointRevision &+= 1
    }

    func activityCheckpointIsDue(now: Duration) -> Bool {
        guard let deadline = activityCheckpointDeadline() else { return false }
        return now >= deadline
    }

    func activityCheckpointDeadline() -> Duration? {
        guard let firstPendingTimestamp = pendingActivityCheckpoint.firstPendingTimestamp,
            let lastPendingTimestamp = pendingActivityCheckpoint.lastPendingTimestamp
        else {
            return nil
        }
        return min(
            lastPendingTimestamp + debounceWindow,
            firstPendingTimestamp + maxFlushLatency
        )
    }

    func checkpointRepositoryLocalActivity() async {
        guard let repositoryLocalActivityProjector else {
            pendingActivityCheckpoint = FilesystemPendingActivityCheckpoint()
            return
        }
        guard let barrier = await fseventStreamClient.captureActivityBarrier() else {
            rescheduleActivityCheckpointAfterFailure()
            return
        }
        let capturedRevision = activityCheckpointRevision
        var repositoryStableKeysByParticipant: [FSEventParticipant: Set<String>] = [:]
        for binding in barrier.bindings {
            guard let repositoryStableKey = repositoryStableKeysByWorktreeId[binding.worktreeId]
            else {
                repositoryStableKeysByParticipant[binding.participant, default: []] = []
                continue
            }
            repositoryStableKeysByParticipant[binding.participant, default: []].insert(
                repositoryStableKey
            )
        }
        let participants = repositoryStableKeysByParticipant.map { participant, stableKeys in
            RepositoryLocalActivityParticipant(
                scopeKey: participant.scopeKey,
                generation: participant.generation,
                volumeIdentifier: participant.volumeIdentifier,
                repositoryStableKeys: stableKeys
            )
        }.sorted { $0.scopeKey < $1.scopeKey }
        let completedAt = Date()
        await repositoryLocalActivityProjector.replaceParticipants(
            participants,
            coverageRestartedAt: completedAt
        )
        let deliveredEventIDByParticipant = Dictionary(
            uniqueKeysWithValues: barrier.deliveredEventIDByParticipant.map { participant, eventID in
                (
                    RepositoryLocalActivityParticipantIdentity(
                        scopeKey: participant.scopeKey,
                        generation: participant.generation
                    ),
                    eventID
                )
            }
        )
        await applyCoarseActivityCoverageLoss(
            participants: participants,
            deliveredEventIDByParticipant: deliveredEventIDByParticipant,
            observedAt: completedAt,
            projector: repositoryLocalActivityProjector
        )
        do {
            let didCommit = try await repositoryLocalActivityProjector.commitBarrier(
                RepositoryLocalActivityBarrier(
                    deliveredEventIDByParticipant: deliveredEventIDByParticipant,
                    completedAt: completedAt
                )
            )
            guard didCommit else {
                rescheduleActivityCheckpointAfterFailure()
                return
            }
            pendingCoarseActivityCoverageLossRepositoryStableKeys.removeAll(
                keepingCapacity: true
            )
            if activityCheckpointRevision == capturedRevision {
                pendingActivityCheckpoint = FilesystemPendingActivityCheckpoint()
            }
        } catch {
            Self.logger.error(
                "Repository activity checkpoint failed: \(String(describing: error), privacy: .public)"
            )
            rescheduleActivityCheckpointAfterFailure()
        }
    }

    private func applyCoarseActivityCoverageLoss(
        participants: [RepositoryLocalActivityParticipant],
        deliveredEventIDByParticipant: [RepositoryLocalActivityParticipantIdentity: UInt64],
        observedAt: Date,
        projector: RepositoryLocalActivityProjector
    ) async {
        guard !pendingCoarseActivityCoverageLossRepositoryStableKeys.isEmpty else { return }
        for participant in participants {
            guard let deliveredEventID = deliveredEventIDByParticipant[participant.identity] else {
                continue
            }
            await projector.ingest(
                RepositoryLocalActivityObservedEvent(
                    scopeKey: participant.scopeKey,
                    generation: participant.generation,
                    eventID: deliveredEventID,
                    coverageLostRepositoryStableKeys:
                        pendingCoarseActivityCoverageLossRepositoryStableKeys.intersection(
                            participant.repositoryStableKeys
                        ),
                    observedAt: observedAt
                )
            )
        }
    }

    private func rescheduleActivityCheckpointAfterFailure() {
        let retryTimestamp = schedulingClock.now()
        pendingActivityCheckpoint = FilesystemPendingActivityCheckpoint(
            firstPendingTimestamp: retryTimestamp,
            lastPendingTimestamp: retryTimestamp
        )
    }
}
