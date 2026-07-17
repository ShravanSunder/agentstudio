import Foundation
import os

protocol WorkspaceFilesystemSourceManaging: AnyObject, Sendable {
    func start() async
    func shutdown() async
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async
    func unregister(worktreeId: UUID) async
    func assertTopology(_ assertion: FilesystemTopologyAssertion) async
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async
    func setActivePaneWorktree(worktreeId: UUID?) async
}

extension FilesystemActor: WorkspaceFilesystemSourceManaging {}

private struct FilesystemSourceSyncWriteMetrics {
    let unregisteredCount: Int
    let registeredCount: Int
    let activityWriteCount: Int
    let activePaneWriteCount: Int
    let topologyGeneration: UInt64
    let filesystemSourceDuration: Duration
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
        Task { [filesystemProjectionIndex] in
            await filesystemProjectionIndex.applyPaneUpdate(update)
        }
    }

    func removePaneFilesystemProjectionContext(paneId: UUID) {
        paneContextGeneration &+= 1
        let update = FilesystemProjectionPaneUpdate(
            requestGeneration: paneContextGeneration,
            kind: .remove(paneId: paneId)
        )
        nextFilesystemProjectionSequenceByPaneId.removeValue(forKey: paneId)
        Task { [filesystemProjectionIndex] in
            await filesystemProjectionIndex.applyPaneUpdate(update)
        }
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
                "agentstudio.performance.coordinator.index_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: indexDuration)
                ),
                "agentstudio.performance.coordinator.mainactor_apply_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: applyDuration)
                ),
                "agentstudio.performance.coordinator.pane.count": .int(projectionResult.paneCount),
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
            await Self.publishDerivedFilesystemEnvelopes(
                derivedEnvelopes,
                to: paneEventBus
            )
        }
        return true
    }

    nonisolated private static func shouldProjectPaneFilesystemEnvelope(_ envelope: RuntimeEnvelope) -> Bool {
        guard case .worktree(let worktreeEnvelope) = envelope else { return false }
        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged), .gitWorkingDirectory(.snapshotChanged):
            return true
        case .filesystem, .gitWorkingDirectory, .forge, .security:
            return false
        }
    }

    nonisolated private static func projectionPhase(for envelope: RuntimeEnvelope) -> String {
        guard case .worktree(let worktreeEnvelope) = envelope else { return "unknown" }
        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged):
            return "filesystem_projection"
        case .gitWorkingDirectory(.snapshotChanged):
            return "git_snapshot_projection"
        default:
            return "unknown"
        }
    }

    func setupFilesystemSourceSync() {
        scheduleFilesystemRootAndActivitySync()
    }

    private func scheduleFilesystemRootAndActivitySync() {
        filesystemSyncRequestGeneration &+= 1
        filesystemSyncRequested = true
        guard filesystemSyncTask == nil else { return }

        filesystemSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.filesystemSyncTask = nil }

            while self.filesystemSyncRequested, !Task.isCancelled {
                self.filesystemSyncRequested = false
                await self.performFilesystemRootAndActivitySyncPass()
            }
        }
    }

    private func performFilesystemRootAndActivitySyncPass() async {
        guard !Task.isCancelled else { return }

        let clock = ContinuousClock()
        let totalStart = clock.now
        let requestGeneration = filesystemSyncRequestGeneration
        let topologyEntries = filesystemProjectionTopologyEntries()
        let paneEntries = filesystemProjectionPaneEntries()
        let activePaneWorktreeId = activePaneWorktree()

        let indexStart = clock.now
        let syncDiff = await filesystemProjectionIndex.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: requestGeneration,
                paneContextGeneration: paneContextGeneration,
                topologyEntries: topologyEntries,
                paneEntries: paneEntries,
                appliedActivityByWorktreeId: filesystemActivityByWorktreeId,
                activePaneWorktreeId: activePaneWorktreeId,
                appliedActivePaneWorktreeId: filesystemLastActivePaneWorktreeId
            )
        )
        let indexDuration = indexStart.duration(to: clock.now)

        guard syncDiff.requestGeneration == filesystemSyncRequestGeneration else {
            filesystemSyncRequested = true
            return
        }

        guard let writeMetrics = await applyFilesystemSourceWrites(syncDiff, clock: clock) else { return }

        guard syncDiff.requestGeneration == filesystemSyncRequestGeneration else {
            filesystemSyncRequested = true
            return
        }
        let didCommitIndexSnapshot = await filesystemProjectionIndex.commitSourceSync(
            requestGeneration: syncDiff.requestGeneration,
            topologyGeneration: writeMetrics.topologyGeneration
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
        filesystemAppliedTopologyGeneration = writeMetrics.topologyGeneration
        nextFilesystemProjectionSequenceByPaneId = nextFilesystemProjectionSequenceByPaneId.filter { paneId, _ in
            syncDiff.validPaneIds.contains(paneId)
        }
        let applyDuration = applyStart.duration(to: clock.now)
        performanceTraceRecorder?.recordDuration(
            .coordinatorWrite,
            duration: totalStart.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.coordinator.phase": .string("source_sync"),
                "agentstudio.performance.coordinator.registered.count": .int(writeMetrics.registeredCount),
                "agentstudio.performance.coordinator.unregistered.count": .int(writeMetrics.unregisteredCount),
                "agentstudio.performance.coordinator.activity_write.count": .int(writeMetrics.activityWriteCount),
                "agentstudio.performance.coordinator.active_pane_write.count": .int(
                    writeMetrics.activePaneWriteCount
                ),
                "agentstudio.performance.coordinator.filesystem_source_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: writeMetrics.filesystemSourceDuration)
                ),
                "agentstudio.performance.coordinator.index_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: indexDuration)
                ),
                "agentstudio.performance.coordinator.mainactor_apply_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: applyDuration)
                ),
                "agentstudio.performance.coordinator.total_elapsed_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: totalStart.duration(to: clock.now))
                ),
                "agentstudio.performance.coordinator.worktree.count": .int(syncDiff.contextsByWorktreeId.count),
            ]
        )
    }

    private func applyFilesystemSourceWrites(
        _ syncDiff: FilesystemSourceSyncDiff,
        clock: ContinuousClock
    ) async -> FilesystemSourceSyncWriteMetrics? {
        let sourceStart = clock.now
        var unregisteredCount = 0
        var registeredCount = 0
        var activityWriteCount = 0
        var activePaneWriteCount = 0

        for worktreeId in syncDiff.unregisterWorktreeIds {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            await filesystemSource.unregister(worktreeId: worktreeId)
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            unregisteredCount += 1
        }

        for registration in syncDiff.registerWorktrees {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            if filesystemRegisteredContextsByWorktreeId[registration.worktreeId] != nil {
                await filesystemSource.unregister(worktreeId: registration.worktreeId)
                guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
                unregisteredCount += 1
            }
            await filesystemSource.register(
                worktreeId: registration.worktreeId,
                repoId: registration.repoId,
                rootPath: registration.rootPath
            )
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            registeredCount += 1
        }

        for activityUpdate in syncDiff.activityUpdates {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            await filesystemSource.setActivity(
                worktreeId: activityUpdate.worktreeId,
                isActiveInApp: activityUpdate.isActiveInApp
            )
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            activityWriteCount += 1
        }

        if syncDiff.shouldUpdateActivePaneWorktree {
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            await filesystemSource.setActivePaneWorktree(worktreeId: syncDiff.activePaneWorktreeId)
            guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
            activePaneWriteCount = 1
        }

        guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }
        filesystemTopologyAssertionGeneration &+= 1
        let topologyGeneration = filesystemTopologyAssertionGeneration
        await filesystemSource.assertTopology(
            FilesystemTopologyAssertion(
                generation: topologyGeneration,
                contextsByWorktreeId: syncDiff.contextsByWorktreeId
            )
        )
        guard continueFilesystemSourceWrites(for: syncDiff.requestGeneration) else { return nil }

        return FilesystemSourceSyncWriteMetrics(
            unregisteredCount: unregisteredCount,
            registeredCount: registeredCount,
            activityWriteCount: activityWriteCount,
            activePaneWriteCount: activePaneWriteCount,
            topologyGeneration: topologyGeneration,
            filesystemSourceDuration: sourceStart.duration(to: clock.now)
        )
    }

    private func continueFilesystemSourceWrites(for requestGeneration: UInt64) -> Bool {
        guard !Task.isCancelled else { return false }
        guard requestGeneration == filesystemSyncRequestGeneration else {
            filesystemSyncRequested = true
            return false
        }
        return true
    }

    private func activePaneWorktree() -> UUID? {
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
        store.paneAtom.panes.values.map { pane in
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
        guard let repoId = pane.repoId, let worktreeId = pane.worktreeId else {
            return FilesystemProjectionPaneUpdate(
                requestGeneration: generation,
                kind: .remove(paneId: pane.id)
            )
        }

        let fallbackCwd =
            store.repositoryTopologyAtom.worktree(worktreeId)?.path
            ?? pane.metadata.launchDirectory
            ?? pane.metadata.cwd
        guard let fallbackCwd else {
            return FilesystemProjectionPaneUpdate(
                requestGeneration: generation,
                kind: .remove(paneId: pane.id)
            )
        }

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

    @concurrent nonisolated private static func publishDerivedFilesystemEnvelopes(
        _ envelopes: [RuntimeEnvelope],
        to paneEventBus: EventBus<RuntimeEnvelope>
    ) async {
        let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceSurfaceCoordinator")
        for envelope in envelopes {
            let result = await paneEventBus.post(envelope)
            if result.droppedCount > 0 {
                logger.warning(
                    "Dropped derived filesystem context event for \(result.droppedCount, privacy: .public) subscriber(s); seq=\(envelope.seq, privacy: .public)"
                )
            }
        }
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
