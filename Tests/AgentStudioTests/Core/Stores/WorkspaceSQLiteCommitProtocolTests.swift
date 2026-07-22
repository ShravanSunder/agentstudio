import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteCommitProtocolTests", .serialized)
struct WorkspaceSQLiteCommitProtocolTests {
    @Test("failed composition replacement rolls back to the prior authoritative core snapshot")
    func failedCompositionReplacementRollsBackToPriorAuthoritativeCoreSnapshot() throws {
        // Arrange
        let workspaceId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.commit.atomic-rollback.core"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let originalPane = makePane(id: paneId, title: "Original Pane")
        let originalTab = Tab(paneId: paneId, name: "Original Tab")
        let originalSnapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Original Workspace",
            panes: [originalPane],
            tabs: [originalTab],
            activeTabId: originalTab.id,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try replaceCoreComposition(originalSnapshot, in: coreRepository)
        let authoritativeSnapshotBeforeFailure = try requireLoadedAuthoritativeSnapshot(coreRepository)
        let missingPaneId = UUIDv7.generate()
        let invalidTab = Tab(paneId: missingPaneId, name: "Missing Pane Tab")
        let invalidSnapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Partially Applied Workspace",
            panes: [originalPane],
            tabs: [invalidTab],
            activeTabId: invalidTab.id,
            createdAt: originalSnapshot.createdAt,
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        // Act
        #expect(
            throws: WorkspaceCoreRepositoryError.paneNotFoundInWorkspace(missingPaneId, workspaceId)
        ) {
            try replaceCoreComposition(invalidSnapshot, in: coreRepository)
        }

        // Assert
        let authoritativeSnapshotAfterFailure = try requireLoadedAuthoritativeSnapshot(coreRepository)
        #expect(authoritativeSnapshotAfterFailure == authoritativeSnapshotBeforeFailure)
        #expect(authoritativeSnapshotAfterFailure.workspace.name == "Original Workspace")
        #expect(authoritativeSnapshotAfterFailure.paneGraph.panes.map(\.id) == [paneId])
        #expect(authoritativeSnapshotAfterFailure.tabShells.map(\.id) == [originalTab.id])
    }

    @Test("core commit remains authoritative after the subsequent local write fails")
    func coreCommitRemainsAuthoritativeAfterSubsequentLocalWriteFails() throws {
        // Arrange
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.commit.local-failure.core"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.commit.local-failure.local"
        )
        try WorkspaceLocalMigrations.migrate(localQueue)
        try localQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER force_local_cursor_write_failure
                    BEFORE INSERT ON local_workspace_cursor
                    BEGIN
                        SELECT RAISE(ABORT, 'forced local cursor write failure');
                    END
                    """
            )
        }
        let backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            }
        )
        let bundle = WorkspaceSQLiteSaveBundle.emptyTopologyFixture(
            workspace: .emptyFixture(
                id: workspaceId,
                name: "Core Commit Survives",
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )

        // Act
        #expect(throws: DatabaseError.self) {
            try backend.save(bundle)
        }

        // Assert
        let authoritativeSnapshot = try requireLoadedAuthoritativeSnapshot(coreRepository)
        #expect(authoritativeSnapshot.workspace.id == workspaceId)
        #expect(authoritativeSnapshot.workspace.name == "Core Commit Survives")
        #expect(authoritativeSnapshot.paneGraph.panes.isEmpty)
        #expect(authoritativeSnapshot.tabShells.isEmpty)
        #expect(authoritativeSnapshot.tabGraph.tabs.isEmpty)
    }

    @Test("authoritative read returns one coherent workspace topology pane and tab snapshot")
    func authoritativeReadReturnsOneCoherentCoreSnapshot() throws {
        // Arrange
        let workspaceId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.commit.coherent-read.core"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [
                .init(
                    id: UUIDv7.generate(),
                    path: URL(fileURLWithPath: "/tmp/agentstudio/coherent-read"),
                    addedAt: Date(timeIntervalSince1970: 5)
                )
            ],
            repos: [
                .init(
                    id: repoId,
                    name: "coherent-repo",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/coherent-read/repo"),
                    createdAt: Date(timeIntervalSince1970: 6),
                    worktrees: [
                        .init(
                            id: worktreeId,
                            repoId: repoId,
                            name: "main",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/coherent-read/repo"),
                            isMainWorktree: true
                        )
                    ]
                )
            ],
            unavailableRepoIds: []
        )
        try coreRepository.replaceRepositoryTopology(topology)
        let pane = makePane(id: paneId, title: "Coherent Pane")
        let tab = Tab(paneId: paneId, name: "Coherent Tab")
        let workspaceSnapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Coherent Workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 7),
            updatedAt: Date(timeIntervalSince1970: 8)
        )
        try replaceCoreComposition(workspaceSnapshot, in: coreRepository)

        // Act
        let authoritativeSnapshot = try requireLoadedAuthoritativeSnapshot(coreRepository)
        let expectedPaneGraph = try WorkspaceSQLiteStateBridge.paneGraphRecord(from: workspaceSnapshot)

        // Assert
        #expect(authoritativeSnapshot.workspace == WorkspaceSQLiteStateBridge.workspaceRecord(from: workspaceSnapshot))
        #expect(authoritativeSnapshot.topology == topology)
        #expect(authoritativeSnapshot.paneGraph.panes.count == expectedPaneGraph.panes.count)
        let persistedPane = try #require(authoritativeSnapshot.paneGraph.panes.single)
        let expectedPane = try #require(expectedPaneGraph.panes.single)
        #expect(persistedPane.id == expectedPane.id)
        #expect(persistedPane.content == expectedPane.content)
        #expect(persistedPane.metadata.launchDirectory == expectedPane.metadata.launchDirectory)
        #expect(persistedPane.metadata.executionBackend == expectedPane.metadata.executionBackend)
        #expect(persistedPane.metadata.title == expectedPane.metadata.title)
        #expect(persistedPane.metadata.note == expectedPane.metadata.note)
        #expect(persistedPane.metadata.checkoutRef == expectedPane.metadata.checkoutRef)
        #expect(persistedPane.metadata.durableFacets == expectedPane.metadata.durableFacets)
        #expect(
            abs(
                persistedPane.metadata.createdAt.timeIntervalSince1970
                    - expectedPane.metadata.createdAt.timeIntervalSince1970
            ) < 0.000001
        )
        #expect(persistedPane.residency == expectedPane.residency)
        #expect(persistedPane.placement == expectedPane.placement)
        #expect(persistedPane.drawer == expectedPane.drawer)
        #expect(
            abs(
                persistedPane.updatedAt.timeIntervalSince1970
                    - expectedPane.updatedAt.timeIntervalSince1970
            ) < 0.000001
        )
        #expect(authoritativeSnapshot.tabShells == WorkspaceSQLiteStateBridge.tabShellRecords(from: workspaceSnapshot))
        #expect(authoritativeSnapshot.tabGraph == WorkspaceSQLiteStateBridge.tabGraphRecord(from: workspaceSnapshot))
    }

    @Test("authoritative read remains on one generation while a writer commits")
    func authoritativeReadRemainsOnOneGenerationWhileWriterCommits() async throws {
        // Arrange
        let fixture = try makeConcurrentAuthoritativeReadFixture()
        defer {
            try? fixture.corePool.close()
            try? FileManager.default.removeItem(at: fixture.databaseDirectory)
        }
        let oldGeneration = try requireLoadedAuthoritativeSnapshot(fixture.coreRepository)
        fixture.readBarrier.arm()

        // Act
        // A detached reader is required so its test barrier does not block the MainActor writer.
        // swiftlint:disable:next no_task_detached
        let concurrentRead = Task.detached {
            try fixture.coreRepository.fetchAuthoritativeSnapshot()
        }
        guard fixture.readBarrier.waitUntilReaderIsPaused() else {
            fixture.readBarrier.resumeReader()
            Issue.record("Authoritative read did not reach the topology barrier")
            _ = try await concurrentRead.value
            return
        }
        do {
            try await updateConcurrentAuthoritativeReadFixture(fixture)
        } catch {
            fixture.readBarrier.resumeReader()
            throw error
        }
        fixture.readBarrier.resumeReader()
        let generationObservedDuringCommit = try requireLoadedAuthoritativeSnapshot(
            try await concurrentRead.value
        )
        let newGeneration = try requireLoadedAuthoritativeSnapshot(fixture.coreRepository)

        // Assert
        #expect(!fixture.readBarrier.didTimeOutWaitingForResume)
        #expect(generationObservedDuringCommit == oldGeneration)
        #expect(newGeneration.workspace.name == "New Workspace")
        #expect(newGeneration.topology.repos.single?.name == "New Repo")
        #expect(newGeneration.paneGraph.panes.single?.metadata.title == "New Pane")
        #expect(newGeneration.tabShells.single?.name == "New Tab")
    }
}

private struct ConcurrentAuthoritativeReadFixture: Sendable {
    let databaseDirectory: URL
    let corePool: DatabasePool
    let coreRepository: WorkspaceCoreRepository
    let readBarrier: AuthoritativeReadBarrier
    let workspaceId: UUID
    let repoId: UUID
    let paneId: UUID
    let tabId: UUID
}

@MainActor
private func makeConcurrentAuthoritativeReadFixture() throws -> ConcurrentAuthoritativeReadFixture {
    let databaseDirectory = FileManager.default.temporaryDirectory.appending(
        path: "agentstudio-authoritative-read-\(UUIDv7.generate().uuidString)"
    )
    try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
    let readBarrier = AuthoritativeReadBarrier()
    var configuration = SQLiteDatabaseFactory.makeConfiguration(
        label: "AgentStudio.sqlite.commit.concurrent-read.core"
    )
    configuration.journalMode = .wal
    configuration.prepareDatabase { database in
        database.trace { event in
            readBarrier.pauseAtFirstTopologyRead(event)
        }
    }
    let corePool = try DatabasePool(
        path: databaseDirectory.appending(path: "core.sqlite").path,
        configuration: configuration
    )
    try WorkspaceCoreMigrations.migrate(corePool)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: corePool)
    let workspaceId = UUIDv7.generate()
    let repoId = UUIDv7.generate()
    let paneId = UUIDv7.generate()
    let tab = Tab(paneId: paneId, name: "Old Tab")
    try seedConcurrentAuthoritativeReadTopology(repoId: repoId, in: coreRepository)
    try replaceCoreComposition(
        .init(
            id: workspaceId,
            name: "Old Workspace",
            panes: [makePane(id: paneId, title: "Old Pane")],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 7),
            updatedAt: Date(timeIntervalSince1970: 8)
        ),
        in: coreRepository
    )
    return .init(
        databaseDirectory: databaseDirectory,
        corePool: corePool,
        coreRepository: coreRepository,
        readBarrier: readBarrier,
        workspaceId: workspaceId,
        repoId: repoId,
        paneId: paneId,
        tabId: tab.id
    )
}

private func seedConcurrentAuthoritativeReadTopology(
    repoId: UUID,
    in coreRepository: WorkspaceCoreRepository
) throws {
    let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio/concurrent-read/repo")
    try coreRepository.replaceRepositoryTopology(
        .init(
            watchedPaths: [
                .init(
                    id: UUIDv7.generate(),
                    path: URL(fileURLWithPath: "/tmp/agentstudio/concurrent-read"),
                    addedAt: Date(timeIntervalSince1970: 5)
                )
            ],
            repos: [
                .init(
                    id: repoId,
                    name: "Old Repo",
                    repoPath: repositoryPath,
                    createdAt: Date(timeIntervalSince1970: 6),
                    worktrees: [
                        .init(
                            id: UUIDv7.generate(),
                            repoId: repoId,
                            name: "main",
                            path: repositoryPath,
                            isMainWorktree: true
                        )
                    ]
                )
            ],
            unavailableRepoIds: []
        )
    )
}

private func updateConcurrentAuthoritativeReadFixture(
    _ fixture: ConcurrentAuthoritativeReadFixture
) async throws {
    try await fixture.corePool.write { database in
        try database.execute(
            sql: "UPDATE workspace SET name = ? WHERE id = ?",
            arguments: ["New Workspace", fixture.workspaceId.uuidString]
        )
        try database.execute(
            sql: "UPDATE repo SET name = ? WHERE id = ?",
            arguments: ["New Repo", fixture.repoId.uuidString]
        )
        try database.execute(
            sql: "UPDATE pane SET title = ? WHERE id = ?",
            arguments: ["New Pane", fixture.paneId.uuidString]
        )
        try database.execute(
            sql: "UPDATE tab_shell SET name = ? WHERE id = ?",
            arguments: ["New Tab", fixture.tabId.uuidString]
        )
    }
}

@MainActor
private func replaceCoreComposition(
    _ snapshot: WorkspaceSQLiteSnapshot,
    in coreRepository: WorkspaceCoreRepository
) throws {
    try coreRepository.replaceWorkspaceSnapshot(
        workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: snapshot),
        paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: snapshot),
        tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: snapshot),
        tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: snapshot)
    )
}

private func requireLoadedAuthoritativeSnapshot(
    _ coreRepository: WorkspaceCoreRepository
) throws -> WorkspaceCoreRepository.AuthoritativeSnapshot {
    try requireLoadedAuthoritativeSnapshot(coreRepository.fetchAuthoritativeSnapshot())
}

private func requireLoadedAuthoritativeSnapshot(
    _ read: WorkspaceCoreRepository.AuthoritativeSnapshotRead
) throws -> WorkspaceCoreRepository.AuthoritativeSnapshot {
    switch read {
    case .loaded(let snapshot):
        return snapshot
    case .noWorkspaces:
        Issue.record("Expected an authoritative snapshot, found no workspaces")
    case .missingActiveSelection:
        Issue.record("Expected an authoritative snapshot, found no active selection")
    }
    throw AuthoritativeSnapshotTestError.notLoaded
}

private enum AuthoritativeSnapshotTestError: Error {
    case notLoaded
}

private final class AuthoritativeReadBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let readerPaused = DispatchSemaphore(value: 0)
    private let readerResume = DispatchSemaphore(value: 0)
    private var isArmed = false
    private var hasPaused = false
    private var resumeTimedOut = false

    var didTimeOutWaitingForResume: Bool {
        lock.withLock { resumeTimedOut }
    }

    func arm() {
        lock.withLock {
            isArmed = true
        }
    }

    func pauseAtFirstTopologyRead(_ event: Database.TraceEvent) {
        guard case .statement(let statement) = event,
            statement.sql.contains("FROM watched_path")
        else {
            return
        }
        let shouldPause = lock.withLock {
            guard isArmed, !hasPaused else { return false }
            hasPaused = true
            return true
        }
        guard shouldPause else { return }

        readerPaused.signal()
        if readerResume.wait(timeout: .now() + 5) == .timedOut {
            lock.withLock {
                resumeTimedOut = true
            }
        }
    }

    func waitUntilReaderIsPaused() -> Bool {
        readerPaused.wait(timeout: .now() + 5) == .success
    }

    func resumeReader() {
        readerResume.signal()
    }
}
