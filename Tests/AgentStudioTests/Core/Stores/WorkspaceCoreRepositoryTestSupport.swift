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
                        id, workspace_id, content_type, execution_backend, source_kind,
                        source_repo_id, source_worktree_id, launch_directory, title, cwd,
                        residency_kind, kind, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    paneId.uuidString,
                    workspaceId.uuidString,
                    SQLitePaneContentTypeStorage.storageValue(for: .terminal),
                    "zmx",
                    "workspace",
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
                        SELECT source_repo_id, source_worktree_id
                        FROM pane
                        WHERE id = ?
                        """,
                    arguments: [paneId.uuidString]
                )
            else {
                return nil
            }
            let repoIdString: String? = row["source_repo_id"]
            let worktreeIdString: String? = row["source_worktree_id"]
            return .init(
                repoId: repoIdString.flatMap(UUID.init(uuidString:)),
                worktreeId: worktreeIdString.flatMap(UUID.init(uuidString:))
            )
        }
    }
}

struct PaneSourceRecord: Equatable {
    let repoId: UUID?
    let worktreeId: UUID?
}

extension Collection {
    var single: Element? {
        count == 1 ? first : nil
    }
}
