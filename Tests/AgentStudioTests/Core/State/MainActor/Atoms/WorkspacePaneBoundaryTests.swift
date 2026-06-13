import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane boundary split")
struct WorkspacePaneBoundaryTests {
    @Test("Pane graph state strips drawer expansion and display facets")
    func paneGraphStateStripsCursorAndDisplayFields() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/agent-studio"),
                title: "Terminal",
                facets: PaneContextFacets(
                    repoId: repoId,
                    repoName: "stale repo",
                    worktreeId: worktreeId,
                    worktreeName: "stale worktree",
                    cwd: URL(filePath: "/tmp/agent-studio/Sources"),
                    parentFolder: "stale parent",
                    organizationName: "stale org",
                    origin: "stale origin",
                    upstream: "stale upstream",
                    tags: ["swift"]
                ),
                note: "ship it"
            ),
            kind: .layout(drawer: Drawer(paneIds: [], isExpanded: true))
        )
        let graphAtom = WorkspacePaneGraphAtom()

        graphAtom.hydrate(persistedPanes: [pane], validWorktreeIds: [worktreeId])

        let state = try #require(graphAtom.paneState(pane.id))
        #expect(state.metadata.facets.repoId == repoId)
        #expect(state.metadata.facets.worktreeId == worktreeId)
        #expect(state.metadata.facets.cwd == URL(filePath: "/tmp/agent-studio/Sources"))
        #expect(state.metadata.facets.tags == ["swift"])
        #expect(state.metadata.facets.paneContextFacets.repoName == nil)
        #expect(state.metadata.facets.paneContextFacets.worktreeName == nil)
        #expect(state.metadata.facets.paneContextFacets.parentFolder == nil)
        #expect(state.metadata.facets.paneContextFacets.organizationName == nil)
        #expect(state.metadata.facets.paneContextFacets.origin == nil)
        #expect(state.metadata.facets.paneContextFacets.upstream == nil)
        #expect(state.drawer?.paneIds.isEmpty == true)
    }

    @Test("Pane graph projection preserves explicitly cleared live worktree facets")
    func paneGraphProjectionPreservesClearedLiveWorktreeFacets() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let graphAtom = WorkspacePaneGraphAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom)
        let pane = paneAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/project"),
            facets: PaneContextFacets(
                repoId: repoId,
                worktreeId: worktreeId,
                cwd: URL(filePath: "/tmp/project")
            )
        )

        let result = paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: URL(filePath: "/tmp/outside-project"),
            resolvedContext: nil
        )
        let projectedPane = try #require(paneAtom.pane(pane.id))

        #expect(result == .applied)
        #expect(projectedPane.metadata.cwd == URL(filePath: "/tmp/outside-project"))
        #expect(projectedPane.repoId == nil)
        #expect(projectedPane.worktreeId == nil)
    }

    @Test("Setting identical zmx session anchor is a no-op")
    func settingIdenticalZmxSessionAnchorIsNoOp() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom)
        let pane = paneAtom.createPane()
        let sessionId = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: pane.id
        )

        let firstUpdateChangedState = paneAtom.setTerminalZmxSessionId(pane.id, sessionId: sessionId)
        let secondUpdateChangedState = paneAtom.setTerminalZmxSessionId(pane.id, sessionId: sessionId)

        #expect(firstUpdateChangedState)
        #expect(!secondUpdateChangedState)
        guard case .terminal(let terminalState) = graphAtom.paneState(pane.id)?.content else {
            Issue.record("Expected pane content to remain terminal")
            return
        }
        #expect(terminalState.zmxSessionId == sessionId)
    }

    @Test("Drawer cursor owns expansion and derived panes reflect it atomically")
    func drawerCursorOwnsExpansionAndDerivedPaneReflectsIt() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom, drawerCursorAtom: drawerCursorAtom)
        let derived = WorkspacePaneDerived(graphAtom: graphAtom, drawerCursorAtom: drawerCursorAtom)
        let firstPane = paneAtom.createPane()
        let secondPane = paneAtom.createPane()
        let firstDrawerId = try #require(graphAtom.paneState(firstPane.id)?.drawer?.drawerId)
        let secondDrawerId = try #require(graphAtom.paneState(secondPane.id)?.drawer?.drawerId)

        paneAtom.toggleDrawer(for: firstPane.id)
        paneAtom.toggleDrawer(for: secondPane.id)

        #expect(drawerCursorAtom.isExpanded(drawerId: firstDrawerId) == false)
        #expect(drawerCursorAtom.isExpanded(drawerId: secondDrawerId) == true)
        #expect(derived.pane(firstPane.id)?.drawer?.isExpanded == false)
        #expect(derived.pane(secondPane.id)?.drawer?.isExpanded == true)
    }

    @Test("Pane derived model composes display facets from topology and cache")
    func paneDerivedComposesDisplayFacetsFromTopologyAndCache() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "sqlite")
        let repo = Repo(id: repoId, name: "agent-studio", repoPath: repoPath)
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "sqlite",
            path: worktreePath,
            isMainWorktree: false
        )
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        topologyAtom.hydrate(
            runtimeRepos: [
                Repo(id: repo.id, name: repo.name, repoPath: repo.repoPath, worktrees: [worktree])
            ],
            watchedPaths: [],
            unavailableRepoIds: []
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        cacheAtom.setRepoEnrichment(
            .resolvedRemote(
                repoId: repoId,
                raw: RawRepoOrigin(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: "origin/main"),
                identity: RepoIdentity(
                    groupKey: "ShravanSunder",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom, drawerCursorAtom: drawerCursorAtom)
        let derived = WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom,
            repoEnrichmentCacheAtom: cacheAtom
        )
        let pane = paneAtom.createPane(
            launchDirectory: worktreePath,
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: "stale repo",
                worktreeId: worktreeId,
                worktreeName: "stale worktree",
                cwd: worktreePath.appending(path: "Sources"),
                parentFolder: "stale parent",
                organizationName: "stale org",
                origin: "stale origin",
                upstream: "stale upstream"
            )
        )

        let derivedPane = try #require(derived.pane(pane.id))

        #expect(derivedPane.metadata.facets.repoName == "agent-studio")
        #expect(derivedPane.metadata.facets.worktreeName == "sqlite")
        #expect(derivedPane.metadata.facets.parentFolder == "project-dev")
        #expect(derivedPane.metadata.facets.organizationName == "ShravanSunder")
        #expect(derivedPane.metadata.facets.origin == "git@github.com:ShravanSunder/agentstudio.git")
        #expect(derivedPane.metadata.facets.upstream == "origin/main")
    }

    @Test("Pane derived worktree lookup uses composed topology context")
    func paneDerivedWorktreeLookupUsesComposedTopologyContext() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "sqlite")
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "sqlite",
            path: worktreePath,
            isMainWorktree: false
        )
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        topologyAtom.hydrate(
            runtimeRepos: [
                Repo(id: repoId, name: "agent-studio", repoPath: repoPath, worktrees: [worktree])
            ],
            watchedPaths: [],
            unavailableRepoIds: []
        )
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom, drawerCursorAtom: drawerCursorAtom)
        let derived = WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom
        )
        let pane = paneAtom.createPane(
            launchDirectory: worktreePath,
            facets: PaneContextFacets(cwd: worktreePath.appending(path: "Sources"))
        )

        let worktreePanes = derived.panes(for: worktreeId)

        #expect(worktreePanes.map(\.id) == [pane.id])
        #expect(worktreePanes.first?.repoId == repoId)
        #expect(worktreePanes.first?.worktreeId == worktreeId)
    }
}
