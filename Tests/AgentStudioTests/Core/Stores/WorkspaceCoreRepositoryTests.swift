import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTests")
struct WorkspaceCoreRepositoryTests {
    @Test("workspace metadata round trips through repository rows")
    func workspaceMetadataRoundTripsThroughRepositoryRows() throws {
        let repository = try makeFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let record = WorkspaceCoreRepository.WorkspaceRecord(
            id: workspaceId,
            name: "SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try repository.upsertWorkspace(record)
        let restoredRecord = try repository.fetchWorkspace(id: workspaceId)

        #expect(restoredRecord == record)
    }

    @Test("workspace upsert preserves createdAt on conflict")
    func workspaceUpsertPreservesCreatedAtOnConflict() throws {
        let repository = try makeFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        let originalCreatedAt = Date(timeIntervalSince1970: 100)
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Original",
                createdAt: originalCreatedAt,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )

        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Updated",
                createdAt: Date(timeIntervalSince1970: 999),
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let restoredRecord = try repository.fetchWorkspace(id: workspaceId)

        #expect(
            restoredRecord
                == .init(
                    id: workspaceId,
                    name: "Updated",
                    createdAt: originalCreatedAt,
                    updatedAt: Date(timeIntervalSince1970: 300)
                )
        )
    }

    @Test("workspace rename preserves createdAt and advances updatedAt")
    func workspaceRenamePreservesCreatedAtAndAdvancesUpdatedAt() throws {
        let repository = try makeFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let createdAt = Date(timeIntervalSince1970: 100)
        try repository.upsertWorkspace(
            .init(id: workspaceId, name: "Original", createdAt: createdAt, updatedAt: createdAt)
        )

        try repository.renameWorkspace(
            workspaceId,
            name: "Renamed",
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let restoredRecord = try repository.fetchWorkspace(id: workspaceId)

        #expect(
            restoredRecord
                == .init(
                    id: workspaceId,
                    name: "Renamed",
                    createdAt: createdAt,
                    updatedAt: Date(timeIntervalSince1970: 300)
                )
        )
    }

    @Test("workspace rename rejects missing workspace")
    func workspaceRenameRejectsMissingWorkspace() throws {
        let repository = try makeFixture().repository
        let missingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000015")!

        #expect(throws: WorkspaceCoreRepositoryError.workspaceNotFound(missingWorkspaceId)) {
            try repository.renameWorkspace(
                missingWorkspaceId,
                name: "Missing",
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        }
    }

    @Test("active workspace selection round trips independently from workspace identity")
    func activeWorkspaceSelectionRoundTripsIndependentlyFromWorkspaceIdentity() throws {
        let repository = try makeFixture().repository
        let selectedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        try repository.upsertWorkspace(
            .init(
                id: selectedWorkspaceId,
                name: "Selected",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )

        try repository.selectActiveWorkspace(
            selectedWorkspaceId,
            updatedAt: Date(timeIntervalSince1970: 250)
        )
        let restoredActiveWorkspaceId = try repository.fetchActiveWorkspaceId()

        #expect(restoredActiveWorkspaceId == selectedWorkspaceId)
    }

    @Test("active workspace selection recreates missing singleton row")
    func activeWorkspaceSelectionRecreatesMissingSingletonRow() throws {
        let fixture = try makeFixture()
        let repository = fixture.repository
        let selectedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000018")!
        try repository.upsertWorkspace(
            .init(
                id: selectedWorkspaceId,
                name: "Selected",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try deleteActiveWorkspaceSelectionSingleton(in: fixture.databaseQueue)

        try repository.selectActiveWorkspace(
            selectedWorkspaceId,
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(try repository.fetchActiveWorkspaceId() == selectedWorkspaceId)
        #expect(try activeWorkspaceSelectionSingletonCount(in: fixture.databaseQueue) == 1)
    }

    @Test("active workspace selection rejects missing workspace")
    func activeWorkspaceSelectionRejectsMissingWorkspace() throws {
        let repository = try makeFixture().repository
        let missingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000016")!

        #expect(throws: WorkspaceCoreRepositoryError.workspaceNotFound(missingWorkspaceId)) {
            try repository.selectActiveWorkspace(
                missingWorkspaceId,
                updatedAt: Date(timeIntervalSince1970: 250)
            )
        }
    }

    @Test("active workspace clear is rejected while workspace rows remain")
    func activeWorkspaceClearIsRejectedWhileWorkspaceRowsRemain() throws {
        let repository = try makeFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000017")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Existing",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.cannotClearActiveWorkspaceWhileWorkspacesExist) {
            try repository.clearActiveWorkspaceSelection(updatedAt: Date(timeIntervalSince1970: 300))
        }
    }

    @Test("dangling active workspace selection fails fast on read")
    func danglingActiveWorkspaceSelectionFailsFastOnRead() throws {
        let fixture = try makeFixture()
        let repository = fixture.repository
        let fallbackWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
        let danglingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000024")!
        try repository.upsertWorkspace(
            .init(
                id: fallbackWorkspaceId,
                name: "Fallback",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try setRawActiveWorkspaceSelection(danglingWorkspaceId.uuidString, in: fixture.databaseQueue)

        #expect(throws: WorkspaceCoreRepositoryError.activeWorkspaceSelectionDangling(danglingWorkspaceId)) {
            try repository.fetchActiveWorkspaceId()
        }
    }

    @Test("deleting active workspace repairs selection in the same core transaction")
    func deletingActiveWorkspaceRepairsSelectionInTheSameCoreTransaction() throws {
        let repository = try makeFixture().repository
        let activeWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let remainingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let createdAt = Date(timeIntervalSince1970: 100)

        try repository.upsertWorkspace(
            .init(
                id: activeWorkspaceId,
                name: "Active",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )
        try repository.upsertWorkspace(
            .init(
                id: remainingWorkspaceId,
                name: "Remaining",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try repository.selectActiveWorkspace(
            activeWorkspaceId,
            updatedAt: Date(timeIntervalSince1970: 350)
        )

        let repairedWorkspaceId = try repository.deleteWorkspace(
            activeWorkspaceId,
            updatedAt: Date(timeIntervalSince1970: 400)
        )

        #expect(repairedWorkspaceId == remainingWorkspaceId)
        #expect(try repository.fetchActiveWorkspaceId() == remainingWorkspaceId)
        #expect(try repository.fetchWorkspace(id: activeWorkspaceId) == nil)
    }

    @Test("deleting non-active workspace preserves current active selection")
    func deletingNonActiveWorkspacePreservesCurrentActiveSelection() throws {
        let repository = try makeFixture().repository
        let activeWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000035")!
        let deletedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000036")!
        let newerRemainingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000037")!
        let createdAt = Date(timeIntervalSince1970: 100)
        try repository.upsertWorkspace(
            .init(id: activeWorkspaceId, name: "Active", createdAt: createdAt, updatedAt: createdAt)
        )
        try repository.upsertWorkspace(
            .init(
                id: deletedWorkspaceId,
                name: "Deleted",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )
        try repository.upsertWorkspace(
            .init(
                id: newerRemainingWorkspaceId,
                name: "Newer Remaining",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 250)
            )
        )
        try repository.selectActiveWorkspace(activeWorkspaceId, updatedAt: Date(timeIntervalSince1970: 150))

        let activeWorkspaceAfterDelete = try repository.deleteWorkspace(
            deletedWorkspaceId,
            updatedAt: Date(timeIntervalSince1970: 400)
        )

        #expect(activeWorkspaceAfterDelete == activeWorkspaceId)
        #expect(try repository.fetchActiveWorkspaceId() == activeWorkspaceId)
        #expect(try repository.fetchWorkspace(id: deletedWorkspaceId) == nil)
    }

    @Test("deleting workspace rejects dangling active selection without repairing it")
    func deletingWorkspaceRejectsDanglingActiveSelectionWithoutRepairingIt() throws {
        let fixture = try makeFixture()
        let repository = fixture.repository
        let deletedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000038")!
        let remainingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000039")!
        let danglingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let timestamp = Date(timeIntervalSince1970: 100)
        try repository.upsertWorkspace(
            .init(id: deletedWorkspaceId, name: "Delete Candidate", createdAt: timestamp, updatedAt: timestamp)
        )
        try repository.upsertWorkspace(
            .init(
                id: remainingWorkspaceId,
                name: "Remaining",
                createdAt: timestamp,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try setRawActiveWorkspaceSelection(danglingWorkspaceId.uuidString, in: fixture.databaseQueue)

        #expect(throws: WorkspaceCoreRepositoryError.activeWorkspaceSelectionDangling(danglingWorkspaceId)) {
            try repository.deleteWorkspace(deletedWorkspaceId, updatedAt: Date(timeIntervalSince1970: 300))
        }
        #expect(try rawActiveWorkspaceSelection(in: fixture.databaseQueue) == danglingWorkspaceId.uuidString)
        #expect(try repository.fetchWorkspace(id: deletedWorkspaceId) != nil)
        #expect(try repository.fetchWorkspace(id: remainingWorkspaceId) != nil)
    }

    @Test("deleting missing workspace rejects and preserves current selection")
    func deletingMissingWorkspaceRejectsAndPreservesCurrentSelection() throws {
        let repository = try makeFixture().repository
        let activeWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        let missingWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000034")!
        let timestamp = Date(timeIntervalSince1970: 100)
        try repository.upsertWorkspace(
            .init(id: activeWorkspaceId, name: "Active", createdAt: timestamp, updatedAt: timestamp)
        )
        try repository.selectActiveWorkspace(activeWorkspaceId, updatedAt: timestamp)

        #expect(throws: WorkspaceCoreRepositoryError.workspaceNotFound(missingWorkspaceId)) {
            try repository.deleteWorkspace(
                missingWorkspaceId,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        }
        #expect(try repository.fetchActiveWorkspaceId() == activeWorkspaceId)
    }

    @Test("deleting final workspace clears active workspace selection")
    func deletingFinalWorkspaceClearsActiveWorkspaceSelection() throws {
        let repository = try makeFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let timestamp = Date(timeIntervalSince1970: 100)
        try repository.upsertWorkspace(
            .init(id: workspaceId, name: "Only", createdAt: timestamp, updatedAt: timestamp)
        )
        try repository.selectActiveWorkspace(workspaceId, updatedAt: timestamp)

        let repairedWorkspaceId = try repository.deleteWorkspace(
            workspaceId,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(repairedWorkspaceId == nil)
        #expect(try repository.fetchActiveWorkspaceId() == nil)
        #expect(try repository.fetchWorkspace(id: workspaceId) == nil)
    }

    private func makeFixture() throws -> WorkspaceCoreRepositoryFixture {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        return .init(
            repository: WorkspaceCoreRepository(databaseWriter: databaseQueue),
            databaseQueue: databaseQueue
        )
    }
}

private struct WorkspaceCoreRepositoryFixture {
    let repository: WorkspaceCoreRepository
    let databaseQueue: DatabaseQueue
}

private func deleteActiveWorkspaceSelectionSingleton(in databaseQueue: DatabaseQueue) throws {
    try databaseQueue.write { database in
        try database.execute(
            sql: """
                DELETE FROM app_workspace_selection
                WHERE singleton_id = 1
                """
        )
    }
}

private func setRawActiveWorkspaceSelection(_ value: String, in databaseQueue: DatabaseQueue) throws {
    try databaseQueue.writeWithoutTransaction { database in
        try database.execute(sql: "PRAGMA foreign_keys = OFF")
        try database.execute(
            sql: """
                UPDATE app_workspace_selection
                SET active_workspace_id = ?
                WHERE singleton_id = 1
                """,
            arguments: [value]
        )
        try database.execute(sql: "PRAGMA foreign_keys = ON")
    }
}

private func rawActiveWorkspaceSelection(in databaseQueue: DatabaseQueue) throws -> String? {
    try databaseQueue.read { database in
        try String.fetchOne(
            database,
            sql: """
                SELECT active_workspace_id
                FROM app_workspace_selection
                WHERE singleton_id = 1
                """
        )
    }
}

private func activeWorkspaceSelectionSingletonCount(in databaseQueue: DatabaseQueue) throws -> Int {
    try databaseQueue.read { database in
        try Int.fetchOne(
            database,
            sql: """
                SELECT count(*)
                FROM app_workspace_selection
                WHERE singleton_id = 1
                """
        ) ?? 0
    }
}
