import CoreGraphics
import Foundation

struct WorkspaceSQLiteStoreBackend {
    enum CoreDatabaseStartupProvenance: Sendable {
        case createdDuringCurrentStartup
        case preexisting
    }

    enum LoadResult {
        case loaded(WorkspaceSQLiteSnapshot)
        case uninitialized
        case unavailable(any Error)
    }

    enum BackendError: Error, Equatable, Sendable {
        case preexistingDatabaseHasNoWorkspaceRows
        case missingActiveWorkspaceSelection
    }

    let coreRepository: WorkspaceCoreRepository
    let localBackend: WorkspaceLocalSQLiteStoreBackend
    let coreDatabaseStartupProvenance: CoreDatabaseStartupProvenance

    init(
        coreRepository: WorkspaceCoreRepository,
        localBackend: WorkspaceLocalSQLiteStoreBackend,
        coreDatabaseStartupProvenance: CoreDatabaseStartupProvenance = .preexisting
    ) {
        self.coreRepository = coreRepository
        self.localBackend = localBackend
        self.coreDatabaseStartupProvenance = coreDatabaseStartupProvenance
    }

    init(
        coreRepository: WorkspaceCoreRepository,
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        coreDatabaseStartupProvenance: CoreDatabaseStartupProvenance = .preexisting
    ) {
        self.coreRepository = coreRepository
        self.coreDatabaseStartupProvenance = coreDatabaseStartupProvenance
        self.localBackend = WorkspaceLocalSQLiteStoreBackend(
            makeLocalRepository: makeLocalRepository,
            makeLocalRestoreRepository: makeLocalRestoreRepository
        )
    }

    func load() throws -> WorkspaceSQLiteSnapshot? {
        switch loadResult() {
        case .loaded(let snapshot):
            return snapshot
        case .uninitialized:
            return nil
        case .unavailable(let error):
            throw error
        }
    }

    func loadResult() -> LoadResult {
        do {
            return .loaded(try loadCompletedSnapshot())
        } catch is BackendUninitializedError {
            return .uninitialized
        } catch {
            return .unavailable(error)
        }
    }

    private func loadCompletedSnapshot() throws -> WorkspaceSQLiteSnapshot {
        let authoritativeSnapshot = try strictlySelectedAuthoritativeSnapshot()
        let localRepository = try? localBackend.restoreRepository(for: authoritativeSnapshot.workspace.id)
        let localCursorState = localRepository.flatMap { repository in
            try? repository.fetchCursorState()
        }
        let localWindowState = localRepository.flatMap { repository in
            try? repository.fetchWindowState()
        }
        return try WorkspaceSQLiteStateBridge.workspaceSnapshot(
            from: .init(
                workspace: authoritativeSnapshot.workspace,
                paneGraph: authoritativeSnapshot.paneGraph,
                tabShells: authoritativeSnapshot.tabShells,
                tabGraph: authoritativeSnapshot.tabGraph,
                cursorState: WorkspaceSQLiteStateBridge.localCursorStateForComposition(
                    persisted: localCursorState,
                    paneGraph: authoritativeSnapshot.paneGraph,
                    tabGraph: authoritativeSnapshot.tabGraph
                ),
                windowState: localWindowState
            )
        )
    }

    func save(_ bundle: WorkspaceSQLiteSaveBundle) throws {
        try replaceWorkspaceSnapshot(bundle, updatesActiveSelection: true)
        let localRepository = try localBackend.repository(for: bundle.id)
        try writeLocalSnapshot(
            bundle.workspace,
            localRepository: localRepository
        )
    }

    func save(_ bundle: WorkspaceSQLiteSaveBundle, localRepository: WorkspaceLocalRepository) throws {
        try replaceWorkspaceSnapshot(bundle, updatesActiveSelection: true)
        try writeLocalSnapshot(bundle.workspace, localRepository: localRepository)
    }

    func writeLocalSnapshot(
        _ snapshot: WorkspaceSQLiteSnapshot,
        localRepository: WorkspaceLocalRepository
    ) throws {
        try localRepository.replaceWorkspaceSnapshotLocalState(
            cursorState: WorkspaceSQLiteStateBridge.cursorStateRecord(from: snapshot),
            windowState: WorkspaceSQLiteStateBridge.windowStateRecord(from: snapshot),
            completedAt: snapshot.updatedAt
        )
    }

    func replaceWorkspaceSnapshot(
        _ bundle: WorkspaceSQLiteSaveBundle,
        updatesActiveSelection: Bool
    ) throws {
        let snapshot = bundle.workspace
        try coreRepository.replaceWorkspaceSnapshot(
            workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: snapshot),
            paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: snapshot),
            tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: snapshot),
            tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: snapshot),
            updatesActiveSelection: updatesActiveSelection
        )
    }

    func fetchRepositoryTopologySnapshot() throws -> RepositoryTopologySQLiteSnapshot {
        try WorkspaceSQLiteStateBridge.repositoryTopologySnapshot(
            topology: coreRepository.fetchRepositoryTopology(),
            updatedAt: Date()
        )
    }

    func replaceRepositoryTopologySnapshot(_ snapshot: RepositoryTopologySQLiteSnapshot) throws {
        try coreRepository.replaceRepositoryTopology(
            WorkspaceSQLiteStateBridge.repositoryTopologyRecord(from: snapshot)
        )
    }

    func selectActiveWorkspace(_ workspaceId: UUID, updatedAt: Date) throws {
        try coreRepository.selectActiveWorkspace(workspaceId, updatedAt: updatedAt)
    }

    func strictlySelectedAuthoritativeSnapshot() throws -> WorkspaceCoreRepository.AuthoritativeSnapshot {
        switch try coreRepository.fetchAuthoritativeSnapshot() {
        case .noWorkspaces:
            switch coreDatabaseStartupProvenance {
            case .createdDuringCurrentStartup:
                throw BackendUninitializedError()
            case .preexisting:
                throw BackendError.preexistingDatabaseHasNoWorkspaceRows
            }
        case .missingActiveSelection:
            throw BackendError.missingActiveWorkspaceSelection
        case .loaded(let snapshot):
            return snapshot
        }
    }
}

struct BackendUninitializedError: Error {}

struct WorkspaceLocalSQLiteStoreBackend: Sendable {
    private let makeLocalRepository: @Sendable (UUID) throws -> WorkspaceLocalRepository
    private let makeLocalRestoreRepository: @Sendable (UUID) throws -> WorkspaceLocalRepository
    init(
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil
    ) {
        self.makeLocalRepository = makeLocalRepository
        if let makeLocalRestoreRepository {
            self.makeLocalRestoreRepository = makeLocalRestoreRepository
        } else {
            self.makeLocalRestoreRepository = { workspaceId in
                try makeLocalRepository(workspaceId)
            }
        }
    }

    func repository(for workspaceId: UUID) throws -> WorkspaceLocalRepository {
        try makeLocalRepository(workspaceId)
    }

    func restoreRepository(for workspaceId: UUID) throws -> WorkspaceLocalRepository {
        try makeLocalRestoreRepository(workspaceId)
    }

}

enum WorkspaceLocalSQLiteStoreBackendError: Error {
    case recoveredFromCorruption(UUID, quarantinedFilename: String? = nil)
    case quarantineFailed(UUID, quarantinedFilename: String? = nil)
}

enum WorkspaceSQLiteStateBridge {
    struct Snapshot {
        var workspace: WorkspaceCoreRepository.WorkspaceRecord
        var paneGraph: WorkspaceCoreRepository.PaneGraphRecord
        var tabShells: [WorkspaceCoreRepository.TabShellRecord]
        var tabGraph: WorkspaceCoreRepository.TabGraphRecord
        var cursorState: WorkspaceLocalRepository.CursorStateRecord
        var windowState: WorkspaceLocalRepository.WindowStateRecord?
    }

    static func workspaceRecord(
        from state: WorkspaceSQLiteSnapshot
    ) -> WorkspaceCoreRepository.WorkspaceRecord {
        .init(
            id: state.id,
            name: state.name,
            createdAt: state.createdAt,
            updatedAt: state.updatedAt
        )
    }

    static func repositoryTopologyRecord(
        from snapshot: RepositoryTopologySQLiteSnapshot
    ) -> WorkspaceCoreRepository.RepositoryTopologyRecord {
        let worktreesByRepoId = Dictionary(grouping: snapshot.worktrees, by: \.repoId)
        return .init(
            watchedPaths: snapshot.watchedPaths.map { watchedPath in
                .init(
                    id: watchedPath.id,
                    path: watchedPath.path,
                    addedAt: watchedPath.addedAt
                )
            },
            repos: snapshot.repos.map { repo in
                .init(
                    id: repo.id,
                    name: repo.name,
                    repoPath: repo.repoPath,
                    createdAt: repo.createdAt,
                    isFavorite: repo.isFavorite,
                    note: repo.note,
                    worktrees: (worktreesByRepoId[repo.id] ?? []).map { worktree in
                        .init(
                            id: worktree.id,
                            repoId: worktree.repoId,
                            name: worktree.name,
                            path: worktree.path,
                            isMainWorktree: worktree.isMainWorktree,
                            note: worktree.note
                        )
                    },
                    tags: repo.tags
                )
            },
            unavailableRepoIds: snapshot.unavailableRepoIds
        )
    }

    static func paneGraphRecord(
        from state: WorkspaceSQLiteSnapshot
    ) throws -> WorkspaceCoreRepository.PaneGraphRecord {
        .init(panes: try state.panes.map { try paneRecord(from: $0, updatedAt: state.updatedAt) })
    }

    static func tabShellRecords(
        from state: WorkspaceSQLiteSnapshot
    ) -> [WorkspaceCoreRepository.TabShellRecord] {
        state.tabs.map { tab in
            .init(id: tab.id, name: tab.name, colorHex: tab.colorHex)
        }
    }

    static func tabGraphRecord(
        from state: WorkspaceSQLiteSnapshot
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
        from state: WorkspaceSQLiteSnapshot
    ) -> WorkspaceLocalRepository.WindowStateRecord {
        .init(
            sidebarWidth: Double(state.sidebarWidth),
            windowFrame: state.windowFrame
        )
    }

    static func cursorStateRecord(
        from state: WorkspaceSQLiteSnapshot
    ) -> WorkspaceLocalRepository.CursorStateRecord {
        let drawers = state.panes.compactMap(\.drawer)
        let arrangementCursorPairs = state.tabs.map { tab in
            (tab.id, tab.activeArrangementId)
        }
        let activePanePairs = state.tabs.flatMap { tab in
            tab.arrangements.compactMap { arrangement in
                arrangement.activePaneId.map { (arrangement.id, $0) }
            }
        }
        let activeChildPairs = state.tabs.flatMap { tab in
            tab.arrangements.flatMap { arrangement in
                arrangement.drawerViews.compactMap { drawerId, drawerView in
                    drawerView.activeChildId.map {
                        (
                            WorkspaceLocalRepository.ArrangementDrawerCursorKey(
                                arrangementId: arrangement.id,
                                drawerId: drawerId
                            ),
                            $0
                        )
                    }
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

    /// Local cursor rows are advisory presentation memory. Missing or stale values
    /// fall back in memory to deterministic choices from the authoritative core
    /// graph; this projection never writes those defaults back to SQLite.
    static func localCursorStateForComposition(
        persisted: WorkspaceLocalRepository.CursorStateRecord?,
        paneGraph: WorkspaceCoreRepository.PaneGraphRecord,
        tabGraph: WorkspaceCoreRepository.TabGraphRecord
    ) -> WorkspaceLocalRepository.CursorStateRecord {
        let tabIds = Set(tabGraph.tabs.map(\.tabId))
        let activeTabId =
            persisted?.activeTabId.flatMap { tabIds.contains($0) ? $0 : nil }
            ?? tabGraph.tabs.first?.tabId

        var activeArrangementIdsByTabId: [UUID: UUID] = [:]
        var activePaneIdsByArrangementId: [UUID: UUID] = [:]
        for tab in tabGraph.tabs {
            let arrangementIds = Set(tab.arrangements.map(\.id))
            if let persistedId = persisted?.activeArrangementIdsByTabId[tab.tabId],
                arrangementIds.contains(persistedId)
            {
                activeArrangementIdsByTabId[tab.tabId] = persistedId
            } else if let defaultArrangementId = tab.arrangements.first(where: \.isDefault)?.id {
                activeArrangementIdsByTabId[tab.tabId] = defaultArrangementId
            }
            for arrangement in tab.arrangements {
                guard let persistedPaneId = persisted?.activePaneIdsByArrangementId[arrangement.id],
                    arrangement.layout.paneIds.contains(persistedPaneId)
                else {
                    continue
                }
                activePaneIdsByArrangementId[arrangement.id] = persistedPaneId
            }
        }

        let drawersById = Dictionary(
            uniqueKeysWithValues: paneGraph.panes.compactMap { pane in
                pane.drawer.map { ($0.drawerId, $0) }
            }
        )
        var drawerExpansionByDrawerId = Dictionary(
            uniqueKeysWithValues: drawersById.keys.map { ($0, false) }
        )
        for (drawerId, isExpanded) in persisted?.drawerExpansionByDrawerId ?? [:]
        where drawersById[drawerId] != nil {
            drawerExpansionByDrawerId[drawerId] = isExpanded
        }

        var activeChildIdsByArrangementDrawer: [WorkspaceLocalRepository.ArrangementDrawerCursorKey: UUID] = [:]
        for (key, childPaneId) in persisted?.activeChildIdsByArrangementDrawer ?? [:] {
            guard
                let tab = tabGraph.tabs.first(where: { tab in
                    tab.arrangements.contains(where: { $0.id == key.arrangementId })
                }),
                let arrangement = tab.arrangements.first(where: { $0.id == key.arrangementId }),
                arrangement.drawerViews[key.drawerId] != nil,
                drawersById[key.drawerId]?.childPaneIds.contains(childPaneId) == true
            else {
                continue
            }
            activeChildIdsByArrangementDrawer[key] = childPaneId
        }

        return .init(
            activeTabId: activeTabId,
            activeArrangementIdsByTabId: activeArrangementIdsByTabId,
            activePaneIdsByArrangementId: activePaneIdsByArrangementId,
            drawerExpansionByDrawerId: drawerExpansionByDrawerId,
            activeChildIdsByArrangementDrawer: activeChildIdsByArrangementDrawer
        )
    }

    static func workspaceSnapshot(
        from snapshot: Snapshot
    ) throws -> WorkspaceSQLiteSnapshot {
        let tabShellsById = Dictionary(uniqueKeysWithValues: snapshot.tabShells.map { ($0.id, $0) })
        let windowState = snapshot.windowState ?? .init(sidebarWidth: 250, windowFrame: nil)
        return .init(
            id: snapshot.workspace.id,
            name: snapshot.workspace.name,
            panes: try snapshot.paneGraph.panes.map { try pane(from: $0, cursorState: snapshot.cursorState) },
            tabs: try snapshot.tabGraph.tabs.map { tabState in
                try tab(
                    from: tabState,
                    shell: tabShellsById[tabState.tabId],
                    cursorState: snapshot.cursorState
                )
            },
            activeTabId: snapshot.cursorState.activeTabId,
            sidebarWidth: CGFloat(windowState.sidebarWidth),
            windowFrame: windowState.windowFrame,
            createdAt: snapshot.workspace.createdAt,
            updatedAt: snapshot.workspace.updatedAt
        )
    }

    static func repositoryTopologySnapshot(
        topology: WorkspaceCoreRepository.RepositoryTopologyRecord,
        updatedAt: Date
    ) -> RepositoryTopologySQLiteSnapshot {
        RepositoryTopologySQLiteSnapshot(
            repos: topology.repos.map(canonicalRepo),
            worktrees: topology.repos.flatMap { $0.worktrees.map(canonicalWorktree) },
            unavailableRepoIds: topology.unavailableRepoIds,
            watchedPaths: topology.watchedPaths.map(watchedPath),
            updatedAt: updatedAt
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
            return .terminal(
                provider: state.provider,
                lifetime: state.lifetime,
                zmxSessionID: state.zmxSessionID
            )
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
            launchDirectory: metadata.launchDirectory,
            executionBackend: metadata.executionBackend,
            createdAt: metadata.createdAt,
            title: metadata.title,
            note: metadata.note,
            checkoutRef: metadata.checkoutRef,
            durableFacets: .init(
                repoId: metadata.facets.repoId,
                worktreeId: metadata.facets.worktreeId,
                cwd: metadata.facets.cwd
            )
        )
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
            kind: try paneKind(from: record, cursorState: cursorState)
        )
    }

    private static func paneContent(
        from record: WorkspaceCoreRepository.PaneContentRecord
    ) throws -> PaneContent {
        switch record {
        case .terminal(let provider, let lifetime, let zmxSessionID):
            .terminal(.init(provider: provider, lifetime: lifetime, zmxSessionID: zmxSessionID))
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
            paneId: PaneId(existingUUID: paneId),
            contentType: contentType,
            launchDirectory: record.launchDirectory,
            executionBackend: record.executionBackend,
            createdAt: record.createdAt,
            title: record.title,
            facets: .init(
                repoId: record.durableFacets.repoId,
                worktreeId: record.durableFacets.worktreeId,
                cwd: record.durableFacets.cwd
            ),
            checkoutRef: record.checkoutRef,
            note: record.note,
            fillNilLaunchDirectoryFacet: false
        )
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
    ) throws -> PaneKind {
        switch record.placement {
        case .layout:
            guard let drawerRecord = record.drawer else {
                throw WorkspaceSQLiteStateBridgeError.layoutPaneMissingDrawer(record.id)
            }
            guard let isExpanded = cursorState.drawerExpansionByDrawerId[drawerRecord.drawerId] else {
                throw WorkspaceSQLiteStateBridgeError.missingDrawerExpansionState
            }
            let drawer = Drawer(
                drawerId: drawerRecord.drawerId,
                parentPaneId: drawerRecord.parentPaneId,
                paneIds: drawerRecord.childPaneIds,
                isExpanded: isExpanded
            )
            return .layout(drawer: drawer)
        case .drawerChild(let parentPaneId):
            return .drawerChild(parentPaneId: parentPaneId)
        }
    }

    private static func tab(
        from state: WorkspaceCoreRepository.TabGraphStateRecord,
        shell: WorkspaceCoreRepository.TabShellRecord?,
        cursorState: WorkspaceLocalRepository.CursorStateRecord
    ) throws -> Tab {
        let arrangements = state.arrangements.map { arrangement in
            paneArrangement(from: arrangement, cursorState: cursorState)
        }
        guard !arrangements.isEmpty, arrangements.filter(\.isDefault).count == 1 else {
            throw WorkspaceSQLiteStateBridgeError.invalidTabArrangementSet(state.tabId)
        }
        guard let activeArrangementId = cursorState.activeArrangementIdsByTabId[state.tabId] else {
            throw WorkspaceSQLiteStateBridgeError.missingActiveArrangementState
        }
        guard arrangements.contains(where: { $0.id == activeArrangementId }) else {
            throw WorkspaceSQLiteStateBridgeError.activeArrangementNotInTab(state.tabId)
        }
        guard let shell else {
            throw WorkspaceSQLiteStateBridgeError.missingTabShell
        }
        return .init(
            id: state.tabId,
            name: shell.name,
            allPaneIds: state.allPaneIds,
            arrangements: arrangements,
            activeArrangementId: activeArrangementId,
            colorHex: shell.colorHex,
            zoomedPaneId: nil
        )
    }

}
