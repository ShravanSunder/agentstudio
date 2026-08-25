import AgentStudioBridge
import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

protocol WorkspaceFilesystemSourceManaging: AnyObject, Sendable {
    func start() async
    func shutdown() async
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async
    func unregister(worktreeId: UUID) async
    func assertTopology(_ assertion: FilesystemTopologyAssertion) async
    func setRepositoryFactDemand(_ snapshot: RepositoryFactDemandSnapshot) async
    func waitForRepositoryFactDemandAdmission() async
}

extension WorkspaceFilesystemSourceManaging {
    func setRepositoryFactDemand(_: RepositoryFactDemandSnapshot) async {}
    func waitForRepositoryFactDemandAdmission() async {}
}

extension FilesystemActor: WorkspaceFilesystemSourceManaging {}

private struct FilesystemSourceSyncWriteMetrics {
    let unregisteredCount: Int
    let registeredCount: Int
    let activityWriteCount: Int
    let activePaneWriteCount: Int
    let sidebarVisibleWriteCount: Int
    let topologyGeneration: UInt64?
    let filesystemSourceDuration: Duration
    let admittedWorktreeCount: Int
}

private struct FilesystemSourceSyncWriteBatch {
    let unregisterWorktreeIds: [UUID]
    let registerWorktrees: [FilesystemSourceSyncDiff.Registration]
    let activityUpdates: [FilesystemSourceSyncDiff.ActivityUpdate]
    let admittedWorktreeCount: Int
    let isFinal: Bool
}

private struct FilesystemProjectionAffectedKeys {
    let paneIds: Set<UUID>
    let worktreeIds: Set<UUID>
}

@MainActor
extension WorkspaceSurfaceCoordinator {
    func syncFilesystemRootsAndActivity() {
        scheduleFilesystemRootAndActivitySync()
    }

    func waitForFilesystemRootsAndActivitySyncIdle() async {
        while let activeTask = filesystemSyncTask {
            await activeTask.value
        }
    }

    func syncFilesystemRootsAndActivityUntilIdle() async {
        scheduleFilesystemRootAndActivitySync()
        await waitForFilesystemRootsAndActivitySyncIdle()
    }

    func upsertPaneFilesystemProjectionContext(for pane: Pane) {
        paneContextGeneration &+= 1
        let update = paneFilesystemProjectionUpdate(for: pane, generation: paneContextGeneration)
        scheduleFilesystemPaneUpdate(update, paneId: pane.id)
    }

    func removePaneFilesystemProjectionContext(paneId: UUID) {
        paneContextGeneration &+= 1
        let update = FilesystemProjectionPaneUpdate(
            requestGeneration: paneContextGeneration,
            kind: .remove(paneId: paneId)
        )
        nextFilesystemProjectionSequenceByPaneId.removeValue(forKey: paneId)
        scheduleFilesystemPaneUpdate(update, paneId: paneId)
    }

    func handleFilesystemEnvelopeIfNeeded(_ envelope: RuntimeEnvelope) async -> Bool {
        guard Self.shouldProjectPaneFilesystemEnvelope(envelope) else {
            return false
        }

        let clock = ContinuousClock()
        let totalStart = clock.now
        filesystemProjectionRequestGeneration &+= 1
        let requestGeneration = filesystemProjectionRequestGeneration
        let capturedPaneContextGeneration = paneContextGeneration
        let capturedTopologyGeneration = filesystemAppliedTopologyGeneration

        let indexStart = clock.now
        let projectionResult = await filesystemProjectionIndex.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: requestGeneration,
                paneContextGeneration: capturedPaneContextGeneration,
                topologyGeneration: capturedTopologyGeneration,
                envelope: envelope
            )
        )
        let indexDuration = indexStart.duration(to: clock.now)

        let affectedKeys = Self.affectedKeys(
            from: projectionResult.intents,
            affectedPaneIds: projectionResult.affectedPaneIds,
            affectedWorktreeIds: projectionResult.affectedWorktreeIds
        )
        await publishProductFileEnvelopeIfNeeded(
            envelope,
            affectedKeys: affectedKeys
        )

        guard
            projectionResult.paneContextGeneration == paneContextGeneration,
            projectionResult.topologyGeneration == filesystemAppliedTopologyGeneration
        else {
            return true
        }

        let applyStart = clock.now
        let derivedEnvelopes = projectionResult.intents.map(makeFilesystemProjectionEnvelope)
        let applyDuration = applyStart.duration(to: clock.now)

        performanceTraceRecorder?.recordDuration(
            .coordinatorWrite,
            duration: totalStart.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.coordinator.phase": .string(Self.projectionPhase(for: envelope)),
                "agentstudio.performance.coordinator.derived_envelope.count": .int(derivedEnvelopes.count),
                "agentstudio.performance.coordinator.derived_input.count": .int(projectionResult.derivedInputCount),
                "agentstudio.performance.coordinator.index_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: indexDuration)
                ),
                "agentstudio.performance.coordinator.mainactor_apply_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: applyDuration)
                ),
                "agentstudio.performance.coordinator.input_revision.count": .int(
                    Int(clamping: projectionResult.inputRevision)
                ),
                "agentstudio.performance.coordinator.pane.count": .int(projectionResult.paneCount),
                "agentstudio.performance.coordinator.skipped_unchanged_input.count": .int(
                    projectionResult.skippedUnchangedInputCount
                ),
                "agentstudio.performance.coordinator.total_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: totalStart.duration(to: clock.now))
                ),
                "agentstudio.performance.coordinator.worktree.count": .int(projectionResult.worktreeCount),
            ]
        )
        if !derivedEnvelopes.isEmpty {
            guard
                projectionResult.paneContextGeneration == paneContextGeneration,
                projectionResult.topologyGeneration == filesystemAppliedTopologyGeneration
            else {
                return true
            }
            await publishCurrentDerivedFilesystemEnvelopes(derivedEnvelopes)
        }
        return true
    }

    nonisolated private static func shouldProjectPaneFilesystemEnvelope(_ envelope: RuntimeEnvelope) -> Bool {
        guard case .worktree(let worktreeEnvelope) = envelope else { return false }
        return PaneFilesystemProjectionAdmission.classify(worktreeEnvelope.event).shouldProject
    }

    nonisolated private static func projectionPhase(for envelope: RuntimeEnvelope) -> String {
        guard case .worktree(let worktreeEnvelope) = envelope else { return "unknown" }
        return PaneFilesystemProjectionAdmission.classify(worktreeEnvelope.event).performancePhase
    }

    nonisolated private static func affectedKeys(
        from intents: [PaneFilesystemProjectionIntent],
        affectedPaneIds: Set<UUID> = [],
        affectedWorktreeIds: Set<UUID> = []
    ) -> FilesystemProjectionAffectedKeys {
        var paneIds = affectedPaneIds
        var worktreeIds = affectedWorktreeIds
        for intent in intents {
            switch intent {
            case .cwdSubtreeChanged(let projection):
                paneIds.insert(projection.paneId)
                worktreeIds.insert(projection.context.worktreeId)
            case .gitWorkingTreeInCwd(let projection):
                paneIds.insert(projection.paneId)
                worktreeIds.insert(projection.context.worktreeId)
            }
        }
        return FilesystemProjectionAffectedKeys(
            paneIds: paneIds,
            worktreeIds: worktreeIds
        )
    }

    private func publishProductFileEnvelopeIfNeeded(
        _ envelope: RuntimeEnvelope,
        affectedKeys: FilesystemProjectionAffectedKeys
    ) async {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard let worktreeId = worktreeEnvelope.worktreeId else { return }
        let admitsCrossWorktreeGitInternalInvalidation: Bool
        if case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event {
            admitsCrossWorktreeGitInternalInvalidation =
                changeset.containsGitInternalChanges
                || changeset.suppressedGitInternalPathCount > 0
        } else {
            admitsCrossWorktreeGitInternalInvalidation = false
        }
        guard
            admitsCrossWorktreeGitInternalInvalidation
                || affectedKeys.worktreeIds.contains(worktreeId)
        else { return }

        // Close the observation callback scheduling gap before admitting work from
        // this raw event. The same canonical facts remain the sole activity mint.
        refreshBridgePaneActivities()

        if let worktreeIdentity = productConstructionWorktreeIdentity(
            for: worktreeEnvelope,
            worktreeId: worktreeId
        ) {
            _ = await worktreeProductConstructionCoordinator.invalidate(
                worktree: worktreeIdentity
            )
        }

        for bridgeView in viewRegistry.allBridgeViews.values {
            let controller = bridgeView.controller
            guard controller.runtime.metadata.repoId == worktreeEnvelope.repoId else {
                continue
            }
            let matchesPaneWorktree = controller.runtime.metadata.worktreeId == worktreeId
            switch worktreeEnvelope.event {
            case .filesystem(.filesChanged(let changeset)):
                let invalidation = BridgePaneWorktreeProductInvalidation.filesChanged(changeset)
                guard
                    invalidation.isGitInternalFileInvalidation
                        || (affectedKeys.paneIds.contains(controller.paneId) && matchesPaneWorktree)
                else {
                    continue
                }
                await controller.handleWorktreeProductInvalidation(invalidation)
            case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
                guard affectedKeys.paneIds.contains(controller.paneId),
                    matchesPaneWorktree,
                    snapshot.worktreeId == worktreeId,
                    snapshot.repoId == worktreeEnvelope.repoId
                else {
                    continue
                }
                await controller.handleWorktreeProductInvalidation(
                    .statusChanged(
                        GitWorkingTreeStatus(
                            summary: snapshot.summary,
                            branch: snapshot.branch,
                            origin: nil
                        )
                    )
                )
            case .filesystem, .gitWorkingDirectory, .forge, .security:
                continue
            }
        }
    }

    private func productConstructionWorktreeIdentity(
        for envelope: WorktreeEnvelope,
        worktreeId: UUID
    ) -> BridgeWorktreeIdentityKey? {
        switch envelope.event {
        case .filesystem(.filesChanged(let changeset)):
            guard changeset.repoId == envelope.repoId,
                changeset.worktreeId == worktreeId
            else { return nil }
        case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
            guard snapshot.repoId == envelope.repoId,
                snapshot.worktreeId == worktreeId
            else { return nil }
        case .filesystem, .gitWorkingDirectory, .forge, .security:
            return nil
        }
        guard let repo = store.repositoryTopologyAtom.repo(envelope.repoId),
            let worktree = repo.worktrees.first(where: { $0.id == worktreeId })
        else { return nil }
        return BridgeWorktreeIdentityKey(
            repoIdentity: repo.id.uuidString,
            worktreeIdentity: worktree.id.uuidString,
            stableRootIdentity: StableKey.fromPath(worktree.path)
        )
    }

    func setupFilesystemSourceSync() {
        scheduleFilesystemRootAndActivitySync()
    }

    private func scheduleFilesystemRootAndActivitySync() {
        filesystemSyncRequestGeneration &+= 1
        filesystemFullReconciliationRequestCount &+= 1
        filesystemSyncRequested = true
        startFilesystemEffectTaskIfNeeded()
    }

    private func scheduleFilesystemPaneUpdate(
        _ update: FilesystemProjectionPaneUpdate,
        paneId: UUID
    ) {
        filesystemAffectedKeyRequestCount &+= 1
        pendingFilesystemPaneUpdatesByPaneId[paneId] = update
        startFilesystemEffectTaskIfNeeded()
    }

    private func startFilesystemEffectTaskIfNeeded() {
        guard filesystemSyncTask == nil else { return }

        filesystemSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.filesystemSyncTask = nil }

            while self.hasPendingFilesystemEffects, !Task.isCancelled {
                if self.filesystemSyncRequested {
                    self.filesystemSyncRequested = false
                    await self.performFilesystemRootAndActivitySyncPass()
                } else {
                    await self.performAffectedFilesystemEffectsPass()
                }
                self.recordFilesystemEffectPerformanceSnapshot()
            }
        }
    }

    private var hasPendingFilesystemEffects: Bool {
        filesystemSyncRequested
            || !pendingFilesystemPaneUpdatesByPaneId.isEmpty
    }

    private func performAffectedFilesystemEffectsPass() async {
        let paneUpdates = pendingFilesystemPaneUpdatesByPaneId.values
            .sorted { $0.requestGeneration < $1.requestGeneration }
        pendingFilesystemPaneUpdatesByPaneId.removeAll(keepingCapacity: true)
        var didApplyPaneEffect = false

        for paneUpdate in paneUpdates {
            let outcome = await filesystemProjectionIndex.applyPaneUpdate(paneUpdate)
            let telemetryOutcome: String
            switch outcome {
            case .applied:
                telemetryOutcome = "applied"
            case .stale, .inapplicable:
                telemetryOutcome = "rejected"
            }
            performanceTraceRecorder?.record(
                .filesystemStageOutcome,
                attributes: [
                    "agentstudio.performance.filesystem.stage": .string("affected_key_apply"),
                    "agentstudio.performance.filesystem.outcome": .string(telemetryOutcome),
                ]
            )
            guard case .applied = outcome else { continue }
            didApplyPaneEffect = true
        }

        if didApplyPaneEffect {
            traceIdentityRefreshHandler?()
        }
    }

    private func recordFilesystemEffectPerformanceSnapshot() {
        performanceTraceRecorder?.recordFilesystemEffectSnapshot(
            FilesystemEffectPerformanceSnapshot(
                fullReconciliationRequestCount: filesystemFullReconciliationRequestCount,
                affectedKeyRequestCount: filesystemAffectedKeyRequestCount
            )
        )
    }

    private func performFilesystemRootAndActivitySyncPass() async {
        guard !Task.isCancelled else { return }

        let clock = ContinuousClock()
        let requestGeneration = filesystemSyncRequestGeneration
        let topologyEntries = filesystemProjectionTopologyEntries()
        let paneEntries = filesystemProjectionPaneEntries()
        let activePaneWorktreeId = activePaneWorktree()
        let sidebarVisibleWorktreeIds = atom(\.sidebarVisibleWorktreesRuntime).visibleWorktreeIds

        let indexStart = clock.now
        let syncDiff = await filesystemProjectionIndex.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: requestGeneration,
                paneContextGeneration: paneContextGeneration,
                topologyEntries: topologyEntries,
                paneEntries: paneEntries,
                appliedContextsByWorktreeId: filesystemRegisteredContextsByWorktreeId,
                appliedActivityByWorktreeId: filesystemActivityByWorktreeId,
                activePaneWorktreeId: activePaneWorktreeId,
                appliedActivePaneWorktreeId: filesystemLastActivePaneWorktreeId,
                sidebarVisibleWorktreeIds: sidebarVisibleWorktreeIds,
                appliedSidebarVisibleWorktreeIds: filesystemLastSidebarVisibleWorktreeIds
            )
        )
        let indexDuration = indexStart.duration(to: clock.now)

        guard syncDiff.requestGeneration == filesystemSyncRequestGeneration else {
            filesystemSyncRequested = true
            return
        }

        let writeBatches = filesystemSourceWriteBatches(for: syncDiff)
        var writeMetricsByBatch: [FilesystemSourceSyncWriteMetrics] = []
        for (batchIndex, writeBatch) in writeBatches.enumerated() {
            guard
                let writeMetrics = await applyFilesystemSourceWrites(
                    writeBatch,
                    syncDiff: syncDiff,
                    clock: clock
                )
            else { return }
            writeMetricsByBatch.append(writeMetrics)
            if batchIndex < writeBatches.index(before: writeBatches.endIndex) {
                await Task.yield()
                guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return }
            }
        }

        guard syncDiff.requestGeneration == filesystemSyncRequestGeneration else {
            filesystemSyncRequested = true
            return
        }
        guard let topologyGeneration = writeMetricsByBatch.last?.topologyGeneration else {
            filesystemSyncRequested = true
            return
        }
        let didCommitIndexSnapshot = await filesystemProjectionIndex.commitSourceSync(
            requestGeneration: syncDiff.requestGeneration,
            topologyGeneration: topologyGeneration
        )
        guard didCommitIndexSnapshot else {
            filesystemSyncRequested = true
            return
        }
        guard !Task.isCancelled else { return }
        let applyStart = clock.now
        filesystemRegisteredContextsByWorktreeId = syncDiff.contextsByWorktreeId
        filesystemActivityByWorktreeId = syncDiff.activityByWorktreeId
        filesystemLastActivePaneWorktreeId = syncDiff.activePaneWorktreeId
        filesystemLastSidebarVisibleWorktreeIds = syncDiff.sidebarVisibleWorktreeIds
        filesystemAppliedTopologyGeneration = topologyGeneration
        nextFilesystemProjectionSequenceByPaneId = nextFilesystemProjectionSequenceByPaneId.filter { paneId, _ in
            syncDiff.validPaneIds.contains(paneId)
        }
        let applyDuration = applyStart.duration(to: clock.now)
        recordFilesystemSourceSyncWriteMetrics(
            writeMetricsByBatch,
            syncDiff: syncDiff,
            indexDuration: indexDuration,
            applyDuration: applyDuration
        )
    }

    private func recordFilesystemSourceSyncWriteMetrics(
        _ writeMetricsByBatch: [FilesystemSourceSyncWriteMetrics],
        syncDiff: FilesystemSourceSyncDiff,
        indexDuration: Duration,
        applyDuration: Duration
    ) {
        for (batchIndex, writeMetrics) in writeMetricsByBatch.enumerated() {
            let batchIndexDuration = batchIndex == writeMetricsByBatch.startIndex ? indexDuration : .zero
            let batchApplyDuration =
                batchIndex == writeMetricsByBatch.index(before: writeMetricsByBatch.endIndex)
                ? applyDuration
                : .zero
            let batchTotalDuration = batchIndexDuration + writeMetrics.filesystemSourceDuration + batchApplyDuration
            performanceTraceRecorder?.recordDuration(
                .coordinatorWrite,
                duration: batchTotalDuration,
                attributes: [
                    "agentstudio.performance.coordinator.phase": .string("source_sync"),
                    "agentstudio.performance.coordinator.registered.count": .int(writeMetrics.registeredCount),
                    "agentstudio.performance.coordinator.unregistered.count": .int(writeMetrics.unregisteredCount),
                    "agentstudio.performance.coordinator.activity_write.count": .int(
                        writeMetrics.activityWriteCount
                    ),
                    "agentstudio.performance.coordinator.active_pane_write.count": .int(
                        writeMetrics.activePaneWriteCount
                    ),
                    "agentstudio.performance.coordinator.sidebar_visible_write.count": .int(
                        writeMetrics.sidebarVisibleWriteCount
                    ),
                    "agentstudio.performance.coordinator.filesystem_source_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(
                            from: writeMetrics.filesystemSourceDuration
                        )
                    ),
                    "agentstudio.performance.coordinator.index_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: batchIndexDuration)
                    ),
                    "agentstudio.performance.coordinator.mainactor_apply_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: batchApplyDuration)
                    ),
                    "agentstudio.performance.coordinator.total_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: batchTotalDuration)
                    ),
                    "agentstudio.performance.coordinator.worktree.count": .int(syncDiff.contextsByWorktreeId.count),
                    "agentstudio.performance.coordinator.source_sync.batch_index": .int(batchIndex),
                    "agentstudio.performance.coordinator.source_sync.batch_count": .int(
                        writeMetricsByBatch.count
                    ),
                    "agentstudio.performance.coordinator.source_sync.admitted_worktree.count": .int(
                        writeMetrics.admittedWorktreeCount
                    ),
                ]
            )
        }
    }

    private func applyFilesystemSourceWrites(
        _ writeBatch: FilesystemSourceSyncWriteBatch,
        syncDiff: FilesystemSourceSyncDiff,
        clock: ContinuousClock
    ) async -> FilesystemSourceSyncWriteMetrics? {
        let sourceStart = clock.now
        var unregisteredCount = 0
        var registeredCount = 0
        let activityWriteCount = 0
        let activePaneWriteCount = 0
        let sidebarVisibleWriteCount = 0

        for worktreeId in writeBatch.unregisterWorktreeIds {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            await filesystemSource.unregister(worktreeId: worktreeId)
            recordAppliedFilesystemSourceUnregister(worktreeId: worktreeId)
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            unregisteredCount += 1
        }

        for registration in writeBatch.registerWorktrees {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            if filesystemRegisteredContextsByWorktreeId[registration.worktreeId] != nil {
                await filesystemSource.unregister(worktreeId: registration.worktreeId)
                recordAppliedFilesystemSourceUnregister(worktreeId: registration.worktreeId)
                guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
                unregisteredCount += 1
            }
            await filesystemSource.register(
                worktreeId: registration.worktreeId,
                repoId: registration.repoId,
                rootPath: registration.rootPath
            )
            filesystemRegisteredContextsByWorktreeId[registration.worktreeId] = WorktreeFilesystemContext(
                repoId: registration.repoId,
                rootPath: registration.rootPath
            )
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            registeredCount += 1
        }

        var topologyGeneration: UInt64?
        if writeBatch.isFinal {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            filesystemTopologyAssertionGeneration &+= 1
            topologyGeneration = filesystemTopologyAssertionGeneration
            await filesystemSource.assertTopology(
                FilesystemTopologyAssertion(
                    generation: filesystemTopologyAssertionGeneration,
                    contextsByWorktreeId: syncDiff.contextsByWorktreeId
                )
            )
            recordAppliedFilesystemTopologyAssertion(syncDiff.contextsByWorktreeId)
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
        }

        return FilesystemSourceSyncWriteMetrics(
            unregisteredCount: unregisteredCount,
            registeredCount: registeredCount,
            activityWriteCount: activityWriteCount,
            activePaneWriteCount: activePaneWriteCount,
            sidebarVisibleWriteCount: sidebarVisibleWriteCount,
            topologyGeneration: topologyGeneration,
            filesystemSourceDuration: sourceStart.duration(to: clock.now),
            admittedWorktreeCount: writeBatch.admittedWorktreeCount
        )
    }

    private func filesystemSourceWriteBatches(
        for syncDiff: FilesystemSourceSyncDiff
    ) -> [FilesystemSourceSyncWriteBatch] {
        var orderedWorktreeIds: [UUID] = []
        var admittedWorktreeIds: Set<UUID> = []
        func admit(_ worktreeId: UUID) {
            guard admittedWorktreeIds.insert(worktreeId).inserted else { return }
            orderedWorktreeIds.append(worktreeId)
        }

        syncDiff.unregisterWorktreeIds.forEach(admit)
        syncDiff.registerWorktrees.map(\.worktreeId).forEach(admit)
        syncDiff.activityUpdates.map(\.worktreeId).forEach(admit)

        let maximumBatchSize = AppPolicies.FilesystemSourceSync.maximumWorktreeKeysPerBatch
        precondition(maximumBatchSize > 0)
        let worktreeIdBatches = stride(from: 0, to: orderedWorktreeIds.count, by: maximumBatchSize).map {
            Array(orderedWorktreeIds[$0..<min($0 + maximumBatchSize, orderedWorktreeIds.count)])
        }
        let admittedBatches = worktreeIdBatches.isEmpty ? [[]] : worktreeIdBatches

        return admittedBatches.enumerated().map { batchIndex, worktreeIds in
            let worktreeIdSet = Set(worktreeIds)
            return FilesystemSourceSyncWriteBatch(
                unregisterWorktreeIds: syncDiff.unregisterWorktreeIds.filter(worktreeIdSet.contains),
                registerWorktrees: syncDiff.registerWorktrees.filter {
                    worktreeIdSet.contains($0.worktreeId)
                },
                activityUpdates: syncDiff.activityUpdates.filter {
                    worktreeIdSet.contains($0.worktreeId)
                },
                admittedWorktreeCount: worktreeIds.count,
                isFinal: batchIndex == admittedBatches.index(before: admittedBatches.endIndex)
            )
        }
    }

    private func recordAppliedFilesystemSourceUnregister(worktreeId: UUID) {
        filesystemRegisteredContextsByWorktreeId.removeValue(forKey: worktreeId)
        filesystemActivityByWorktreeId.removeValue(forKey: worktreeId)
        if filesystemLastActivePaneWorktreeId == worktreeId {
            filesystemLastActivePaneWorktreeId = nil
        }
    }

    private func recordAppliedFilesystemTopologyAssertion(
        _ contextsByWorktreeId: [UUID: WorktreeFilesystemContext]
    ) {
        let desiredWorktreeIds = Set(contextsByWorktreeId.keys)
        filesystemRegisteredContextsByWorktreeId = contextsByWorktreeId
        filesystemActivityByWorktreeId = filesystemActivityByWorktreeId.filter { worktreeId, _ in
            desiredWorktreeIds.contains(worktreeId)
        }
        if let filesystemLastActivePaneWorktreeId,
            !desiredWorktreeIds.contains(filesystemLastActivePaneWorktreeId)
        {
            self.filesystemLastActivePaneWorktreeId = nil
        }
    }

    private func continueFilesystemSourceWrites(for requestGeneration: UInt64) -> Bool {
        guard !Task.isCancelled else { return false }
        guard requestGeneration == filesystemSyncRequestGeneration else {
            filesystemSyncRequested = true
            return false
        }
        return true
    }

    func activePaneWorktree() -> UUID? {
        guard let activePaneId = store.tabLayoutAtom.activeTab?.activePaneId else { return nil }
        return store.paneAtom.pane(activePaneId)?.worktreeId
    }

    private func filesystemProjectionTopologyEntries() -> [FilesystemProjectionTopologyEntry] {
        var entries: [FilesystemProjectionTopologyEntry] = []
        for repo in store.repositoryTopologyAtom.repos where !store.repositoryTopologyAtom.isRepoUnavailable(repo.id) {
            for worktree in repo.worktrees {
                entries.append(
                    FilesystemProjectionTopologyEntry(
                        repoId: repo.id,
                        worktreeId: worktree.id,
                        rootPath: worktree.path,
                        isUnavailable: false
                    )
                )
            }
        }
        return entries
    }

    private func filesystemProjectionPaneEntries() -> [FilesystemProjectionPaneEntry] {
        store.paneAtom.paneSnapshot().values.map { pane in
            FilesystemProjectionPaneEntry(
                paneId: pane.id,
                paneKind: pane.metadata.contentType,
                repoId: pane.repoId ?? pane.metadata.repoId,
                worktreeId: pane.worktreeId ?? pane.metadata.worktreeId,
                cwd: pane.metadata.facets.cwd ?? pane.metadata.launchDirectory
            )
        }
    }

    private func paneFilesystemProjectionUpdate(
        for pane: Pane,
        generation: UInt64
    ) -> FilesystemProjectionPaneUpdate {
        let repoId = pane.repoId ?? pane.metadata.repoId
        let worktreeId = pane.worktreeId ?? pane.metadata.worktreeId
        guard let repoId, let worktreeId else {
            return FilesystemProjectionPaneUpdate(
                requestGeneration: generation,
                kind: .remove(paneId: pane.id)
            )
        }
        let fallbackCwd =
            store.repositoryTopologyAtom.worktree(worktreeId)?.path
            ?? pane.metadata.launchDirectory
            ?? pane.metadata.cwd

        return FilesystemProjectionPaneUpdate(
            requestGeneration: generation,
            kind: .upsert(
                FilesystemProjectionPaneEntry(
                    paneId: pane.id,
                    paneKind: pane.metadata.contentType,
                    repoId: repoId,
                    worktreeId: worktreeId,
                    cwd: pane.metadata.cwd ?? fallbackCwd
                )
            )
        )
    }

    func publishCurrentDerivedFilesystemEnvelopes(_ envelopes: [RuntimeEnvelope]) async {
        let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceSurfaceCoordinator")
        for envelope in envelopes {
            guard isCurrentDerivedFilesystemEnvelope(envelope) else { continue }
            let result = await paneEventBus.post(envelope)
            if result.droppedCount > 0 {
                logger.warning(
                    "Dropped derived filesystem context event for \(result.droppedCount, privacy: .public) subscriber(s); seq=\(envelope.seq, privacy: .public)"
                )
            }
        }
    }

    private func isCurrentDerivedFilesystemEnvelope(_ envelope: RuntimeEnvelope) -> Bool {
        guard
            case .pane(let paneEnvelope) = envelope,
            case .paneFilesystemContext(let event) = paneEnvelope.event
        else {
            return false
        }
        let projectedContext: PaneFilesystemContext
        switch event {
        case .cwdSubtreeChanged(let context, _, _), .gitWorkingTreeInCwd(let context, _, _, _):
            projectedContext = context
        }
        guard paneEnvelope.paneId == projectedContext.paneId else { return false }
        return currentPaneFilesystemContext(paneId: projectedContext.paneId.uuid) == projectedContext
    }

    private func currentPaneFilesystemContext(paneId: UUID) -> PaneFilesystemContext? {
        guard store.paneAtom.graphAtom.paneState(paneId) != nil else { return nil }
        guard
            let pane = store.paneAtom.pane(paneId),
            let repoId = pane.repoId ?? pane.metadata.repoId,
            let worktreeId = pane.worktreeId ?? pane.metadata.worktreeId
        else {
            return nil
        }
        let cwd =
            pane.metadata.cwd
            ?? store.repositoryTopologyAtom.worktree(worktreeId)?.path
            ?? pane.metadata.launchDirectory
        guard let cwd else { return nil }
        return PaneFilesystemContext(
            paneId: PaneId(existingUUID: paneId),
            repoId: repoId,
            cwd: cwd.standardizedFileURL,
            worktreeId: worktreeId
        )
    }

    private func makeFilesystemProjectionEnvelope(_ intent: PaneFilesystemProjectionIntent) -> RuntimeEnvelope {
        switch intent {
        case .cwdSubtreeChanged(let projection):
            return makeFilesystemProjectionEnvelope(
                paneId: projection.paneId,
                paneKind: projection.paneKind,
                timestamp: projection.timestamp,
                correlationId: projection.correlationId,
                commandId: projection.commandId,
                event: .paneFilesystemContext(
                    .cwdSubtreeChanged(
                        context: projection.context,
                        paths: Set(projection.paths),
                        batchSeq: projection.batchSequence
                    )
                )
            )
        case .gitWorkingTreeInCwd(let projection):
            return makeFilesystemProjectionEnvelope(
                paneId: projection.paneId,
                paneKind: projection.paneKind,
                timestamp: projection.timestamp,
                correlationId: projection.correlationId,
                commandId: projection.commandId,
                event: .paneFilesystemContext(
                    .gitWorkingTreeInCwd(
                        context: projection.context,
                        staged: projection.summary.staged,
                        unstaged: projection.summary.changed,
                        untracked: projection.summary.untracked
                    )
                )
            )
        }
    }

    private func makeFilesystemProjectionEnvelope(
        paneId: UUID,
        paneKind: PaneContentType,
        timestamp: ContinuousClock.Instant,
        correlationId: UUID?,
        commandId: UUID?,
        event: PaneRuntimeEvent
    ) -> RuntimeEnvelope {
        let nextSequence = nextFilesystemProjectionSequenceByPaneId[paneId, default: 0] + 1
        nextFilesystemProjectionSequenceByPaneId[paneId] = nextSequence

        let typedPaneId = PaneId(existingUUID: paneId)
        return .pane(
            PaneEnvelope(
                source: .pane(typedPaneId),
                seq: nextSequence,
                timestamp: timestamp,
                correlationId: correlationId,
                commandId: commandId,
                paneId: typedPaneId,
                paneKind: paneKind,
                event: event
            )
        )
    }
}
