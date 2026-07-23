import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreRecoveryTests", .serialized)
struct WorkspaceSQLiteStoreRecoveryTests {
    @Test("failed core replacement rolls back core and leaves local rows unchanged")
    func failedCoreReplacementRollsBackCoreAndLeavesLocalRowsUnchanged() async throws {
        let workspaceId = UUIDv7.generate()
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
        let committedCursorState = try fixture.localRepository.fetchCursorState()
        let committedWindowState = try fixture.localRepository.fetchWindowState()
        let invalidPaneId = UUIDv7.generate()
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

        #expect(try fixture.localRepository.fetchCursorState() == committedCursorState)
        #expect(try fixture.localRepository.fetchWindowState() == committedWindowState)
        let loaded = try #require(try fixture.backend.load())
        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Committed Workspace")
        #expect(loaded.name != "Invalid Replacement")
        #expect(loaded.activeTabId == nil)
        #expect(loaded.sidebarWidth == 250)
    }

    @Test("independent local rows do not determine core snapshot authority")
    func independentLocalRowsDoNotDetermineCoreSnapshotAuthority() throws {
        let workspaceId = UUIDv7.generate()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        try fixture.backend.save(
            .emptyFixture(
                id: workspaceId,
                name: "Authoritative Core",
                sidebarWidth: 315,
                createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_310)
            )
        )
        try fixture.localRepository.replaceWindowState(
            .init(sidebarWidth: 430, windowFrame: nil),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400)
        )

        let loaded = try #require(try fixture.backend.load())

        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Authoritative Core")
        #expect(loaded.sidebarWidth == 430)
    }
}

private struct WorkspaceSQLiteRecoveryFixture {
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
        coreRepository: coreRepository,
        localRepository: localRepository,
        backend: backend
    )
}
