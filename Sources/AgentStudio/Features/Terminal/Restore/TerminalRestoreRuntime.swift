import Foundation

@MainActor
struct TerminalRestoreRuntime {
    struct ZmxAttachDiagnostics: Sendable {
        let paneId: UUID
        let sessionId: String
        let zmxDir: String
        let socketPath: String
        let socketPathLength: Int
        let maxSocketPathLength: Int
        let zmxPath: String

        var socketPathHeadroom: Int {
            maxSocketPathLength - socketPathLength
        }
    }

    let sessionConfiguration: SessionConfiguration
    let liveSessionIdsProvider: @MainActor @Sendable (SessionConfiguration) async -> Set<String>

    init(
        sessionConfiguration: SessionConfiguration,
        liveSessionIdsProvider: @escaping @MainActor @Sendable (SessionConfiguration) async -> Set<String> = Self
            .discoverLiveSessionIds
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.liveSessionIdsProvider = liveSessionIdsProvider
    }

    func shouldStartHiddenRestore(
        policy: BackgroundRestorePolicy,
        hasExistingSession: Bool
    ) -> Bool {
        TerminalRestoreScheduler.shouldStartHiddenRestore(
            policy: policy,
            hasExistingSession: hasExistingSession
        )
    }

    func discoverLiveSessionIds() async -> Set<String> {
        await liveSessionIdsProvider(sessionConfiguration)
    }

    func shouldRestoreHiddenPane(
        _ pane: Pane,
        store: WorkspaceStore,
        liveSessionIds: Set<String>
    ) -> Bool {
        guard pane.provider == .zmx else { return true }
        guard let sessionId = zmxSessionId(for: pane, store: store) else { return false }
        return shouldStartHiddenRestore(
            policy: sessionConfiguration.backgroundRestorePolicy,
            hasExistingSession: liveSessionIds.contains(sessionId)
        )
    }

    func zmxAttachCommand(for pane: Pane, store: WorkspaceStore) -> String? {
        guard let sessionId = zmxSessionId(for: pane, store: store) else { return nil }
        guard let zmxPath = sessionConfiguration.zmxPath else { return nil }
        return ZmxBackend.buildAttachCommand(
            zmxPath: zmxPath,
            sessionId: sessionId,
            shell: SessionConfiguration.defaultShell()
        )
    }

    func zmxSessionId(for pane: Pane, store: WorkspaceStore) -> String? {
        guard pane.provider == .zmx else { return nil }

        if let parentPaneId = pane.parentPaneId {
            return ZmxBackend.drawerSessionId(
                parentPaneId: parentPaneId,
                drawerPaneId: pane.id
            )
        }

        if let worktreeId = pane.worktreeId,
            let worktree = store.worktree(worktreeId),
            let repo = store.repo(containing: worktreeId)
        {
            return ZmxBackend.sessionId(
                repoStableKey: repo.stableKey,
                worktreeStableKey: worktree.stableKey,
                paneId: pane.id
            )
        }

        if let workingDirectory = pane.metadata.facets.cwd {
            return ZmxBackend.floatingSessionId(
                workingDirectory: workingDirectory,
                paneId: pane.id
            )
        }

        return ZmxBackend.floatingSessionId(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            paneId: pane.id
        )
    }

    func zmxAttachDiagnostics(for pane: Pane, store: WorkspaceStore) -> ZmxAttachDiagnostics? {
        guard pane.provider == .zmx else { return nil }
        guard let sessionId = zmxSessionId(for: pane, store: store) else { return nil }
        guard let zmxPath = sessionConfiguration.zmxPath else { return nil }

        let socketPath = "\(sessionConfiguration.zmxDir)/\(sessionId)"
        return ZmxAttachDiagnostics(
            paneId: pane.id,
            sessionId: sessionId,
            zmxDir: sessionConfiguration.zmxDir,
            socketPath: socketPath,
            socketPathLength: socketPath.count,
            maxSocketPathLength: 104,
            zmxPath: zmxPath
        )
    }

    private static func discoverLiveSessionIds(
        sessionConfiguration: SessionConfiguration
    ) async -> Set<String> {
        guard let zmxPath = sessionConfiguration.zmxPath else { return [] }
        let backend = ZmxBackend(
            zmxPath: zmxPath,
            zmxDir: sessionConfiguration.zmxDir,
            retryPolicy: .standard
        )
        return Set(await backend.discoverOrphanSessions(excluding: []))
    }
}
