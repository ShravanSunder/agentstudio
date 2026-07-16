import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreRecoveryTests", .serialized)
struct WorkspaceSQLiteStoreRecoveryTests {
    @Test("failed core replacement does not advance local snapshot token")
    func failedCoreReplacementDoesNotAdvanceLocalSnapshotToken() async throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_280)
        let committedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_290)
        try fixture.backend.save(
            .emptyFixture(
                id: workspaceId,
                name: "Committed Workspace",
                activeTabId: nil,
                sidebarWidth: 250,
                createdAt: createdAt,
                updatedAt: committedUpdatedAt
            )
        )
        let committedLocalSnapshotAt = try fixture.localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt()
        let invalidPaneId = UUID()
        let invalidTab = Tab(paneId: invalidPaneId, name: "Invalid Replacement Tab")

        #expect(throws: (any Error).self) {
            try fixture.backend.save(
                .emptyFixture(
                    id: workspaceId,
                    name: "Invalid Replacement",
                    panes: [],
                    tabs: [invalidTab],
                    activeTabId: invalidTab.id,
                    sidebarWidth: 999,
                    createdAt: createdAt,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
                )
            )
        }

        #expect(try fixture.localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == committedLocalSnapshotAt)
        let loaded = try #require(try fixture.backend.load())
        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Committed Workspace")
        #expect(loaded.name != "Invalid Replacement")
        #expect(loaded.activeTabId == nil)
        #expect(loaded.sidebarWidth == 250)
    }

    @Test("completed snapshot readiness requires matching local snapshot")
    func completedSnapshotReadinessRequiresMatchingLocalSnapshot() async throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        let coreCompletedAt = Date(timeIntervalSince1970: 1_700_000_310)
        try fixture.backend.save(
            .emptyFixture(
                id: workspaceId,
                name: "Archive Candidate",
                sidebarWidth: 315,
                createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                updatedAt: coreCompletedAt
            )
        )
        #expect(
            try fixture.backend.hasCompletedSnapshot(
                workspaceId: workspaceId,
                localRepository: fixture.localRepository
            )
        )

        try await fixture.localQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_workspace_sqlite_snapshot_status
                    SET completed_at = ?
                    WHERE workspace_id = ?
                    """,
                arguments: [
                    coreCompletedAt.addingTimeInterval(60).timeIntervalSince1970,
                    workspaceId.uuidString,
                ]
            )
        }

        #expect(
            try !fixture.backend.hasCompletedSnapshot(
                workspaceId: workspaceId,
                localRepository: fixture.localRepository
            )
        )
    }
}

private struct WorkspaceSQLiteRecoveryFixture {
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let localRepository: WorkspaceLocalRepository
    let backend: WorkspaceSQLiteStoreBackend
}

@MainActor
private func makeRecoveryFixture(workspaceId: UUID) throws -> WorkspaceSQLiteRecoveryFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.recovery.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.recovery.local")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        }
    )
    return .init(
        localQueue: localQueue,
        coreRepository: coreRepository,
        localRepository: localRepository,
        backend: backend
    )
}
