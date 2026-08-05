import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace duplicate-root boot continuity", .serialized)
struct WorkspaceDuplicateRootBootContinuityTests {
    @Test("ambiguous canonical roots load, persist degradation, and reload without pane loss")
    func ambiguousCanonicalRootsPersistCleanedDegradation() async throws {
        // Arrange
        let fixture = try await DuplicateRootBootContinuityFixture.make()
        defer { fixture.removeTemporaryFiles() }
        var firstLoadReasons: [PaneTopologyPersistenceReason] = []
        let firstDatastore = fixture.makeDatastore()

        // Act
        guard case .prepared = await firstDatastore.prepareDatabasesForBoot() else {
            Issue.record("expected duplicate-root recovery fixture to prepare")
            return
        }
        let firstTopologyAtom = RepositoryTopologyAtom()
        let firstStore = WorkspaceStore(
            repositoryTopologyAtom: firstTopologyAtom,
            sqliteDatastore: firstDatastore,
            persistenceReasonReporter: { reason in
                firstLoadReasons.append(reason)
            },
            startsObserving: false
        )
        guard case .loaded = await firstStore.loadCanonicalComposition() else {
            Issue.record("expected duplicate-root recovery fixture to load")
            return
        }

        // Assert
        try fixture.assertLoadedComposition(in: firstStore)
        try fixture.assertCleanedDegradedTopology(in: firstTopologyAtom)
        #expect(firstLoadReasons.count(where: { $0 == .paneTopologyAssociationAmbiguous }) == 1)
        #expect(firstLoadReasons.count(where: { $0 == .topologyRestoreMissingMainDegraded }) == 1)

        // Act: persist the normalized topology through the production owner, then reload fresh.
        let topologyStore = RepositoryTopologyStore(
            atom: firstTopologyAtom,
            sqliteDatastore: firstDatastore
        )
        topologyStore.startObserving()
        try await topologyStore.flushAsync()

        var reloadReasons: [PaneTopologyPersistenceReason] = []
        let reloadedDatastore = fixture.makeDatastore()
        guard case .prepared = await reloadedDatastore.prepareDatabasesForBoot() else {
            Issue.record("expected cleaned duplicate-root fixture to prepare on reload")
            return
        }
        let reloadedTopologyAtom = RepositoryTopologyAtom()
        let reloadedStore = WorkspaceStore(
            repositoryTopologyAtom: reloadedTopologyAtom,
            sqliteDatastore: reloadedDatastore,
            persistenceReasonReporter: { reason in
                reloadReasons.append(reason)
            },
            startsObserving: false
        )
        guard case .loaded = await reloadedStore.loadCanonicalComposition() else {
            Issue.record("expected cleaned duplicate-root fixture to load on reload")
            return
        }

        // Assert: the ambiguity was removed durably rather than reconsidered on every launch.
        try fixture.assertLoadedComposition(in: reloadedStore)
        try fixture.assertCleanedDegradedTopology(in: reloadedTopologyAtom)
        #expect(!reloadReasons.contains(.paneTopologyAssociationAmbiguous))
        #expect(reloadReasons.count(where: { $0 == .topologyRestoreMissingMainDegraded }) == 1)
    }
}

@MainActor
private struct DuplicateRootBootContinuityFixture {
    let rootDirectory: URL
    let coreDatabaseURL: URL
    let localDatabaseURL: URL
    let workspace: WorkspaceSQLiteSnapshot
    let repositoryID: UUID
    let firstAmbiguousRootID: UUID
    let secondAmbiguousRootID: UUID
    let linkedWorktreeID: UUID
    let repositoryPath: URL
    let repositoryAliasPath: URL
    let linkedWorktreePath: URL

    static func make() async throws -> Self {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-duplicate-root-continuity-\(UUIDv7.generate().uuidString)"
        )
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        let repositoryPath = rootDirectory.appending(path: "repository")
        let repositoryAliasPath = rootDirectory.appending(path: "repository-alias")
        let linkedWorktreePath = rootDirectory.appending(path: "linked-worktree")
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: repositoryAliasPath,
            withDestinationURL: repositoryPath
        )
        let fixture = Self(
            rootDirectory: rootDirectory,
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL,
            workspace: makeWorkspace(linkedWorktreePath: linkedWorktreePath),
            repositoryID: UUIDv7.generate(),
            firstAmbiguousRootID: UUIDv7.generate(),
            secondAmbiguousRootID: UUIDv7.generate(),
            linkedWorktreeID: UUIDv7.generate(),
            repositoryPath: repositoryPath,
            repositoryAliasPath: repositoryAliasPath,
            linkedWorktreePath: linkedWorktreePath
        )
        let seedDatastore = fixture.makeDatastore()
        guard case .prepared = await seedDatastore.prepareDatabasesForBoot() else {
            Issue.record("expected duplicate-root seed databases to prepare")
            return fixture
        }
        try await seedDatastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(workspace: fixture.workspace)
        )
        try fixture.insertHistoricalDuplicateRoots()
        return fixture
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
    }

    func assertLoadedComposition(in store: WorkspaceStore) throws {
        #expect(store.workspaceId == workspace.id)
        #expect(store.workspaceName == workspace.name)
        #expect(store.panes == Dictionary(uniqueKeysWithValues: workspace.panes.map { ($0.id, $0) }))
        #expect(store.tabs == workspace.tabs)
        #expect(store.activeTabId == workspace.activeTabId)
    }

    func assertCleanedDegradedTopology(in atom: RepositoryTopologyAtom) throws {
        let repository = try #require(atom.repos.single)
        let linkedWorktree = try #require(repository.worktrees.single)
        #expect(repository.id == repositoryID)
        #expect(atom.isRepoUnavailable(repositoryID))
        #expect(linkedWorktree.id == linkedWorktreeID)
        #expect(linkedWorktree.path == linkedWorktreePath.standardizedFileURL)
        #expect(linkedWorktree.note == "linked note survives")
        #expect(!linkedWorktree.isMainWorktree)
        #expect(atom.worktree(firstAmbiguousRootID) == nil)
        #expect(atom.worktree(secondAmbiguousRootID) == nil)
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    private static func makeWorkspace(linkedWorktreePath: URL) -> WorkspaceSQLiteSnapshot {
        let paneID = UUIDv7.generate()
        let pane = Pane(
            id: paneID,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: linkedWorktreePath.appending(
                    path: "Sources",
                    directoryHint: .isDirectory
                ),
                createdAt: Date(timeIntervalSince1970: 1_700_200_000),
                title: "Persisted linked pane",
                note: "pane note survives"
            )
        )
        let tab = Tab(paneId: paneID, name: "Persisted topology tab")
        return WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Duplicate-root continuity workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 318,
            createdAt: Date(timeIntervalSince1970: 1_700_200_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_200_001)
        )
    }

    private func insertHistoricalDuplicateRoots() throws {
        let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.duplicate-root-continuity"
        )
        defer { try? databasePool.close() }
        try databasePool.write { database in
            try database.execute(
                sql: """
                    INSERT INTO repo(id, name, repo_path, stable_key, created_at, is_favorite, note)
                    VALUES (?, ?, ?, ?, ?, 0, ?)
                    """,
                arguments: [
                    repositoryID.uuidString,
                    repositoryPath.lastPathComponent,
                    repositoryPath.path,
                    "historical-repository-stable-key",
                    1_700_200_002.0,
                    "repository note survives",
                ]
            )
            for (worktreeID, name, path, storedStableKey, isMainWorktree, note) in [
                (
                    firstAmbiguousRootID,
                    "root-one",
                    repositoryPath,
                    "historical-root-one-stable-key",
                    true,
                    "ambiguous root one"
                ),
                (
                    secondAmbiguousRootID,
                    "root-two",
                    repositoryAliasPath,
                    "historical-root-two-stable-key",
                    false,
                    "ambiguous root two"
                ),
                (
                    linkedWorktreeID,
                    "linked",
                    linkedWorktreePath,
                    "historical-linked-stable-key",
                    false,
                    "linked note survives"
                ),
            ] {
                try database.execute(
                    sql: """
                        INSERT INTO worktree(
                            id, repo_id, name, path, stable_key, is_main_worktree, note
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        worktreeID.uuidString,
                        repositoryID.uuidString,
                        name,
                        path.path,
                        storedStableKey,
                        isMainWorktree ? 1 : 0,
                        note,
                    ]
                )
            }
        }
    }
}
