import CoreGraphics
import Foundation

struct WorkspaceSQLiteStoreBackend {
    enum LoadResult {
        case loaded(WorkspaceSQLiteSnapshot)
        case uninitialized
        case unavailable(any Error)
    }

    enum BackendError: Error, Equatable {
        case incompleteWorkspaceSnapshot(UUID)
    }

    let coreRepository: WorkspaceCoreRepository
    let localBackend: WorkspaceLocalSQLiteStoreBackend

    init(
        coreRepository: WorkspaceCoreRepository,
        localBackend: WorkspaceLocalSQLiteStoreBackend
    ) {
        self.coreRepository = coreRepository
        self.localBackend = localBackend
    }

    init(
        coreRepository: WorkspaceCoreRepository,
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        legacyImportDecision:
            @escaping @Sendable (
                UUID,
                WorkspaceLocalSQLiteLegacyLane
            ) throws -> WorkspaceLocalSQLiteLegacyImportDecision = { _, _ in .allowImport
            }
    ) {
        self.coreRepository = coreRepository
        self.localBackend = WorkspaceLocalSQLiteStoreBackend(
            makeLocalRepository: makeLocalRepository,
            makeLocalRestoreRepository: makeLocalRestoreRepository,
            legacyImportDecision: legacyImportDecision
        )
    }

    func load(preferredWorkspaceId: UUID) throws -> WorkspaceSQLiteSnapshot? {
        switch loadResult(preferredWorkspaceId: preferredWorkspaceId) {
        case .loaded(let snapshot):
            return snapshot
        case .uninitialized:
            return nil
        case .unavailable(let error):
            throw error
        }
    }

    func loadResult(preferredWorkspaceId: UUID) -> LoadResult {
        do {
            return .loaded(try loadCompletedSnapshot(preferredWorkspaceId: preferredWorkspaceId))
        } catch is BackendUninitializedError {
            return .uninitialized
        } catch {
            return .unavailable(error)
        }
    }

    private func loadCompletedSnapshot(preferredWorkspaceId: UUID) throws -> WorkspaceSQLiteSnapshot {
        let workspaceId = try resolvedWorkspaceId(preferredWorkspaceId: preferredWorkspaceId)
        guard let workspaceId,
            let workspace = try coreRepository.fetchWorkspace(id: workspaceId)
        else {
            throw BackendUninitializedError()
        }
        let coreCompletedAt = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspace.id)
        guard let coreCompletedAt else {
            throw BackendError.incompleteWorkspaceSnapshot(workspace.id)
        }

        let topology = try coreRepository.fetchRepositoryTopology(workspaceId: workspace.id)
        let paneGraph = try coreRepository.fetchPaneGraph(workspaceId: workspace.id)
        let tabShells = try coreRepository.fetchTabShells(workspaceId: workspace.id)
        let tabGraph = try coreRepository.fetchTabGraph(workspaceId: workspace.id)
        let localRepository: WorkspaceLocalRepository?
        let localRepairDisposition: LocalSnapshotRepairDisposition
        do {
            localRepository = try localBackend.restoreRepository(for: workspace.id)
            localRepairDisposition = .repairAllowed
        } catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption {
            localRepository = nil
            localRepairDisposition = .repairAllowed
        } catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed {
            localRepository = nil
            localRepairDisposition = .repairBlockedByQuarantineFailure
        } catch {
            localRepository = nil
            localRepairDisposition = .repairAllowed
        }
        let cursorState: WorkspaceLocalRepository.CursorStateRecord
        let windowState: WorkspaceLocalRepository.WindowStateRecord?
        switch readLocalSnapshot(localRepository, matching: coreCompletedAt) {
        case .matched(let restoredCursorState, let restoredWindowState):
            cursorState = restoredCursorState
            windowState = restoredWindowState
        case .needsDefaultLocalState, .unavailable:
            cursorState = WorkspaceSQLiteStateBridge.defaultCursorState(tabShells: tabShells, tabGraph: tabGraph)
            windowState = nil
            if localRepairDisposition == .repairAllowed {
                repairLocalSnapshotIfPossible(
                    workspaceId: workspace.id,
                    cursorState: cursorState,
                    windowState: windowState,
                    completedAt: coreCompletedAt
                )
            }
        }

        let state = try WorkspaceSQLiteStateBridge.persistableState(
            from: .init(
                workspace: workspace,
                topology: topology,
                paneGraph: paneGraph,
                tabShells: tabShells,
                tabGraph: tabGraph,
                cursorState: cursorState,
                windowState: windowState
            )
        )
        return WorkspacePersistenceTransformer.sqliteSnapshot(from: state)
    }

    func readLocalSnapshot(
        _ localRepository: WorkspaceLocalRepository?,
        matching coreCompletedAt: Date
    ) -> WorkspaceLocalSnapshotRead {
        guard let localRepository else { return .needsDefaultLocalState }
        do {
            guard try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == coreCompletedAt else {
                return .needsDefaultLocalState
            }
            return .matched(
                cursorState: try localRepository.fetchCursorState(),
                windowState: try localRepository.fetchWindowState()
            )
        } catch {
            return .unavailable(error)
        }
    }

    func save(_ snapshot: WorkspaceSQLiteSnapshot) throws {
        try replaceWorkspaceSnapshotStaged(snapshot, updatesActiveSelection: true)
        let localRepository = try localBackend.repository(for: snapshot.id)
        try writeLocalSnapshotAndCommit(snapshot, localRepository: localRepository)
    }

    func save(_ snapshot: WorkspaceSQLiteSnapshot, localRepository: WorkspaceLocalRepository) throws {
        let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
        try replaceWorkspaceSnapshotStaged(snapshot, updatesActiveSelection: true)
        try writeLocalSnapshotAndCommit(snapshot, state: state, localRepository: localRepository)
    }

    private func writeLocalSnapshotAndCommit(
        _ snapshot: WorkspaceSQLiteSnapshot,
        localRepository: WorkspaceLocalRepository
    ) throws {
        let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
        try writeLocalSnapshotAndCommit(snapshot, state: state, localRepository: localRepository)
    }

    private func writeLocalSnapshotAndCommit(
        _ snapshot: WorkspaceSQLiteSnapshot,
        state: WorkspacePersistor.PersistableState,
        localRepository: WorkspaceLocalRepository
    ) throws {
        try localRepository.replaceWorkspaceSnapshotLocalState(
            cursorState: WorkspaceSQLiteStateBridge.cursorStateRecord(from: state),
            windowState: WorkspaceSQLiteStateBridge.windowStateRecord(from: state),
            completedAt: snapshot.updatedAt
        )
        try markWorkspaceSnapshotCommitted(workspaceId: snapshot.id, committedAt: snapshot.updatedAt)
    }

    func replaceWorkspaceSnapshotStaged(
        _ snapshot: WorkspaceSQLiteSnapshot,
        updatesActiveSelection: Bool
    ) throws {
        let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
        try coreRepository.replaceWorkspaceSnapshotStaged(
            workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: state),
            topology: WorkspaceSQLiteStateBridge.repositoryTopologyRecord(from: state),
            paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: state),
            tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: state),
            tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: state),
            stagedAt: snapshot.updatedAt,
            updatesActiveSelection: updatesActiveSelection
        )
    }

    func markWorkspaceSnapshotCommitted(workspaceId: UUID, committedAt: Date) throws {
        try coreRepository.markWorkspaceSQLiteSnapshotCommitted(workspaceId: workspaceId, committedAt: committedAt)
    }

    private func repairLocalSnapshotIfPossible(
        workspaceId: UUID,
        cursorState: WorkspaceLocalRepository.CursorStateRecord,
        windowState: WorkspaceLocalRepository.WindowStateRecord?,
        completedAt: Date
    ) {
        do {
            let localRepository = try localBackend.repository(for: workspaceId)
            try localRepository.replaceWorkspaceSnapshotLocalState(
                cursorState: cursorState,
                windowState: windowState,
                completedAt: completedAt
            )
        } catch {
            return
        }
    }

    func saveImportedLegacySnapshot(
        _ snapshot: WorkspaceSQLiteSnapshot,
        sourceStatePath: String
    ) throws {
        let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
        try replaceWorkspaceSnapshotStaged(snapshot, updatesActiveSelection: false)
        let localRepository = try localBackend.repository(for: snapshot.id)
        try localRepository.replaceWorkspaceSnapshotLocalState(
            cursorState: WorkspaceSQLiteStateBridge.cursorStateRecord(from: state),
            windowState: WorkspaceSQLiteStateBridge.windowStateRecord(from: state),
            completedAt: snapshot.updatedAt
        )
        try markWorkspaceSnapshotCommitted(workspaceId: snapshot.id, committedAt: snapshot.updatedAt)
        do {
            try coreRepository.markLegacyWorkspaceCoreImported(
                workspaceId: snapshot.id,
                sourceStatePath: sourceStatePath,
                importedAt: snapshot.updatedAt
            )
        } catch {
            try? coreRepository.markLegacyWorkspaceImportFailed(
                workspace: WorkspaceSQLiteStateBridge.workspaceRecord(
                    from: state
                ),
                sourceStatePath: sourceStatePath,
                error: "Legacy import bookkeeping failed after completed snapshot: \(String(describing: error))"
            )
        }
    }

    func markLegacyWorkspaceImportFailed(
        _ state: WorkspacePersistor.PersistableState,
        sourceStatePath: String,
        error: any Error
    ) throws {
        try coreRepository.markLegacyWorkspaceImportFailed(
            workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: state),
            sourceStatePath: sourceStatePath,
            error: String(describing: error)
        )
    }

    func hasCompletedSnapshot(workspaceId: UUID) throws -> Bool {
        guard let coreCompletedAt = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId)
        else {
            return false
        }
        let localRepository: WorkspaceLocalRepository
        do {
            localRepository = try localBackend.restoreRepository(for: workspaceId)
        } catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption {
            return false
        } catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed {
            return false
        }
        return try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == coreCompletedAt
    }

    func markLegacyWorkspaceArchived(workspaceId: UUID, archivedAt: Date) throws {
        try coreRepository.markLegacyWorkspaceArchived(workspaceId: workspaceId, archivedAt: archivedAt)
    }

    func markLegacyWorkspaceCompanionImportsCompleted(workspaceId: UUID, importedAt: Date) throws {
        try coreRepository.markLegacyWorkspaceCompanionImportsCompleted(
            workspaceId: workspaceId,
            importedAt: importedAt
        )
    }

    func selectActiveWorkspace(_ workspaceId: UUID, updatedAt: Date) throws {
        try coreRepository.selectActiveWorkspace(workspaceId, updatedAt: updatedAt)
    }

    func resolvedWorkspaceId(preferredWorkspaceId: UUID) throws -> UUID? {
        do {
            if let activeWorkspaceId = try coreRepository.fetchActiveWorkspaceId() {
                if try coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: activeWorkspaceId) {
                    return activeWorkspaceId
                }
            }
            if let preferredWorkspaceId = try selectPreferredWorkspaceIfAvailable(preferredWorkspaceId) {
                return preferredWorkspaceId
            }
        } catch let error as WorkspaceCoreRepositoryError {
            switch error {
            case .activeWorkspaceSelectionDangling, .malformedWorkspaceId:
                if let preferredWorkspaceId = try selectPreferredWorkspaceIfAvailable(preferredWorkspaceId) {
                    return preferredWorkspaceId
                }
            default:
                throw error
            }
        }
        return try coreRepository.repairActiveCompletedWorkspaceSelection(updatedAt: Date())
    }

    private func selectPreferredWorkspaceIfAvailable(_ preferredWorkspaceId: UUID) throws -> UUID? {
        guard try coreRepository.fetchWorkspace(id: preferredWorkspaceId) != nil,
            try coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: preferredWorkspaceId)
        else {
            return nil
        }
        try coreRepository.selectActiveWorkspace(preferredWorkspaceId, updatedAt: Date())
        return preferredWorkspaceId
    }
}

enum WorkspaceLocalSnapshotRead {
    case matched(
        cursorState: WorkspaceLocalRepository.CursorStateRecord,
        windowState: WorkspaceLocalRepository.WindowStateRecord?
    )
    case needsDefaultLocalState
    case unavailable(any Error)
}

enum LocalSnapshotRepairDisposition {
    case repairAllowed
    case repairBlockedByQuarantineFailure
}

struct BackendUninitializedError: Error {}

enum WorkspaceLocalSQLiteLegacyLane: Sendable {
    case local
    case cache
}

enum WorkspaceLocalSQLiteLegacyImportDecision: Sendable {
    case allowImport
    case blockReplayAllowArchive
    case blockReplayBlockArchive

    var allowsLegacyImport: Bool {
        switch self {
        case .allowImport:
            return true
        case .blockReplayAllowArchive, .blockReplayBlockArchive:
            return false
        }
    }

    var canArchiveLegacyFile: Bool {
        switch self {
        case .blockReplayAllowArchive:
            return true
        case .allowImport, .blockReplayBlockArchive:
            return false
        }
    }
}

struct WorkspaceLocalSQLiteStoreBackend: Sendable {
    private let makeLocalRepository: @Sendable (UUID) throws -> WorkspaceLocalRepository
    private let makeLocalRestoreRepository: @Sendable (UUID) throws -> WorkspaceLocalRepository
    private let makeLegacyImportDecision:
        @Sendable (
            UUID,
            WorkspaceLocalSQLiteLegacyLane
        ) throws -> WorkspaceLocalSQLiteLegacyImportDecision

    init(
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        legacyImportDecision:
            @escaping @Sendable (
                UUID,
                WorkspaceLocalSQLiteLegacyLane
            ) throws -> WorkspaceLocalSQLiteLegacyImportDecision = { _, _ in .allowImport
            }
    ) {
        self.makeLocalRepository = makeLocalRepository
        if let makeLocalRestoreRepository {
            self.makeLocalRestoreRepository = makeLocalRestoreRepository
        } else {
            self.makeLocalRestoreRepository = { workspaceId in
                try makeLocalRepository(workspaceId)
            }
        }
        self.makeLegacyImportDecision = legacyImportDecision
    }

    func repository(for workspaceId: UUID) throws -> WorkspaceLocalRepository {
        try makeLocalRepository(workspaceId)
    }

    func restoreRepository(for workspaceId: UUID) throws -> WorkspaceLocalRepository {
        try makeLocalRestoreRepository(workspaceId)
    }

    func legacyImportDecision(
        for workspaceId: UUID,
        lane: WorkspaceLocalSQLiteLegacyLane
    ) throws -> WorkspaceLocalSQLiteLegacyImportDecision {
        try makeLegacyImportDecision(workspaceId, lane)
    }
}

enum WorkspaceLocalSQLiteStoreBackendError: Error {
    case recoveredFromCorruption(UUID)
    case quarantineFailed(UUID)
}

enum WorkspaceSQLiteStateBridge {
    struct Snapshot {
        var workspace: WorkspaceCoreRepository.WorkspaceRecord
        var topology: WorkspaceCoreRepository.RepositoryTopologyRecord
        var paneGraph: WorkspaceCoreRepository.PaneGraphRecord
        var tabShells: [WorkspaceCoreRepository.TabShellRecord]
        var tabGraph: WorkspaceCoreRepository.TabGraphRecord
        var cursorState: WorkspaceLocalRepository.CursorStateRecord
        var windowState: WorkspaceLocalRepository.WindowStateRecord?
    }

    static func workspaceRecord(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceCoreRepository.WorkspaceRecord {
        .init(
            id: state.id,
            name: state.name,
            createdAt: state.createdAt,
            updatedAt: state.updatedAt
        )
    }

    static func repositoryTopologyRecord(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceCoreRepository.RepositoryTopologyRecord {
        let worktreesByRepoId = Dictionary(grouping: state.worktrees, by: \.repoId)
        let repos = state.repos.map { repo in
            WorkspaceCoreRepository.RepoRecord(
                id: repo.id,
                name: repo.name,
                repoPath: repo.repoPath,
                createdAt: repo.createdAt,
                worktrees: (worktreesByRepoId[repo.id] ?? []).map { worktree in
                    WorkspaceCoreRepository.WorktreeRecord(
                        id: worktree.id,
                        repoId: worktree.repoId,
                        name: worktree.name,
                        path: worktree.path,
                        isMainWorktree: worktree.isMainWorktree
                    )
                }
            )
        }
        return .init(
            watchedPaths: state.watchedPaths.map { watchedPath in
                WorkspaceCoreRepository.WatchedPathRecord(
                    id: watchedPath.id,
                    path: watchedPath.path,
                    addedAt: watchedPath.addedAt
                )
            },
            repos: repos,
            unavailableRepoIds: state.unavailableRepoIds
        )
    }

    static func paneGraphRecord(
        from state: WorkspacePersistor.PersistableState
    ) throws -> WorkspaceCoreRepository.PaneGraphRecord {
        .init(panes: try state.panes.map { try paneRecord(from: $0, updatedAt: state.updatedAt) })
    }

    static func tabShellRecords(
        from state: WorkspacePersistor.PersistableState
    ) -> [WorkspaceCoreRepository.TabShellRecord] {
        state.tabs.map { tab in
            .init(id: tab.id, name: tab.name)
        }
    }

    static func tabGraphRecord(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceCoreRepository.TabGraphRecord {
        .init(
            tabs: state.tabs.map { tab in
                .init(
                    tabId: tab.id,
                    allPaneIds: tab.allPaneIds,
                    arrangements: tab.arrangements.map(tabArrangementGraphRecord)
                )
            }
        )
    }

    static func windowStateRecord(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceLocalRepository.WindowStateRecord {
        .init(
            sidebarWidth: Double(state.sidebarWidth),
            windowFrame: state.windowFrame
        )
    }

    static func cursorStateRecord(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceLocalRepository.CursorStateRecord {
        let drawers = state.panes.compactMap(\.drawer)
        let arrangementCursorPairs = state.tabs.map { tab in
            (tab.id, Optional(tab.activeArrangementId))
        }
        let activePanePairs = state.tabs.flatMap { tab in
            tab.arrangements.map { arrangement in
                (arrangement.id, arrangement.activePaneId)
            }
        }
        let activeChildPairs = state.tabs.flatMap { tab in
            tab.arrangements.flatMap { arrangement in
                arrangement.drawerViews.map { drawerId, drawerView in
                    (
                        WorkspaceLocalRepository.ArrangementDrawerCursorKey(
                            arrangementId: arrangement.id,
                            drawerId: drawerId
                        ),
                        drawerView.activeChildId
                    )
                }
            }
        }
        return .init(
            activeTabId: state.activeTabId,
            activeArrangementIdsByTabId: Dictionary(uniqueKeysWithValues: arrangementCursorPairs),
            activePaneIdsByArrangementId: Dictionary(uniqueKeysWithValues: activePanePairs),
            drawerExpansionByDrawerId: Dictionary(uniqueKeysWithValues: drawers.map { ($0.drawerId, $0.isExpanded) }),
            activeChildIdsByArrangementDrawer: Dictionary(uniqueKeysWithValues: activeChildPairs)
        )
    }

    static func defaultCursorState(
        tabShells: [WorkspaceCoreRepository.TabShellRecord],
        tabGraph: WorkspaceCoreRepository.TabGraphRecord
    ) -> WorkspaceLocalRepository.CursorStateRecord {
        .init(
            activeTabId: tabShells.first?.id ?? tabGraph.tabs.first?.tabId,
            activeArrangementIdsByTabId: [:],
            activePaneIdsByArrangementId: [:],
            drawerExpansionByDrawerId: [:],
            activeChildIdsByArrangementDrawer: [:]
        )
    }

    static func persistableState(
        from snapshot: Snapshot
    ) throws -> WorkspacePersistor.PersistableState {
        let tabShellsById = Dictionary(uniqueKeysWithValues: snapshot.tabShells.map { ($0.id, $0) })
        return .init(
            id: snapshot.workspace.id,
            name: snapshot.workspace.name,
            repos: snapshot.topology.repos.map(canonicalRepo),
            worktrees: snapshot.topology.repos.flatMap { $0.worktrees.map(canonicalWorktree) },
            unavailableRepoIds: snapshot.topology.unavailableRepoIds,
            panes: try snapshot.paneGraph.panes.map { try pane(from: $0, cursorState: snapshot.cursorState) },
            tabs: snapshot.tabGraph.tabs.map { tabState in
                tab(
                    from: tabState,
                    shell: tabShellsById[tabState.tabId],
                    cursorState: snapshot.cursorState
                )
            },
            activeTabId: snapshot.cursorState.activeTabId,
            sidebarWidth: CGFloat(snapshot.windowState?.sidebarWidth ?? 250),
            windowFrame: snapshot.windowState?.windowFrame,
            watchedPaths: snapshot.topology.watchedPaths.map(watchedPath),
            createdAt: snapshot.workspace.createdAt,
            updatedAt: snapshot.workspace.updatedAt
        )
    }

    private static func paneRecord(
        from pane: Pane,
        updatedAt: Date
    ) throws -> WorkspaceCoreRepository.PaneRecord {
        .init(
            id: pane.id,
            content: try paneContentRecord(from: pane.content),
            metadata: paneMetadataRecord(from: pane.metadata),
            residency: paneResidencyRecord(from: pane.residency),
            placement: panePlacementRecord(from: pane.kind),
            drawer: pane.drawer.map(drawerRecord),
            updatedAt: updatedAt
        )
    }

    private static func paneContentRecord(
        from content: PaneContent
    ) throws -> WorkspaceCoreRepository.PaneContentRecord {
        switch content {
        case .terminal(let state):
            return .terminal(provider: state.provider, lifetime: state.lifetime)
        case .webview(let state):
            return .webview(url: state.url, title: state.title, showNavigation: state.showNavigation)
        case .codeViewer(let state):
            return .codeViewer(filePath: state.filePath, scrollToLine: state.scrollToLine)
        case .bridgePanel:
            return try payloadContentRecord(content, contentType: .diff, payloadKind: "bridgePanel")
        case .unsupported(let unsupported):
            return try payloadContentRecord(
                content,
                contentType: .plugin(unsupported.type),
                payloadKind: unsupported.type
            )
        }
    }

    private static func paneMetadataRecord(
        from metadata: PaneMetadata
    ) -> WorkspaceCoreRepository.PaneMetadataRecord {
        .init(
            source: paneSourceRecord(from: metadata.source),
            executionBackend: metadata.executionBackend,
            createdAt: metadata.createdAt,
            title: metadata.title,
            note: metadata.note,
            checkoutRef: metadata.checkoutRef,
            durableFacets: .init(
                repoId: metadata.facets.repoId,
                worktreeId: metadata.facets.worktreeId,
                cwd: metadata.facets.cwd,
                tags: metadata.facets.tags
            )
        )
    }

    private static func paneSourceRecord(
        from source: PaneMetadata.PaneMetadataSource
    ) -> WorkspaceCoreRepository.PaneSourceRecord {
        switch source {
        case .worktree(let worktreeId, let repoId, let launchDirectory):
            .worktree(repoId: repoId, worktreeId: worktreeId, launchDirectory: launchDirectory)
        case .floating(let launchDirectory, _):
            .floating(launchDirectory: launchDirectory)
        }
    }

    private static func paneResidencyRecord(
        from residency: SessionResidency
    ) -> WorkspaceCoreRepository.PaneResidencyRecord {
        switch residency {
        case .active:
            .active
        case .backgrounded:
            .backgrounded
        case .pendingUndo(let expiresAt):
            .pendingUndo(expiresAt: expiresAt)
        case .orphaned(let reason):
            switch reason {
            case .worktreeNotFound(let path):
                .orphaned(worktreePath: path)
            }
        }
    }

    private static func panePlacementRecord(
        from kind: PaneKind
    ) -> WorkspaceCoreRepository.PanePlacementRecord {
        switch kind {
        case .layout:
            .layout
        case .drawerChild(let parentPaneId):
            .drawerChild(parentPaneId: parentPaneId)
        }
    }

    private static func drawerRecord(from drawer: Drawer) -> WorkspaceCoreRepository.DrawerRecord {
        .init(
            drawerId: drawer.drawerId,
            parentPaneId: drawer.parentPaneId,
            childPaneIds: drawer.paneIds
        )
    }

    private static func tabArrangementGraphRecord(
        from arrangement: PaneArrangement
    ) -> WorkspaceCoreRepository.TabArrangementGraphRecord {
        .init(
            id: arrangement.id,
            name: arrangement.name,
            isDefault: arrangement.isDefault,
            layout: arrangement.layout,
            minimizedPaneIds: arrangement.minimizedPaneIds,
            showsMinimizedPanes: arrangement.showsMinimizedPanes,
            drawerViews: arrangement.drawerViews.mapValues { drawerView in
                .init(
                    layout: drawerView.layout,
                    minimizedPaneIds: drawerView.minimizedPaneIds
                )
            }
        )
    }

    private static func payloadContentRecord(
        _ content: PaneContent,
        contentType: PaneContentType,
        payloadKind: String
    ) throws -> WorkspaceCoreRepository.PaneContentRecord {
        let data = try JSONEncoder().encode(content)
        guard let payloadJSON = String(data: data, encoding: .utf8) else {
            throw WorkspaceSQLiteStateBridgeError.invalidPayloadJSON
        }
        return .payload(contentType: contentType, payloadKind: payloadKind, payloadJSON: payloadJSON)
    }

    private static func pane(
        from record: WorkspaceCoreRepository.PaneRecord,
        cursorState: WorkspaceLocalRepository.CursorStateRecord
    ) throws -> Pane {
        Pane(
            id: record.id,
            content: try paneContent(from: record.content),
            metadata: paneMetadata(from: record.metadata, paneId: record.id, contentType: record.content.contentType),
            residency: paneResidency(from: record.residency),
            kind: paneKind(from: record, cursorState: cursorState)
        )
    }

    private static func paneContent(
        from record: WorkspaceCoreRepository.PaneContentRecord
    ) throws -> PaneContent {
        switch record {
        case .terminal(let provider, let lifetime):
            .terminal(.init(provider: provider, lifetime: lifetime))
        case .webview(let url, let title, let showNavigation):
            .webview(.init(url: url, title: title, showNavigation: showNavigation))
        case .codeViewer(let filePath, let scrollToLine):
            .codeViewer(.init(filePath: filePath, scrollToLine: scrollToLine))
        case .payload(_, _, let payloadJSON):
            try JSONDecoder().decode(PaneContent.self, from: Data(payloadJSON.utf8))
        }
    }

    private static func paneMetadata(
        from record: WorkspaceCoreRepository.PaneMetadataRecord,
        paneId: UUID,
        contentType: PaneContentType
    ) -> PaneMetadata {
        .init(
            paneId: PaneId(uuid: paneId),
            contentType: contentType,
            source: paneMetadataSource(from: record.source),
            executionBackend: record.executionBackend,
            createdAt: record.createdAt,
            title: record.title,
            facets: .init(
                repoId: record.durableFacets.repoId,
                worktreeId: record.durableFacets.worktreeId,
                cwd: record.durableFacets.cwd,
                tags: record.durableFacets.tags
            ),
            checkoutRef: record.checkoutRef,
            note: record.note
        )
    }

    private static func paneMetadataSource(
        from record: WorkspaceCoreRepository.PaneSourceRecord
    ) -> PaneMetadata.PaneMetadataSource {
        switch record {
        case .worktree(let repoId, let worktreeId, let launchDirectory):
            .worktree(worktreeId: worktreeId, repoId: repoId, launchDirectory: launchDirectory)
        case .floating(let launchDirectory):
            .floating(launchDirectory: launchDirectory, title: nil)
        }
    }

    private static func paneResidency(
        from record: WorkspaceCoreRepository.PaneResidencyRecord
    ) -> SessionResidency {
        switch record {
        case .active:
            .active
        case .backgrounded:
            .backgrounded
        case .pendingUndo(let expiresAt):
            .pendingUndo(expiresAt: expiresAt)
        case .orphaned(let worktreePath):
            .orphaned(reason: .worktreeNotFound(path: worktreePath))
        }
    }

    private static func paneKind(
        from record: WorkspaceCoreRepository.PaneRecord,
        cursorState: WorkspaceLocalRepository.CursorStateRecord
    ) -> PaneKind {
        switch record.placement {
        case .layout:
            let drawer =
                record.drawer.map { drawer in
                    Drawer(
                        drawerId: drawer.drawerId,
                        parentPaneId: drawer.parentPaneId,
                        paneIds: drawer.childPaneIds,
                        isExpanded: cursorState.drawerExpansionByDrawerId[drawer.drawerId] ?? false
                    )
                } ?? Drawer(parentPaneId: record.id)
            return .layout(drawer: drawer)
        case .drawerChild(let parentPaneId):
            return .drawerChild(parentPaneId: parentPaneId)
        }
    }

    private static func tab(
        from state: WorkspaceCoreRepository.TabGraphStateRecord,
        shell: WorkspaceCoreRepository.TabShellRecord?,
        cursorState: WorkspaceLocalRepository.CursorStateRecord
    ) -> Tab {
        let arrangements = state.arrangements.map { arrangement in
            paneArrangement(from: arrangement, cursorState: cursorState)
        }
        let rememberedActiveArrangementId = flattenedCursor(cursorState.activeArrangementIdsByTabId[state.tabId])
        let activeArrangementId =
            rememberedActiveArrangementId
            ?? arrangements.first(where: \.isDefault)?.id
            ?? arrangements[0].id
        return .init(
            id: state.tabId,
            name: shell?.name ?? "Tab",
            allPaneIds: state.allPaneIds,
            arrangements: arrangements,
            activeArrangementId: activeArrangementId,
            zoomedPaneId: nil
        )
    }

    private static func paneArrangement(
        from record: WorkspaceCoreRepository.TabArrangementGraphRecord,
        cursorState: WorkspaceLocalRepository.CursorStateRecord
    ) -> PaneArrangement {
        .init(
            id: record.id,
            name: record.name,
            isDefault: record.isDefault,
            layout: record.layout,
            minimizedPaneIds: record.minimizedPaneIds,
            showsMinimizedPanes: record.showsMinimizedPanes,
            activePaneId: flattenedCursor(cursorState.activePaneIdsByArrangementId[record.id]),
            drawerViews: record.drawerViews.map { drawerId, drawerView in
                let key = WorkspaceLocalRepository.ArrangementDrawerCursorKey(
                    arrangementId: record.id,
                    drawerId: drawerId
                )
                return (
                    drawerId,
                    DrawerView(
                        layout: drawerView.layout,
                        activeChildId: flattenedCursor(cursorState.activeChildIdsByArrangementDrawer[key]),
                        minimizedPaneIds: drawerView.minimizedPaneIds
                    )
                )
            }.reduce(into: [:]) { partialResult, pair in
                partialResult[pair.0] = pair.1
            }
        )
    }

    private static func flattenedCursor(_ value: UUID??) -> UUID? {
        guard let value else { return nil }
        return value
    }

    private static func canonicalRepo(from record: WorkspaceCoreRepository.RepoRecord) -> CanonicalRepo {
        .init(
            id: record.id,
            name: record.name,
            repoPath: record.repoPath,
            createdAt: record.createdAt
        )
    }

    private static func canonicalWorktree(from record: WorkspaceCoreRepository.WorktreeRecord) -> CanonicalWorktree {
        .init(
            id: record.id,
            repoId: record.repoId,
            name: record.name,
            path: record.path,
            isMainWorktree: record.isMainWorktree
        )
    }

    private static func watchedPath(from record: WorkspaceCoreRepository.WatchedPathRecord) -> WatchedPath {
        .init(id: record.id, path: record.path, addedAt: record.addedAt)
    }
}

enum WorkspaceSQLiteStateBridgeError: Error {
    case invalidPayloadJSON
}
