import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Workspace topology context persistence", .serialized)
struct WorkspaceTopologyContextPersistenceTests {
    @Test("a pre-hide workspace capture cannot restore context after the same IDs return")
    func preHideCaptureClearsStaleContextAfterSameIDReturn() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "workspace-topology-context-\(UUIDv7.generate())"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: root.appending(path: "core.sqlite"),
            localDatabaseURL: root.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected prepared persistence fixture")
            return
        }
        _ = await datastore.loadAuthoritativeCoreSnapshot()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let repositoryPath = root.appending(path: "repository")
        let availableTopology = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "repository",
                    repoPath: repositoryPath,
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: repositoryPath,
                    isMainWorktree: true
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try await datastore.saveRepositoryTopologySnapshot(availableTopology, captureRevision: 1)
        let paneID = UUIDv7.generate()
        let pane = makePane(
            id: paneID,
            launchDirectory: repositoryPath,
            title: "captured before hide",
            facets: .init(repoId: repositoryID, worktreeId: worktreeID, cwd: repositoryPath)
        )
        let tab = Tab(paneId: paneID, name: "retained tab")
        let preHideCapture = WorkspaceSQLiteSaveBundle(
            workspace: .init(
                id: UUIDv7.generate(),
                name: "retained workspace",
                panes: [pane],
                tabs: [tab],
                activeTabId: tab.id,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 101)
            ),
            captureRevision: .init(
                panes: 1,
                tabShells: 1,
                tabGraphs: 1,
                topologyContextRevision: 1
            )
        )
        try await datastore.saveWorkspaceSnapshotBundle(preHideCapture)
        let absence = RepositoryLocationAbsence.unconfirmed
        let hiddenTopology = RepositoryTopologySQLiteSnapshot(
            repos: availableTopology.repos,
            worktrees: availableTopology.worktrees,
            unavailableRepoIds: [repositoryID],
            watchedPaths: availableTopology.watchedPaths,
            watchedPathStableKeysByID: availableTopology.watchedPathStableKeysByID,
            updatedAt: Date(timeIntervalSince1970: 102),
            absenceRecords: .init(
                repositories: [repositoryID: absence],
                worktrees: [worktreeID: absence]
            )
        )
        try await datastore.saveRepositoryTopologySnapshot(hiddenTopology, captureRevision: 2)
        try await datastore.saveRepositoryTopologySnapshot(availableTopology, captureRevision: 3)

        try await datastore.saveWorkspaceSnapshotBundle(preHideCapture)

        guard case .loaded(let loaded) = await datastore.loadAuthoritativeCoreSnapshot() else {
            Issue.record("expected workspace readback")
            return
        }
        let persistedPane = try #require(loaded.workspace.panes.first { $0.id == paneID })
        #expect(persistedPane.metadata.title == "captured before hide")
        #expect(persistedPane.metadata.repoId == nil)
        #expect(persistedPane.metadata.worktreeId == nil)
        #expect(persistedPane.metadata.cwd?.standardizedFileURL.path == repositoryPath.standardizedFileURL.path)
        #expect(loaded.workspace.tabs.contains { $0.id == tab.id })
    }
}
