import Foundation
import os

protocol PaneCoordinatorFilesystemSourceManaging: AnyObject, Sendable {
    func start() async
    func shutdown() async
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async
    func unregister(worktreeId: UUID) async
    func assertTopology(_ assertion: FilesystemTopologyAssertion) async
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async
    func setActivePaneWorktree(worktreeId: UUID?) async
}

extension FilesystemActor: PaneCoordinatorFilesystemSourceManaging {}

@MainActor
extension PaneCoordinator {
    func syncFilesystemRootsAndActivity() {
        scheduleFilesystemRootAndActivitySync()
    }

    func handleFilesystemEnvelopeIfNeeded(_ envelope: RuntimeEnvelope) -> Bool {
        guard Self.shouldProjectPaneFilesystemEnvelope(envelope) else {
            return false
        }

        let clock = ContinuousClock()
        let start = clock.now
        let worktreeRootsByWorktreeId =
            Self.requiresWorktreeRootLookup(envelope)
            ? workspaceWorktreeContextsById().mapValues(\.rootPath)
            : [:]
        let derivedEnvelopes = paneFilesystemProjectionStore.consume(
            envelope,
            panesById: store.paneAtom.panes,
            worktreeRootsByWorktreeId: worktreeRootsByWorktreeId
        )
        performanceTraceRecorder?.recordDuration(
            .coordinatorWrite,
            duration: start.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.coordinator.derived_envelope.count": .int(derivedEnvelopes.count),
                "agentstudio.performance.coordinator.pane.count": .int(store.paneAtom.panes.count),
                "agentstudio.performance.coordinator.worktree.count": .int(worktreeRootsByWorktreeId.count),
            ]
        )
        if !derivedEnvelopes.isEmpty {
            let taskId = UUID()
            let publishTask = Task { [weak self, paneEventBus] in
                await Self.publishDerivedFilesystemEnvelopes(
                    derivedEnvelopes,
                    to: paneEventBus
                )
                let _: Void = await MainActor.run {
                    self?.derivedFilesystemPublishTasks.removeValue(forKey: taskId)
                }
            }
            derivedFilesystemPublishTasks[taskId] = publishTask
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

    nonisolated private static func requiresWorktreeRootLookup(_ envelope: RuntimeEnvelope) -> Bool {
        guard case .worktree(let worktreeEnvelope) = envelope else { return false }
        if case .filesystem(.filesChanged) = worktreeEnvelope.event {
            return true
        }
        return false
    }

    func setupFilesystemSourceSync() {
        scheduleFilesystemRootAndActivitySync()
    }

    private func scheduleFilesystemRootAndActivitySync() {
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
        let start = clock.now
        let desiredContextsByWorktreeId = workspaceWorktreeContextsById()
        let activityByWorktreeId = desiredContextsByWorktreeId.keys.reduce(into: [UUID: Bool]()) { result, worktreeId in
            result[worktreeId] = store.paneAtom.paneCount(for: worktreeId) > 0
        }
        let activePaneWorktreeId = activePaneWorktree()
        let existingContextsByWorktreeId = filesystemRegisteredContextsByWorktreeId

        let existingWorktreeIds = Set(existingContextsByWorktreeId.keys)
        let desiredWorktreeIds = Set(desiredContextsByWorktreeId.keys)
        let removedWorktreeIds = existingWorktreeIds.subtracting(desiredWorktreeIds)
        var unregisteredCount = 0
        var registeredCount = 0
        var activityWriteCount = 0
        var activePaneWriteCount = 0

        for worktreeId in removedWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            guard !Task.isCancelled else { return }
            await filesystemSource.unregister(worktreeId: worktreeId)
            unregisteredCount += 1
            guard !Task.isCancelled else { return }
            filesystemActivityByWorktreeId.removeValue(forKey: worktreeId)
            if filesystemLastActivePaneWorktreeId == worktreeId {
                filesystemLastActivePaneWorktreeId = nil
            }
        }

        let desiredContextEntries = desiredContextsByWorktreeId.sorted { lhs, rhs in
            Self.sortWorktreeByPriority(lhs.key, rhs.key, activePaneWorktreeId: activePaneWorktreeId)
        }
        for (worktreeId, desiredContext) in desiredContextEntries {
            guard !Task.isCancelled else { return }
            let existingContext = existingContextsByWorktreeId[worktreeId]
            guard existingContext != desiredContext else { continue }
            if existingContext != nil {
                await filesystemSource.unregister(worktreeId: worktreeId)
                guard !Task.isCancelled else { return }
            }
            await filesystemSource.register(
                worktreeId: worktreeId,
                repoId: desiredContext.repoId,
                rootPath: desiredContext.rootPath
            )
            registeredCount += 1
            guard !Task.isCancelled else { return }
        }

        let activityEntries = activityByWorktreeId.sorted { lhs, rhs in
            Self.sortWorktreeByPriority(lhs.key, rhs.key, activePaneWorktreeId: activePaneWorktreeId)
        }
        for (worktreeId, isActiveInApp) in activityEntries {
            let previousActivity = filesystemActivityByWorktreeId[worktreeId]
            guard previousActivity != isActiveInApp else { continue }
            guard !Task.isCancelled else { return }
            await filesystemSource.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp)
            activityWriteCount += 1
            guard !Task.isCancelled else { return }
            filesystemActivityByWorktreeId[worktreeId] = isActiveInApp
        }

        if filesystemLastActivePaneWorktreeId != activePaneWorktreeId {
            guard !Task.isCancelled else { return }
            await filesystemSource.setActivePaneWorktree(worktreeId: activePaneWorktreeId)
            activePaneWriteCount = 1
            guard !Task.isCancelled else { return }
            filesystemLastActivePaneWorktreeId = activePaneWorktreeId
        }

        guard !Task.isCancelled else { return }
        filesystemTopologyAssertionGeneration &+= 1
        await filesystemSource.assertTopology(
            FilesystemTopologyAssertion(
                generation: filesystemTopologyAssertionGeneration,
                contextsByWorktreeId: desiredContextsByWorktreeId
            )
        )
        guard !Task.isCancelled else { return }
        filesystemRegisteredContextsByWorktreeId = desiredContextsByWorktreeId
        filesystemActivityByWorktreeId = activityByWorktreeId
        filesystemLastActivePaneWorktreeId = activePaneWorktreeId
        let validWorktreeIds = Set(desiredContextsByWorktreeId.keys)
        paneFilesystemProjectionStore.prune(
            validPaneIds: Set(store.paneAtom.panes.keys),
            validWorktreeIds: validWorktreeIds
        )
        performanceTraceRecorder?.recordDuration(
            .coordinatorWrite,
            duration: start.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.coordinator.registered.count": .int(registeredCount),
                "agentstudio.performance.coordinator.unregistered.count": .int(unregisteredCount),
                "agentstudio.performance.coordinator.activity_write.count": .int(activityWriteCount),
                "agentstudio.performance.coordinator.active_pane_write.count": .int(activePaneWriteCount),
                "agentstudio.performance.coordinator.worktree.count": .int(desiredContextsByWorktreeId.count),
            ]
        )
    }

    private func activePaneWorktree() -> UUID? {
        guard let activePaneId = store.tabLayoutAtom.activeTab?.activePaneId else { return nil }
        return store.paneAtom.pane(activePaneId)?.worktreeId
    }

    private func workspaceWorktreeContextsById() -> [UUID: WorktreeFilesystemContext] {
        var contextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:]
        for repo in store.repositoryTopologyAtom.repos where !store.repositoryTopologyAtom.isRepoUnavailable(repo.id) {
            for worktree in repo.worktrees {
                contextsByWorktreeId[worktree.id] = WorktreeFilesystemContext(
                    repoId: repo.id,
                    rootPath: worktree.path.standardizedFileURL.resolvingSymlinksInPath()
                )
            }
        }
        return contextsByWorktreeId
    }

    nonisolated private static func sortWorktreeIds(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    @concurrent nonisolated private static func publishDerivedFilesystemEnvelopes(
        _ envelopes: [RuntimeEnvelope],
        to paneEventBus: EventBus<RuntimeEnvelope>
    ) async {
        let logger = Logger(subsystem: "com.agentstudio", category: "PaneCoordinator")
        for envelope in envelopes {
            let result = await paneEventBus.post(envelope)
            if result.droppedCount > 0 {
                logger.warning(
                    "Dropped derived filesystem context event for \(result.droppedCount, privacy: .public) subscriber(s); seq=\(envelope.seq, privacy: .public)"
                )
            }
        }
    }

    nonisolated private static func sortWorktreeByPriority(
        _ lhs: UUID, _ rhs: UUID, activePaneWorktreeId: UUID?
    ) -> Bool {
        let lhsActive = lhs == activePaneWorktreeId
        let rhsActive = rhs == activePaneWorktreeId
        if lhsActive != rhsActive { return lhsActive }
        return lhs.uuidString < rhs.uuidString
    }
}
