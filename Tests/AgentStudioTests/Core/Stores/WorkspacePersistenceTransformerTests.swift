import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistenceTransformerTests {
    @Test
    func hydrate_restoresWorktreeBoundPaneWhenTopologyIsPresent() {
        let metadataAtom = WorkspaceMetadataAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        let repoId = UUID()
        let worktreeId = UUID()
        let canonicalRepo = CanonicalRepo(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )
        let canonicalWorktree = CanonicalWorktree(
            id: worktreeId,
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            isMainWorktree: true
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                source: .worktree(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    launchDirectory: URL(fileURLWithPath: "/tmp/agent-studio")
                ),
                title: "Restored"
            )
        )
        let tab = Tab(paneId: pane.id)
        let state = WorkspacePersistor.PersistableState(
            id: UUID(),
            repos: [canonicalRepo],
            worktrees: [canonicalWorktree],
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id
        )

        WorkspacePersistenceTransformer.hydrate(
            state,
            metadataAtom: metadataAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        #expect(topologyAtom.repo(repoId) != nil)
        #expect(paneAtom.pane(pane.id)?.worktreeId == worktreeId)
        #expect(tabLayoutAtom.tabs.count == 1)
        #expect(tabLayoutAtom.tabs[0].paneIds == [pane.id])
    }

    @Test
    func makePersistableState_prunesTemporaryPanesFromTabs() {
        let metadataAtom = WorkspaceMetadataAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        metadataAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000),
            sidebarWidth: 250,
            windowFrame: nil
        )

        let persistentPane = makePane(title: "Persistent")
        let temporaryPane = makePane(title: "Temporary", lifetime: .temporary)
        paneAtom.addPane(persistentPane)
        paneAtom.addPane(temporaryPane)
        let tab = makeTab(paneIds: [persistentPane.id, temporaryPane.id], activePaneId: temporaryPane.id)
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            metadataAtom: metadataAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.panes.map(\.id) == [persistentPane.id])
        #expect(state.tabs.count == 1)
        #expect(state.tabs[0].paneIds == [persistentPane.id])
        #expect(state.activeTabId == tab.id)
    }
}
