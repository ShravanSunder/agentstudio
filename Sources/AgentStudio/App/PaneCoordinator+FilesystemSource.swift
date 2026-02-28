import Foundation

protocol PaneCoordinatorFilesystemSourceManaging: AnyObject, Sendable {
    func register(worktreeId: UUID, rootPath: URL) async
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
        let desiredRootsByWorktreeId = workspaceWorktreeRootPathsById()
        let activityByWorktreeId = desiredRootsByWorktreeId.keys.reduce(into: [UUID: Bool]()) { result, worktreeId in
            result[worktreeId] = store.paneCount(for: worktreeId) > 0
        }
        let activePaneWorktreeId = activePaneWorktree()

        filesystemSyncTask?.cancel()
        filesystemSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let existingRootsByWorktreeId = self.filesystemRegisteredRootsByWorktreeId
            let existingWorktreeIds = Set(existingRootsByWorktreeId.keys)
            let desiredWorktreeIds = Set(desiredRootsByWorktreeId.keys)
            let removedWorktreeIds = existingWorktreeIds.subtracting(desiredWorktreeIds)

            for worktreeId in removedWorktreeIds.sorted(by: Self.sortWorktreeIds) {
                await self.filesystemSource.unregister(worktreeId: worktreeId)
            }

            let desiredRootEntries = desiredRootsByWorktreeId.sorted { lhs, rhs in
                Self.sortWorktreeIds(lhs.key, rhs.key)
            }
            for (worktreeId, desiredRootPath) in desiredRootEntries {
                let existingRootPath = existingRootsByWorktreeId[worktreeId]
                guard existingRootPath != desiredRootPath else { continue }
                if existingRootPath != nil {
                    await self.filesystemSource.unregister(worktreeId: worktreeId)
                }
                await self.filesystemSource.register(worktreeId: worktreeId, rootPath: desiredRootPath)
            }

            let activityEntries = activityByWorktreeId.sorted { lhs, rhs in
                Self.sortWorktreeIds(lhs.key, rhs.key)
            }
            for (worktreeId, isActiveInApp) in activityEntries {
                await self.filesystemSource.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp)
            }

            await self.filesystemSource.setActivePaneWorktree(worktreeId: activePaneWorktreeId)

            self.filesystemRegisteredRootsByWorktreeId = desiredRootsByWorktreeId
            let validWorktreeIds = Set(desiredRootsByWorktreeId.keys)
            self.workspaceGitStatusStore.prune(validWorktreeIds: validWorktreeIds)
            self.paneFilesystemProjectionStore.prune(
                validPaneIds: Set(self.store.panes.keys),
                validWorktreeIds: validWorktreeIds
            )
        }
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
