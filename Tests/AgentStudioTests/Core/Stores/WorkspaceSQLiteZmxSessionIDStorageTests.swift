import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace SQLite zmx session ID storage", .serialized)
struct WorkspaceSQLiteZmxSessionIDStorageTests {
    @Test("new zmx panes preserve their UUIDv7 identities through SQLite flush")
    func newZmxPanesPreserveUUIDv7IdentitiesThroughSQLiteFlush() async throws {
        let workspaceID = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        identityAtom.replaceIdentity(
            workspaceId: workspaceID,
            workspaceName: "UUIDv7 zmx workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_075)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-zmx-id-repo"))
        let worktree = try #require(repo.worktrees.first)
        let floatingDirectory = URL(filePath: "/tmp/agent-studio-zmx-id-floating")
        let worktreeSessionID = ZmxSessionID.generateUUIDv7()
        let floatingSessionID = ZmxSessionID.generateUUIDv7()
        let parentSessionID = ZmxSessionID.generateUUIDv7()
        let drawerSessionID = ZmxSessionID.generateUUIDv7()

        let worktreePane = store.createPane(
            launchDirectory: worktree.path,
            title: "Worktree terminal",
            provider: .zmx,
            zmxSessionID: worktreeSessionID,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let floatingPane = store.createPane(
            launchDirectory: floatingDirectory,
            title: "Floating terminal",
            provider: .zmx,
            zmxSessionID: floatingSessionID
        )
        let parentPane = store.createPane(
            launchDirectory: floatingDirectory,
            title: "Parent terminal",
            provider: .zmx,
            zmxSessionID: parentSessionID
        )
        store.appendTab(Tab(paneId: worktreePane.id, name: "Worktree"))
        store.appendTab(Tab(paneId: floatingPane.id, name: "Floating"))
        store.appendTab(Tab(paneId: parentPane.id, name: "Parent"))
        let drawerPane = try #require(
            store.addDrawerPane(
                to: parentPane.id,
                parentFallbackCWD: floatingDirectory,
                zmxSessionID: drawerSessionID
            )
        )

        #expect(store.pane(worktreePane.id)?.terminalState?.zmxSessionID == worktreeSessionID)
        #expect(store.pane(floatingPane.id)?.terminalState?.zmxSessionID == floatingSessionID)
        #expect(store.pane(drawerPane.id)?.terminalState?.zmxSessionID == drawerSessionID)
        #expect((await store.flushAsync()).succeeded)

        let storedPanes = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes
        let storedContentByPaneID = Dictionary(uniqueKeysWithValues: storedPanes.map { ($0.id, $0.content) })
        let storedWorktreeContent = try #require(storedContentByPaneID[worktreePane.id])
        let storedFloatingContent = try #require(storedContentByPaneID[floatingPane.id])
        let storedDrawerContent = try #require(storedContentByPaneID[drawerPane.id])
        guard case .terminal(_, _, let storedWorktreeSessionID) = storedWorktreeContent,
            case .terminal(_, _, let storedFloatingSessionID) = storedFloatingContent,
            case .terminal(_, _, let storedDrawerSessionID) = storedDrawerContent
        else {
            Issue.record("Expected terminal content records")
            return
        }
        #expect(storedWorktreeSessionID == worktreeSessionID)
        #expect(storedFloatingSessionID == floatingSessionID)
        #expect(storedDrawerSessionID == drawerSessionID)
    }
}
