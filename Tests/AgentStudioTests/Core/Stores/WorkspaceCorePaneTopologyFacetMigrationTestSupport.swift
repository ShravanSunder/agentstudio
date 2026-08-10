import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

let paneFacetTriggerNames = [
    "pane_facet_repo_matches_workspace",
    "pane_facet_repo_update_matches_workspace",
    "pane_facet_worktree_matches_workspace",
    "pane_facet_worktree_update_matches_workspace",
]

struct Migration015PreservationFixture {
    let databaseQueue: DatabaseQueue
    let ids: Migration015FixtureIDs

    var workspaceID: UUID { ids.workspaceID }
    var repositoryID: UUID { ids.repositoryID }
    var worktreeID: UUID { ids.worktreeID }
    var paneIDs: [UUID] { ids.paneIDs }
    var terminalPaneID: UUID { ids.terminalPaneID }
    var codeViewerPaneID: UUID { ids.codeViewerPaneID }
    var bridgePaneID: UUID { ids.bridgePaneID }
    var drawerTerminalPaneID: UUID { ids.drawerTerminalPaneID }
    var secondTabTerminalPaneID: UUID { ids.secondTabTerminalPaneID }
    var drawerID: UUID { ids.drawerID }
    var codeViewerDrawerID: UUID { ids.codeViewerDrawerID }
    var secondTabDrawerID: UUID { ids.secondTabDrawerID }
    var tabIDs: [UUID] { ids.tabIDs }
    var arrangementIDs: [UUID] { ids.arrangementIDs }

    func snapshot() throws -> Migration015PreservationSnapshot {
        try databaseQueue.read { database in
            try Migration015PreservationSnapshot(
                panes: fetchMigration015PaneSnapshot(database),
                layout: fetchMigration015LayoutSnapshot(database)
            )
        }
    }
}

struct Migration015PreservationSnapshot: Equatable {
    let panes: Migration015PaneSnapshot
    let layout: Migration015LayoutSnapshot
}

struct Migration015PaneSnapshot: Equatable {
    let paneRows: [String]
    let terminalRows: [String]
    let codeViewerRows: [String]
    let payloadRows: [String]
    let drawerRows: [String]
    let drawerMembership: [String]
}

struct Migration015LayoutSnapshot: Equatable {
    let tabOrder: [String]
    let tabMembership: [String]
    let arrangementOrder: [String]
    let arrangementLayout: [String]
    let arrangementMinimizedPanes: [String]
    let drawerViewLayout: [String]
}

func fetchMigration015PaneSnapshot(_ database: Database) throws -> Migration015PaneSnapshot {
    try .init(
        paneRows: String.fetchAll(
            database,
            sql: """
                SELECT id || '|' || content_type || '|' || execution_backend || '|'
                    || coalesce(launch_directory, '<null>') || '|' || title || '|'
                    || coalesce(note, '<null>') || '|' || coalesce(cwd, '<null>') || '|'
                    || coalesce(checkout_ref, '<null>') || '|' || residency_kind || '|'
                    || kind || '|' || coalesce(parent_pane_id, '<null>') || '|'
                    || created_at || '|' || updated_at
                FROM pane
                ORDER BY created_at, id
                """
        ),
        terminalRows: String.fetchAll(
            database,
            sql: """
                SELECT pane_id || '|' || provider || '|' || lifetime || '|'
                    || coalesce(zmx_session_id, '<null>')
                FROM pane_content_terminal
                ORDER BY pane_id
                """
        ),
        codeViewerRows: String.fetchAll(
            database,
            sql: """
                SELECT pane_id || '|' || file_path || '|' || coalesce(scroll_to_line, '<null>')
                FROM pane_content_code_viewer
                ORDER BY pane_id
                """
        ),
        payloadRows: String.fetchAll(
            database,
            sql: """
                SELECT pane_id || '|' || payload_kind || '|' || payload_json
                FROM pane_content_payload
                ORDER BY pane_id
                """
        ),
        drawerRows: String.fetchAll(
            database,
            sql: "SELECT id || '|' || parent_pane_id FROM drawer ORDER BY parent_pane_id"
        ),
        drawerMembership: String.fetchAll(
            database,
            sql: """
                SELECT drawer_id || '|' || pane_id || '|' || sort_index
                FROM drawer_pane
                ORDER BY drawer_id, sort_index
                """
        )
    )
}

func fetchMigration015LayoutSnapshot(_ database: Database) throws -> Migration015LayoutSnapshot {
    try .init(
        tabOrder: String.fetchAll(
            database,
            sql: "SELECT id || '|' || name || '|' || sort_index FROM tab_shell ORDER BY sort_index"
        ),
        tabMembership: String.fetchAll(
            database,
            sql: """
                SELECT tab_id || '|' || pane_id || '|' || sort_index
                FROM tab_pane
                ORDER BY tab_id, sort_index
                """
        ),
        arrangementOrder: String.fetchAll(
            database,
            sql: """
                SELECT tab_id || '|' || id || '|' || name || '|' || is_default || '|' || sort_index
                FROM tab_arrangement
                ORDER BY tab_id, sort_index
                """
        ),
        arrangementLayout: String.fetchAll(
            database,
            sql: """
                SELECT arrangement_id || '|pane|' || pane_id || '|' || sort_index || '|' || ratio
                FROM arrangement_layout_pane
                UNION ALL
                SELECT arrangement_id || '|divider|' || divider_id || '|' || sort_index || '|-'
                FROM arrangement_layout_divider
                ORDER BY 1
                """
        ),
        arrangementMinimizedPanes: String.fetchAll(
            database,
            sql: """
                SELECT arrangement_id || '|' || pane_id
                FROM arrangement_minimized_pane
                ORDER BY arrangement_id, pane_id
                """
        ),
        drawerViewLayout: String.fetchAll(
            database,
            sql: """
                SELECT arrangement_id || '|' || drawer_id || '|' || row_kind || '|pane|'
                    || pane_id || '|' || sort_index || '|' || ratio
                FROM drawer_view_layout_pane
                UNION ALL
                SELECT arrangement_id || '|' || drawer_id || '|' || row_kind || '|divider|'
                    || divider_id || '|' || sort_index || '|-'
                FROM drawer_view_layout_divider
                ORDER BY 1
                """
        )
    )
}

struct Migration015FixtureIDs {
    let workspaceID = UUIDv7.generate()
    let repositoryID = UUIDv7.generate()
    let worktreeID = UUIDv7.generate()
    let staleRepositoryID = UUIDv7.generate()
    let staleWorktreeID = UUIDv7.generate()
    let terminalPaneID = UUIDv7.generate()
    let codeViewerPaneID = UUIDv7.generate()
    let bridgePaneID = UUIDv7.generate()
    let drawerTerminalPaneID = UUIDv7.generate()
    let secondTabTerminalPaneID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    let codeViewerDrawerID = UUIDv7.generate()
    let secondTabDrawerID = UUIDv7.generate()
    let firstTabID = UUIDv7.generate()
    let secondTabID = UUIDv7.generate()
    let firstDefaultArrangementID = UUIDv7.generate()
    let firstAlternateArrangementID = UUIDv7.generate()
    let secondDefaultArrangementID = UUIDv7.generate()

    var paneIDs: [UUID] {
        [terminalPaneID, codeViewerPaneID, bridgePaneID, drawerTerminalPaneID, secondTabTerminalPaneID]
    }

    var tabIDs: [UUID] { [firstTabID, secondTabID] }
    var arrangementIDs: [UUID] {
        [firstDefaultArrangementID, firstAlternateArrangementID, secondDefaultArrangementID]
    }
}

func makeMigration015PreservationFixture() throws -> Migration015PreservationFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    let ids = Migration015FixtureIDs()
    try WorkspaceCoreMigrations.migrator.migrate(
        databaseQueue,
        upTo: "014_drop_shows_minimized_panes"
    )
    try databaseQueue.writeWithoutTransaction { database in
        try seedMigration015Predecessor(database, ids: ids)
    }
    return .init(databaseQueue: databaseQueue, ids: ids)
}

func makeMigration015MalformedFacetFixture() throws -> Migration015PreservationFixture {
    let fixture = try makeMigration015PreservationFixture()
    try fixture.databaseQueue.writeWithoutTransaction { database in
        try database.execute(sql: "PRAGMA foreign_keys = OFF")
        try database.execute(
            sql: """
                UPDATE pane
                SET facet_repo_id = ?, facet_worktree_id = ?
                WHERE id = ?
                """,
            arguments: [
                "malformed-repository-uuid",
                "malformed-worktree-uuid",
                fixture.terminalPaneID.uuidString,
            ]
        )
        try database.execute(sql: "PRAGMA foreign_keys = ON")
    }
    return fixture
}

func seedMigration015Predecessor(_ database: Database, ids: Migration015FixtureIDs) throws {
    try database.execute(sql: "PRAGMA foreign_keys = OFF")
    try insertMigration015WorkspaceAndTopology(database, ids: ids)
    try insertMigration015Panes(database, ids: ids)
    try insertMigration015Drawer(
        database,
        drawerID: ids.drawerID,
        parentPaneID: ids.terminalPaneID,
        childPaneIDs: [ids.bridgePaneID, ids.drawerTerminalPaneID]
    )
    try insertMigration015Drawer(
        database,
        drawerID: ids.codeViewerDrawerID,
        parentPaneID: ids.codeViewerPaneID,
        childPaneIDs: []
    )
    try insertMigration015Drawer(
        database,
        drawerID: ids.secondTabDrawerID,
        parentPaneID: ids.secondTabTerminalPaneID,
        childPaneIDs: []
    )
    try insertMigration015TabsAndArrangements(database, ids: ids)
    try insertLegacyPaneFacetTriggers(database)
    try database.execute(sql: "PRAGMA foreign_keys = ON")
}

func insertLegacyPaneFacetTriggers(_ database: Database) throws {
    let triggerStatements = [
        """
        CREATE TRIGGER pane_facet_repo_matches_workspace
        BEFORE INSERT ON pane BEGIN SELECT 1; END
        """,
        """
        CREATE TRIGGER pane_facet_repo_update_matches_workspace
        BEFORE UPDATE OF facet_repo_id ON pane BEGIN SELECT 1; END
        """,
        """
        CREATE TRIGGER pane_facet_worktree_matches_workspace
        BEFORE INSERT ON pane BEGIN SELECT 1; END
        """,
        """
        CREATE TRIGGER pane_facet_worktree_update_matches_workspace
        BEFORE UPDATE OF facet_worktree_id ON pane BEGIN SELECT 1; END
        """,
    ]
    for statement in triggerStatements {
        try database.execute(sql: statement)
    }
}

func insertMigration015WorkspaceAndTopology(
    _ database: Database,
    ids: Migration015FixtureIDs
) throws {
    try database.execute(
        sql: "INSERT INTO workspace(id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
        arguments: [ids.workspaceID.uuidString, "Migration 015", 1.0, 2.0]
    )
    try database.execute(
        sql: """
            UPDATE app_workspace_selection
            SET active_workspace_id = ?, updated_at = ?
            WHERE singleton_id = 1
            """,
        arguments: [ids.workspaceID.uuidString, 2.0]
    )
    try database.execute(
        sql: """
            INSERT INTO repo(id, name, repo_path, stable_key, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
        arguments: [
            ids.repositoryID.uuidString,
            "Migration 015",
            "/tmp/migration-015",
            ids.repositoryID.uuidString,
            2.0,
        ]
    )
    try database.execute(
        sql: """
            INSERT INTO worktree(id, repo_id, name, path, stable_key, is_main_worktree)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            ids.worktreeID.uuidString,
            ids.repositoryID.uuidString,
            "main",
            "/tmp/migration-015",
            ids.worktreeID.uuidString,
            1,
        ]
    )
}

struct Migration015PaneSeed {
    let id: UUID
    let workspaceID: UUID
    let contentType: PaneContentType
    let facetRepositoryID: UUID?
    let facetWorktreeID: UUID?
    let launchDirectory: String?
    let title: String
    let note: String?
    let cwd: String?
    let checkoutRef: String?
    let residency: String
    let kind: String
    let parentPaneID: UUID?
    let timestamp: Double
}

enum Migration015FixtureError: Error {
    case invalidBridgePayloadUTF8
}

func insertMigration015Panes(_ database: Database, ids: Migration015FixtureIDs) throws {
    try insertMigration015PrimaryTerminal(database, ids: ids)
    try insertMigration015CodeViewer(database, ids: ids)
    try insertMigration015Bridge(database, ids: ids)
    try insertMigration015DrawerTerminal(database, ids: ids)
    try insertMigration015SecondTabTerminal(database, ids: ids)
}

func insertMigration015PrimaryTerminal(_ database: Database, ids: Migration015FixtureIDs) throws {
    try insertMigration015Pane(
        database,
        seed: .init(
            id: ids.terminalPaneID,
            workspaceID: ids.workspaceID,
            contentType: .terminal,
            facetRepositoryID: ids.repositoryID,
            facetWorktreeID: ids.worktreeID,
            launchDirectory: "/tmp/migration-015",
            title: "Preserved terminal",
            note: "preserved note",
            cwd: "/tmp/migration-015/Sources",
            checkoutRef: "feature/preserve",
            residency: "backgrounded",
            kind: "leaf",
            parentPaneID: nil,
            timestamp: 3.0
        )
    )
    try database.execute(
        sql: """
            INSERT INTO pane_content_terminal(pane_id, provider, lifetime, zmx_session_id)
            VALUES (?, ?, ?, ?)
            """,
        arguments: [ids.terminalPaneID.uuidString, "zmx", "persistent", "migration-015-anchor"]
    )
}

func insertMigration015CodeViewer(_ database: Database, ids: Migration015FixtureIDs) throws {
    try insertMigration015Pane(
        database,
        seed: .init(
            id: ids.codeViewerPaneID,
            workspaceID: ids.workspaceID,
            contentType: .codeViewer,
            facetRepositoryID: nil,
            facetWorktreeID: nil,
            launchDirectory: nil,
            title: "Nil CWD code viewer",
            note: nil,
            cwd: nil,
            checkoutRef: nil,
            residency: "active",
            kind: "leaf",
            parentPaneID: nil,
            timestamp: 4.0
        )
    )
    try database.execute(
        sql: """
            INSERT INTO pane_content_code_viewer(pane_id, file_path, scroll_to_line)
            VALUES (?, ?, ?)
            """,
        arguments: [ids.codeViewerPaneID.uuidString, "/tmp/migration-015/Sources/App.swift", 37]
    )
}

func insertMigration015Bridge(_ database: Database, ids: Migration015FixtureIDs) throws {
    try insertMigration015Pane(
        database,
        seed: .init(
            id: ids.bridgePaneID,
            workspaceID: ids.workspaceID,
            contentType: .diff,
            facetRepositoryID: ids.staleRepositoryID,
            facetWorktreeID: ids.staleWorktreeID,
            launchDirectory: nil,
            title: "Stale facet Bridge",
            note: "bridge source preserved",
            cwd: nil,
            checkoutRef: "main",
            residency: "active",
            kind: "drawerChild",
            parentPaneID: ids.terminalPaneID,
            timestamp: 5.0
        )
    )
    let bridgeContent = PaneContent.bridgePanel(
        BridgePaneState(
            panelKind: .fileViewer,
            source: .workspace(
                rootPath: "/tmp/migration-015",
                baseline: .localDefaultBranch(branchName: "main")
            )
        )
    )
    let bridgePayload = try JSONEncoder().encode(bridgeContent)
    guard let bridgePayloadJSON = String(bytes: bridgePayload, encoding: .utf8) else {
        throw Migration015FixtureError.invalidBridgePayloadUTF8
    }
    try database.execute(
        sql: """
            INSERT INTO pane_content_payload(pane_id, payload_kind, payload_json)
            VALUES (?, ?, ?)
            """,
        arguments: [ids.bridgePaneID.uuidString, "bridgePanel", bridgePayloadJSON]
    )
}

func insertMigration015DrawerTerminal(_ database: Database, ids: Migration015FixtureIDs) throws {
    try insertMigration015Pane(
        database,
        seed: .init(
            id: ids.drawerTerminalPaneID,
            workspaceID: ids.workspaceID,
            contentType: .terminal,
            facetRepositoryID: ids.repositoryID,
            facetWorktreeID: nil,
            launchDirectory: "/tmp/migration-015",
            title: "Topology degraded drawer terminal",
            note: nil,
            cwd: "/tmp/migration-015/DeletedWorktree",
            checkoutRef: nil,
            residency: "active",
            kind: "drawerChild",
            parentPaneID: ids.terminalPaneID,
            timestamp: 6.0
        )
    )
    try database.execute(
        sql: """
            INSERT INTO pane_content_terminal(pane_id, provider, lifetime, zmx_session_id)
            VALUES (?, ?, ?, ?)
            """,
        arguments: [ids.drawerTerminalPaneID.uuidString, "zmx", "persistent", "migration-015-drawer-anchor"]
    )
}

func insertMigration015SecondTabTerminal(_ database: Database, ids: Migration015FixtureIDs) throws {
    try insertMigration015Pane(
        database,
        seed: .init(
            id: ids.secondTabTerminalPaneID,
            workspaceID: ids.workspaceID,
            contentType: .terminal,
            facetRepositoryID: nil,
            facetWorktreeID: nil,
            launchDirectory: "/tmp/migration-015/Second",
            title: "Second tab terminal",
            note: nil,
            cwd: "/tmp/migration-015/Second",
            checkoutRef: nil,
            residency: "active",
            kind: "leaf",
            parentPaneID: nil,
            timestamp: 7.0
        )
    )
    try database.execute(
        sql: """
            INSERT INTO pane_content_terminal(pane_id, provider, lifetime, zmx_session_id)
            VALUES (?, ?, ?, ?)
            """,
        arguments: [ids.secondTabTerminalPaneID.uuidString, "zmx", "persistent", "migration-015-second-anchor"]
    )
}

func insertMigration015Pane(
    _ database: Database,
    seed: Migration015PaneSeed
) throws {
    try database.execute(
        sql: """
            INSERT INTO pane(
                id, workspace_id, content_type, execution_backend,
                facet_repo_id, facet_worktree_id, launch_directory, title, note,
                cwd, checkout_ref, residency_kind, kind, parent_pane_id,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            seed.id.uuidString,
            seed.workspaceID.uuidString,
            SQLitePaneContentTypeStorage.storageValue(for: seed.contentType),
            "local",
            seed.facetRepositoryID?.uuidString,
            seed.facetWorktreeID?.uuidString,
            seed.launchDirectory,
            seed.title,
            seed.note,
            seed.cwd,
            seed.checkoutRef,
            seed.residency,
            seed.kind,
            seed.parentPaneID?.uuidString,
            seed.timestamp,
            seed.timestamp + 0.5,
        ]
    )
}

func insertMigration015Drawer(
    _ database: Database,
    drawerID: UUID,
    parentPaneID: UUID,
    childPaneIDs: [UUID]
) throws {
    try database.execute(
        sql: "INSERT INTO drawer(id, parent_pane_id) VALUES (?, ?)",
        arguments: [drawerID.uuidString, parentPaneID.uuidString]
    )
    for (sortIndex, childPaneID) in childPaneIDs.enumerated() {
        try database.execute(
            sql: "INSERT INTO drawer_pane(drawer_id, pane_id, sort_index) VALUES (?, ?, ?)",
            arguments: [drawerID.uuidString, childPaneID.uuidString, sortIndex]
        )
    }
}

func insertMigration015TabsAndArrangements(
    _ database: Database,
    ids: Migration015FixtureIDs
) throws {
    let firstTabPaneIDs = Array(ids.paneIDs.prefix(4))
    let tabs = [(ids.firstTabID, "First", 0), (ids.secondTabID, "Second", 1)]
    let workspaceID = try String.fetchOne(database, sql: "SELECT id FROM workspace")
    for (tabID, name, sortIndex) in tabs {
        try database.execute(
            sql: "INSERT INTO tab_shell(id, workspace_id, name, sort_index) VALUES (?, ?, ?, ?)",
            arguments: [tabID.uuidString, workspaceID, name, sortIndex]
        )
    }
    for (sortIndex, paneID) in firstTabPaneIDs.enumerated() {
        try database.execute(
            sql: "INSERT INTO tab_pane(tab_id, pane_id, sort_index) VALUES (?, ?, ?)",
            arguments: [ids.firstTabID.uuidString, paneID.uuidString, sortIndex]
        )
    }
    try database.execute(
        sql: "INSERT INTO tab_pane(tab_id, pane_id, sort_index) VALUES (?, ?, 0)",
        arguments: [ids.secondTabID.uuidString, ids.secondTabTerminalPaneID.uuidString]
    )

    try insertMigration015Arrangement(
        database,
        seed: .init(
            id: ids.firstDefaultArrangementID,
            tabID: ids.firstTabID,
            name: "Default",
            isDefault: true,
            sortIndex: 0,
            layoutPaneIDs: Array(firstTabPaneIDs.prefix(2)),
            drawerChildPaneIDs: Array(firstTabPaneIDs.suffix(2)),
            drawerID: ids.drawerID
        )
    )
    try insertMigration015Arrangement(
        database,
        seed: .init(
            id: ids.firstAlternateArrangementID,
            tabID: ids.firstTabID,
            name: "Alternate",
            isDefault: false,
            sortIndex: 1,
            layoutPaneIDs: Array(firstTabPaneIDs.prefix(2).reversed()),
            drawerChildPaneIDs: Array(firstTabPaneIDs.suffix(2).reversed()),
            drawerID: ids.drawerID
        )
    )
    try insertMigration015Arrangement(
        database,
        seed: .init(
            id: ids.secondDefaultArrangementID,
            tabID: ids.secondTabID,
            name: "Default",
            isDefault: true,
            sortIndex: 0,
            layoutPaneIDs: [ids.secondTabTerminalPaneID],
            drawerChildPaneIDs: [],
            drawerID: nil
        )
    )
}

struct Migration015ArrangementSeed {
    let id: UUID
    let tabID: UUID
    let name: String
    let isDefault: Bool
    let sortIndex: Int
    let layoutPaneIDs: [UUID]
    let drawerChildPaneIDs: [UUID]
    let drawerID: UUID?
}

func insertMigration015Arrangement(
    _ database: Database,
    seed: Migration015ArrangementSeed
) throws {
    try database.execute(
        sql: """
            INSERT INTO tab_arrangement(id, tab_id, name, is_default, sort_index)
            VALUES (?, ?, ?, ?, ?)
            """,
        arguments: [seed.id.uuidString, seed.tabID.uuidString, seed.name, seed.isDefault ? 1 : 0, seed.sortIndex]
    )
    for (index, paneID) in seed.layoutPaneIDs.enumerated() {
        try database.execute(
            sql: """
                INSERT INTO arrangement_layout_pane(arrangement_id, pane_id, sort_index, ratio)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [seed.id.uuidString, paneID.uuidString, index * 2, index == 0 ? 0.6 : 0.4]
        )
    }
    if seed.layoutPaneIDs.count > 1 {
        try database.execute(
            sql: """
                INSERT INTO arrangement_layout_divider(arrangement_id, divider_id, sort_index)
                VALUES (?, ?, 1)
                """,
            arguments: [seed.id.uuidString, UUIDv7.generate().uuidString]
        )
        try database.execute(
            sql: "INSERT INTO arrangement_minimized_pane(arrangement_id, pane_id) VALUES (?, ?)",
            arguments: [seed.id.uuidString, seed.layoutPaneIDs[1].uuidString]
        )
    }
    guard let drawerID = seed.drawerID else { return }
    try database.execute(
        sql: """
            INSERT INTO arrangement_drawer_view(arrangement_id, drawer_id, row_split_ratio)
            VALUES (?, ?, ?)
            """,
        arguments: [seed.id.uuidString, drawerID.uuidString, 0.7]
    )
    for (index, paneID) in seed.drawerChildPaneIDs.enumerated() {
        try database.execute(
            sql: """
                INSERT INTO drawer_view_layout_pane(
                    arrangement_id, drawer_id, row_kind, pane_id, sort_index, ratio
                )
                VALUES (?, ?, 'top', ?, ?, ?)
                """,
            arguments: [
                seed.id.uuidString, drawerID.uuidString, paneID.uuidString, index * 2, index == 0 ? 0.55 : 0.45,
            ]
        )
    }
    try database.execute(
        sql: """
            INSERT INTO drawer_view_layout_divider(
                arrangement_id, drawer_id, row_kind, divider_id, sort_index
            )
            VALUES (?, ?, 'top', ?, 1)
            """,
        arguments: [seed.id.uuidString, drawerID.uuidString, UUIDv7.generate().uuidString]
    )
}

@MainActor
func makeMigration015WorkspaceStore(
    coreDatabaseQueue: DatabaseQueue,
    localDatabaseQueue: DatabaseQueue
) async throws -> WorkspaceStore {
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue),
        makeLocalRepository: { workspaceID in
            WorkspaceLocalRepository(workspaceId: workspaceID, databaseWriter: localDatabaseQueue)
        },
        coreDatabaseStartupProvenance: .preexisting
    )
    let datastore = try await preparedWorkspaceSQLiteDatastore(from: backend)
    let coreAtoms = CoreAtoms()
    let saveCoordinator = WorkspaceSQLiteSaveCoordinator(
        identityAtom: coreAtoms.workspaceIdentity,
        windowMemoryAtom: coreAtoms.workspaceWindowMemory,
        workspacePaneAtom: coreAtoms.workspacePane,
        workspaceTabLayoutAtom: coreAtoms.workspaceTabLayout,
        sqliteDatastore: datastore
    )
    return WorkspaceStore(
        identityAtom: coreAtoms.workspaceIdentity,
        windowMemoryAtom: coreAtoms.workspaceWindowMemory,
        repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology,
        paneAtom: coreAtoms.workspacePane,
        tabLayoutAtom: coreAtoms.workspaceTabLayout,
        mutationCoordinator: coreAtoms.workspaceMutationCoordinator,
        sqliteDatastore: datastore,
        sqliteSaveCoordinator: saveCoordinator
    )
}

struct Migration015ApplicationSnapshot: Equatable {
    let workspaceID: UUID
    let workspaceName: String
    let workspaceCreatedAt: Date
    let repositories: [Repo]
    let watchedPaths: [WatchedPath]
    let unavailableRepositoryIDs: Set<UUID>
    let panes: [Pane]
    let tabs: [Tab]
    let activeTabID: UUID?
}

@MainActor
func migration015ApplicationSnapshot(
    _ store: WorkspaceStore
) -> Migration015ApplicationSnapshot {
    .init(
        workspaceID: store.identityAtom.workspaceId,
        workspaceName: store.identityAtom.workspaceName,
        workspaceCreatedAt: store.identityAtom.createdAt,
        repositories: store.repositoryTopologyAtom.repos,
        watchedPaths: store.repositoryTopologyAtom.watchedPaths,
        unavailableRepositoryIDs: store.repositoryTopologyAtom.unavailableRepoIds,
        panes: store.paneAtom.paneSnapshot().values.sorted { leftPane, rightPane in
            leftPane.id.uuidString < rightPane.id.uuidString
        },
        tabs: store.tabLayoutAtom.tabs,
        activeTabID: store.tabLayoutAtom.activeTabId
    )
}

@MainActor
func assertMigration015ApplicationState(
    _ store: WorkspaceStore,
    fixture: Migration015PreservationFixture
) throws {
    #expect(store.identityAtom.workspaceId == fixture.workspaceID)
    #expect(store.paneAtom.graphAtom.paneIDs == Set(fixture.paneIDs))
    #expect(store.tabLayoutAtom.tabs.map(\.id) == fixture.tabIDs)

    let repository = try #require(store.repositoryTopologyAtom.repos.single)
    #expect(repository.id == fixture.repositoryID)
    #expect(repository.name == "Migration 015")
    #expect(repository.repoPath == URL(filePath: "/tmp/migration-015"))
    let worktree = try #require(repository.worktrees.single)
    #expect(worktree.id == fixture.worktreeID)
    #expect(worktree.repoId == fixture.repositoryID)
    #expect(worktree.name == "main")
    #expect(worktree.path == URL(filePath: "/tmp/migration-015"))
    #expect(worktree.isMainWorktree)
    #expect(store.repositoryTopologyAtom.watchedPaths.isEmpty)
    #expect(store.repositoryTopologyAtom.unavailableRepoIds.isEmpty)
    #expect(store.repositoryTopologyAtom.worktreePathIndexCount == 1)

    let terminalPane = try #require(store.paneAtom.pane(fixture.terminalPaneID))
    #expect(
        terminalPane.metadata.launchDirectory
            == URL(filePath: "/tmp/migration-015", directoryHint: .isDirectory)
    )
    #expect(
        terminalPane.metadata.cwd
            == URL(filePath: "/tmp/migration-015/Sources", directoryHint: .isDirectory)
    )
    #expect(terminalPane.metadata.note == "preserved note")
    #expect(terminalPane.metadata.checkoutRef == "feature/preserve")
    #expect(terminalPane.terminalState?.zmxSessionID.rawValue == "migration-015-anchor")
    #expect(terminalPane.drawer?.drawerId == fixture.drawerID)
    #expect(
        terminalPane.drawer?.paneIds
            == [fixture.bridgePaneID, fixture.drawerTerminalPaneID]
    )

    let codeViewerPane = try #require(store.paneAtom.pane(fixture.codeViewerPaneID))
    #expect(codeViewerPane.metadata.launchDirectory == nil)
    #expect(
        codeViewerPane.metadata.cwd
            == URL(filePath: "/tmp/migration-015/Sources", directoryHint: .isDirectory)
    )
    #expect(codeViewerPane.drawer?.drawerId == fixture.codeViewerDrawerID)
    #expect(
        codeViewerPane.content
            == .codeViewer(
                CodeViewerState(
                    filePath: URL(filePath: "/tmp/migration-015/Sources/App.swift"),
                    scrollToLine: 37
                )
            )
    )

    let bridgePane = try #require(store.paneAtom.pane(fixture.bridgePaneID))
    #expect(bridgePane.metadata.launchDirectory == nil)
    #expect(
        bridgePane.metadata.cwd
            == URL(filePath: "/tmp/migration-015", directoryHint: .isDirectory)
    )
    #expect(
        bridgePane.content
            == .bridgePanel(
                BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(
                        rootPath: "/tmp/migration-015",
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                )
            )
    )

    for paneID in fixture.paneIDs {
        let pane = try #require(store.paneAtom.pane(paneID))
        #expect(pane.repoId == fixture.repositoryID)
        #expect(pane.worktreeId == fixture.worktreeID)
    }

    let firstTab = try #require(store.tabLayoutAtom.tab(fixture.tabIDs[0]))
    #expect(firstTab.allPaneIds == Array(fixture.paneIDs.prefix(4)))
    #expect(firstTab.arrangements.map(\.id) == Array(fixture.arrangementIDs.prefix(2)))
    #expect(
        firstTab.arrangements[0].layout.paneIds
            == [fixture.terminalPaneID, fixture.codeViewerPaneID]
    )
    #expect(
        firstTab.arrangements[1].layout.paneIds
            == [fixture.codeViewerPaneID, fixture.terminalPaneID]
    )
    #expect(
        firstTab.arrangements[0].drawerViews[fixture.drawerID]?.layout.topRow.paneIds
            == [fixture.bridgePaneID, fixture.drawerTerminalPaneID]
    )
    #expect(
        firstTab.arrangements[1].drawerViews[fixture.drawerID]?.layout.topRow.paneIds
            == [fixture.drawerTerminalPaneID, fixture.bridgePaneID]
    )

    let secondTab = try #require(store.tabLayoutAtom.tab(fixture.tabIDs[1]))
    #expect(
        store.paneAtom.pane(fixture.secondTabTerminalPaneID)?.drawer?.drawerId
            == fixture.secondTabDrawerID
    )
    #expect(secondTab.allPaneIds == [fixture.secondTabTerminalPaneID])
    #expect(secondTab.arrangements.map(\.id) == [fixture.arrangementIDs[2]])
    #expect(secondTab.arrangements[0].layout.paneIds == [fixture.secondTabTerminalPaneID])
}

func fetchPaneFacetTriggerNames(_ database: Database) throws -> [String] {
    try String.fetchAll(
        database,
        sql: """
            SELECT name
            FROM sqlite_master
            WHERE type = 'trigger' AND name LIKE 'pane_facet_%'
            ORDER BY name
            """
    )
}
