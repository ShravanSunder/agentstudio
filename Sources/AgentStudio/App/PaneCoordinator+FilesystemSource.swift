import Foundation

struct WorktreeFilesystemContext: Sendable, Equatable {
    let repoId: UUID
    let rootPath: URL
}

protocol PaneCoordinatorFilesystemSourceManaging: AnyObject, Sendable {
    func start() async
    func shutdown() async
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async
    func unregister(worktreeId: UUID) async
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async
    func setActivePaneWorktree(worktreeId: UUID?) async
}

extension FilesystemActor: PaneCoordinatorFilesystemSourceManaging {}

@MainActor
extension PaneCoordinator {
    func syncFilesystemRootsAndActivity() {
        scheduleFilesystemRootAndActivitySync()
    }

    func handleFilesystemEnvelopeIfNeeded(_ envelope: PaneEventEnvelope) -> Bool {
        guard case .filesystem = envelope.event else { return false }

        workspaceGitWorkingTreeStore.consume(envelope)
        paneFilesystemProjectionStore.consume(
            envelope,
            panesById: store.panes,
            worktreeRootsByWorktreeId: workspaceWorktreeContextsById().mapValues(\.rootPath)
        )
        return true
    }

    func setupFilesystemSourceSync() {
        store.repoWorktreesDidChangeHook = { [weak self] in
            self?.scheduleFilesystemRootAndActivitySync()
        }
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

        let desiredContextsByWorktreeId = workspaceWorktreeContextsById()
        let activityByWorktreeId = desiredContextsByWorktreeId.keys.reduce(into: [UUID: Bool]()) { result, worktreeId in
            result[worktreeId] = store.paneCount(for: worktreeId) > 0
        }
        let activePaneWorktreeId = activePaneWorktree()

        let existingContextsByWorktreeId = filesystemRegisteredContextsByWorktreeId
        let existingWorktreeIds = Set(existingContextsByWorktreeId.keys)
        let desiredWorktreeIds = Set(desiredContextsByWorktreeId.keys)
        let removedWorktreeIds = existingWorktreeIds.subtracting(desiredWorktreeIds)

        for worktreeId in removedWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            guard !Task.isCancelled else { return }
            await filesystemSource.unregister(worktreeId: worktreeId)
            guard !Task.isCancelled else { return }
            filesystemActivityByWorktreeId.removeValue(forKey: worktreeId)
            if filesystemLastActivePaneWorktreeId == worktreeId {
                filesystemLastActivePaneWorktreeId = nil
            }
        }

        let desiredContextEntries = desiredContextsByWorktreeId.sorted { lhs, rhs in
            Self.sortWorktreeIds(lhs.key, rhs.key)
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
            guard !Task.isCancelled else { return }
        }

        let activityEntries = activityByWorktreeId.sorted { lhs, rhs in
            Self.sortWorktreeIds(lhs.key, rhs.key)
        }
        for (worktreeId, isActiveInApp) in activityEntries {
            let previousActivity = filesystemActivityByWorktreeId[worktreeId]
            guard previousActivity != isActiveInApp else { continue }
            guard !Task.isCancelled else { return }
            await filesystemSource.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp)
            guard !Task.isCancelled else { return }
            filesystemActivityByWorktreeId[worktreeId] = isActiveInApp
        }

        if filesystemLastActivePaneWorktreeId != activePaneWorktreeId {
            guard !Task.isCancelled else { return }
            await filesystemSource.setActivePaneWorktree(worktreeId: activePaneWorktreeId)
            guard !Task.isCancelled else { return }
            filesystemLastActivePaneWorktreeId = activePaneWorktreeId
        }

        guard !Task.isCancelled else { return }
        filesystemRegisteredContextsByWorktreeId = desiredContextsByWorktreeId
        filesystemActivityByWorktreeId = activityByWorktreeId
        filesystemLastActivePaneWorktreeId = activePaneWorktreeId
        let validWorktreeIds = Set(desiredContextsByWorktreeId.keys)
        workspaceGitWorkingTreeStore.prune(validWorktreeIds: validWorktreeIds)
        paneFilesystemProjectionStore.prune(
            validPaneIds: Set(store.panes.keys),
            validWorktreeIds: validWorktreeIds
        )
    }

    private func activePaneWorktree() -> UUID? {
        guard let activePaneId = store.activeTab?.activePaneId else { return nil }
        return store.pane(activePaneId)?.worktreeId
    }

    private func workspaceWorktreeContextsById() -> [UUID: WorktreeFilesystemContext] {
        var contextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:]
        for repo in store.repos {
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
}
