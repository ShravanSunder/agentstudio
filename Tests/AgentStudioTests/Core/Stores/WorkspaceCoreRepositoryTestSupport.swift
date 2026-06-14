import Foundation
import GRDB

@testable import AgentStudio

func makeWorkspaceCoreRepositoryFixture() throws -> WorkspaceCoreTopologyRepositoryFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceCoreMigrations.migrate(databaseQueue)
    return .init(
        repository: WorkspaceCoreRepository(databaseWriter: databaseQueue),
        databaseQueue: databaseQueue
    )
}

struct WorkspaceCoreTopologyRepositoryFixture {
    let repository: WorkspaceCoreRepository
    let databaseQueue: DatabaseQueue

    func insertPane(
        workspaceId: UUID,
        paneId: UUID,
        sourceRepoId: UUID,
        sourceWorktreeId: UUID
    ) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO pane(
                        id, workspace_id, content_type, execution_backend,
                        facet_repo_id, facet_worktree_id, launch_directory, title, cwd,
                        residency_kind, kind, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    paneId.uuidString,
                    workspaceId.uuidString,
                    SQLitePaneContentTypeStorage.storageValue(for: .terminal),
                    "zmx",
                    sourceRepoId.uuidString,
                    sourceWorktreeId.uuidString,
                    "/tmp",
                    "Terminal",
                    "/tmp",
                    "active",
                    "leaf",
                    1.0,
                    1.0,
                ]
            )
        }
    }

    func fetchPaneSource(paneId: UUID) throws -> PaneSourceRecord? {
        try databaseQueue.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT facet_repo_id, facet_worktree_id
                        FROM pane
                        WHERE id = ?
                        """,
                    arguments: [paneId.uuidString]
                )
            else {
                return nil
            }
            let repoIdString: String? = row["facet_repo_id"]
            let worktreeIdString: String? = row["facet_worktree_id"]
            return .init(
                repoId: repoIdString.flatMap(UUID.init(uuidString:)),
                worktreeId: worktreeIdString.flatMap(UUID.init(uuidString:))
            )
        }
    }

    func insertTabShell(workspaceId: UUID, tabId: UUID) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO tab_shell(id, workspace_id, name, sort_index)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [tabId.uuidString, workspaceId.uuidString, "First", 0]
            )
        }
    }

    func insertTabPane(tabId: UUID, paneId: UUID) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO tab_pane(tab_id, pane_id, sort_index)
                    VALUES (?, ?, ?)
                    """,
                arguments: [tabId.uuidString, paneId.uuidString, 0]
            )
        }
    }

    func fetchTabPaneCount(tabId: UUID, paneId: UUID) throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: """
                    SELECT count(*)
                    FROM tab_pane
                    WHERE tab_id = ?
                    AND pane_id = ?
                    """,
                arguments: [tabId.uuidString, paneId.uuidString]
            ) ?? 0
        }
    }

    func fetchPaneContentRouteCounts() throws -> PaneContentRouteCounts {
        try databaseQueue.read { database in
            try .init(
                terminal: fetchCount(database, tableName: "pane_content_terminal"),
                webview: fetchCount(database, tableName: "pane_content_webview"),
                codeViewer: fetchCount(database, tableName: "pane_content_code_viewer"),
                payload: fetchCount(database, tableName: "pane_content_payload")
            )
        }
    }

    private func fetchCount(_ database: Database, tableName: String) throws -> Int {
        try Int.fetchOne(database, sql: "SELECT count(*) FROM \(tableName)") ?? 0
    }
}

struct PaneSourceRecord: Equatable {
    let repoId: UUID?
    let worktreeId: UUID?
}

struct PaneContentRouteCounts: Equatable {
    let terminal: Int
    let webview: Int
    let codeViewer: Int
    let payload: Int
}

extension Collection {
    var single: Element? {
        count == 1 ? first : nil
    }
}
