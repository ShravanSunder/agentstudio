import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteCommitProtocolTests", .serialized)
struct WorkspaceSQLiteCommitProtocolTests {
    @Test("staged core write is not authoritative until final commit")
    func stagedCoreWriteIsNotAuthoritativeUntilFinalCommit() throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.staged.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let snapshot = WorkspaceSQLiteSnapshot.emptyFixture(
            id: workspaceId,
            name: "Partial Core",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)

        try coreRepository.replaceWorkspaceSnapshotStaged(
            workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: state),
            topology: WorkspaceSQLiteStateBridge.repositoryTopologyRecord(from: state),
            paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: state),
            tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: state),
            tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: state),
            stagedAt: snapshot.updatedAt
        )

        #expect(try !coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: workspaceId))
        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == nil)
    }

    @Test("staged-only status row does not count as completed")
    func stagedOnlyStatusRowDoesNotCountAsCompleted() throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.staged-row.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        try coreRepository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Staged Only",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        )

        try coreRepository.markWorkspaceSQLiteSnapshotStaged(
            workspaceId: workspaceId,
            stagedAt: Date(timeIntervalSince1970: 2)
        )

        #expect(try !coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: workspaceId))
        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == nil)
    }

    @Test("active selection repair ignores staged-only rows")
    func activeSelectionRepairIgnoresStagedOnlyRows() throws {
        let completedWorkspaceId = UUID()
        let stagedWorkspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.commit.active-selection.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        try saveCompletedCoreSnapshot(
            workspaceId: completedWorkspaceId,
            name: "Completed",
            updatedAt: Date(timeIntervalSince1970: 2),
            coreRepository: coreRepository
        )
        try coreRepository.upsertWorkspace(
            .init(
                id: stagedWorkspaceId,
                name: "Staged",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 3)
            )
        )
        try coreRepository.markWorkspaceSQLiteSnapshotStaged(
            workspaceId: stagedWorkspaceId,
            stagedAt: Date(timeIntervalSince1970: 3)
        )
        try coreRepository.selectActiveWorkspace(
            stagedWorkspaceId,
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        let repairedWorkspaceId = try coreRepository.repairActiveCompletedWorkspaceSelection(
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        #expect(repairedWorkspaceId == completedWorkspaceId)
        #expect(try coreRepository.fetchActiveWorkspaceId() == completedWorkspaceId)
    }

    @Test("failed local save leaves staged core recoverable with deterministic local defaults")
    func failedLocalSaveLeavesStagedCoreRecoverableWithDeterministicLocalDefaults() throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.failure.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.failure.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let workingBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
        )
        let committedAt = Date(timeIntervalSince1970: 10)
        try workingBackend.save(
            .emptyFixture(
                id: workspaceId,
                name: "Committed",
                updatedAt: committedAt
            )
        )
        let failingBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw CocoaError(.fileNoSuchFile) }
        )

        #expect(throws: CocoaError.self) {
            try failingBackend.save(
                .emptyFixture(
                    id: workspaceId,
                    name: "Staged But Not Local",
                    updatedAt: Date(timeIntervalSince1970: 11)
                )
            )
        }

        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == nil)
        let recovered = try #require(try workingBackend.load(preferredWorkspaceId: workspaceId))
        #expect(recovered.name == "Staged But Not Local")
        #expect(recovered.sidebarWidth == 250)
        #expect(
            try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == recovered.updatedAt)
        #expect(
            try WorkspaceLocalRepository(
                workspaceId: workspaceId,
                databaseWriter: localQueue
            ).fetchCompletedWorkspaceSQLiteSnapshotAt() == recovered.updatedAt
        )
    }

    @Test("successful core and local save leaves matching completion tokens")
    func successfulCoreAndLocalSaveLeavesMatchingCompletionTokens() throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.success.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.success.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        let backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
        )
        let updatedAt = Date(timeIntervalSince1970: 10)

        try backend.save(
            .emptyFixture(
                id: workspaceId,
                name: "Complete",
                updatedAt: updatedAt
            )
        )

        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == updatedAt)
        #expect(try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == updatedAt)
    }
}

@MainActor
private func saveCompletedCoreSnapshot(
    workspaceId: UUID,
    name: String,
    updatedAt: Date,
    coreRepository: WorkspaceCoreRepository
) throws {
    let snapshot = WorkspaceSQLiteSnapshot.emptyFixture(
        id: workspaceId,
        name: name,
        updatedAt: updatedAt
    )
    let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
    try coreRepository.replaceWorkspaceSnapshot(
        workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: state),
        topology: WorkspaceSQLiteStateBridge.repositoryTopologyRecord(from: state),
        paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: state),
        tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: state),
        tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: state),
        completedAt: updatedAt
    )
}
