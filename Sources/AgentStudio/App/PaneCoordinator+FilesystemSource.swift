import Foundation

protocol PaneCoordinatorFilesystemSourceManaging: AnyObject, Sendable {
    func start() async
    func shutdown() async
    func register(worktreeId: UUID, rootPath: URL) async
    func unregister(worktreeId: UUID) async
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async
    func setActivePaneWorktree(worktreeId: UUID?) async
}

extension FilesystemActor: PaneCoordinatorFilesystemSourceManaging {}

extension PaneCoordinatorFilesystemSourceManaging {
    func start() async {}
    func shutdown() async {}
}

@MainActor
extension PaneCoordinator {
    func syncFilesystemRootsAndActivity() {
        scheduleFilesystemRootAndActivitySync()
    }

    func handleFilesystemEnvelopeIfNeeded(_ envelope: PaneEventEnvelope) -> Bool {
        guard case .filesystem = envelope.event else { return false }

        workspaceGitStatusStore.consume(envelope)
        paneFilesystemProjectionStore.consume(
            envelope,
            panesById: store.panes,
            worktreeRootsByWorktreeId: workspaceWorktreeRootPathsById()
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

        let desiredRootsByWorktreeId = workspaceWorktreeRootPathsById()
        let activityByWorktreeId = desiredRootsByWorktreeId.keys.reduce(into: [UUID: Bool]()) { result, worktreeId in
            result[worktreeId] = store.paneCount(for: worktreeId) > 0
        }
        let activePaneWorktreeId = activePaneWorktree()

        let existingRootsByWorktreeId = filesystemRegisteredRootsByWorktreeId
        let existingWorktreeIds = Set(existingRootsByWorktreeId.keys)
        let desiredWorktreeIds = Set(desiredRootsByWorktreeId.keys)
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

        let desiredRootEntries = desiredRootsByWorktreeId.sorted { lhs, rhs in
            Self.sortWorktreeIds(lhs.key, rhs.key)
        }
        for (worktreeId, desiredRootPath) in desiredRootEntries {
            guard !Task.isCancelled else { return }
            let existingRootPath = existingRootsByWorktreeId[worktreeId]
            guard existingRootPath != desiredRootPath else { continue }
            if existingRootPath != nil {
                await filesystemSource.unregister(worktreeId: worktreeId)
                guard !Task.isCancelled else { return }
            }
            await filesystemSource.register(worktreeId: worktreeId, rootPath: desiredRootPath)
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
        filesystemRegisteredRootsByWorktreeId = desiredRootsByWorktreeId
        filesystemActivityByWorktreeId = activityByWorktreeId
        filesystemLastActivePaneWorktreeId = activePaneWorktreeId
        let validWorktreeIds = Set(desiredRootsByWorktreeId.keys)
        workspaceGitStatusStore.prune(validWorktreeIds: validWorktreeIds)
        paneFilesystemProjectionStore.prune(
            validPaneIds: Set(store.panes.keys),
            validWorktreeIds: validWorktreeIds
        )
    }

    private func activePaneWorktree() -> UUID? {
        guard let activePaneId = store.activeTab?.activePaneId else { return nil }
        return store.pane(activePaneId)?.worktreeId
    }

    private func workspaceWorktreeRootPathsById() -> [UUID: URL] {
        var rootsByWorktreeId: [UUID: URL] = [:]
        for repo in store.repos {
            for worktree in repo.worktrees {
                rootsByWorktreeId[worktree.id] = worktree.path.standardizedFileURL.resolvingSymlinksInPath()
            }
        }
        return rootsByWorktreeId
    }

    nonisolated private static func sortWorktreeIds(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
