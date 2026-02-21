import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class DynamicViewProjectorTests {

    // MARK: - Helpers

    private func makeTestPanes() -> (panes: [UUID: Pane], repos: [Repo], tabs: [Tab]) {
        let repoA = makeRepo(name: "agent-studio", repoPath: "/Users/dev/projects/agent-studio")
        let repoB = makeRepo(name: "askluna", repoPath: "/Users/dev/projects/askluna")

        let wtA1 = makeWorktree(name: "main", path: "/Users/dev/projects/agent-studio/main")
        let wtA2 = makeWorktree(name: "feature-x", path: "/Users/dev/projects/agent-studio/feature-x")
        let wtB1 = makeWorktree(name: "main", path: "/Users/dev/projects/askluna/main")

        var repoAWithWTs = repoA
        repoAWithWTs = Repo(
            id: repoA.id, name: repoA.name, repoPath: repoA.repoPath, worktrees: [wtA1, wtA2],
            createdAt: repoA.createdAt, updatedAt: repoA.updatedAt)
        var repoBWithWTs = repoB
        repoBWithWTs = Repo(
            id: repoB.id, name: repoB.name, repoPath: repoB.repoPath, worktrees: [wtB1], createdAt: repoB.createdAt,
            updatedAt: repoB.updatedAt)

        let pane1 = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                source: .worktree(worktreeId: wtA1.id, repoId: repoA.id),
                title: "agent-studio main",
                cwd: URL(fileURLWithPath: "/Users/dev/projects/agent-studio/main"),
                agentType: .claude
            )
        )
        let pane2 = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                source: .worktree(worktreeId: wtA2.id, repoId: repoA.id),
                title: "agent-studio feature-x",
                cwd: URL(fileURLWithPath: "/Users/dev/projects/agent-studio/feature-x"),
                agentType: .codex
            )
        )
        let pane3 = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                source: .worktree(worktreeId: wtB1.id, repoId: repoB.id),
                title: "askluna main",
                cwd: URL(fileURLWithPath: "/Users/dev/projects/askluna/main"),
                agentType: .claude
            )
        )
        let pane4 = Pane(
            content: .webview(WebviewState(url: URL(string: "https://docs.example.com")!, showNavigation: true)),
            metadata: PaneMetadata(
                source: .floating(workingDirectory: nil, title: "Docs"),
                title: "Docs"
            )
        )

        let panes: [UUID: Pane] = [
            pane1.id: pane1,
            pane2.id: pane2,
            pane3.id: pane3,
            pane4.id: pane4,
        ]

        // Two tabs: tab1 has pane1+pane2, tab2 has pane3+pane4
        let tab1 = makeTab(paneIds: [pane1.id, pane2.id])
        let tab2 = makeTab(paneIds: [pane3.id, pane4.id])

        return (panes: panes, repos: [repoAWithWTs, repoBWithWTs], tabs: [tab1, tab2])
    }

    // MARK: - By Repo

    @Test

    func test_byRepo_groupsByRepository() {
        let (panes, repos, tabs) = makeTestPanes()
        let paneList = Array(panes.values)
        let agentStudioPanes = paneList.filter { $0.repoId == repos[0].id }
        let asklunaPanes = paneList.filter { $0.repoId == repos[1].id }

        let result = DynamicViewProjector.project(
            viewType: .byRepo, panes: panes, tabs: tabs, repos: repos
        )

        #expect(result.viewType == .byRepo)
        // 3 groups: agent-studio, askluna, floating
        #expect(result.groups.count == 3)

        let repoNames = Set(result.groups.map(\.name))
        #expect(repoNames.contains("agent-studio"))
        #expect(repoNames.contains("askluna"))
        #expect(repoNames.contains("Floating"))

        // agent-studio has 2 panes
        let agentStudioGroup = result.groups.first { $0.name == "agent-studio" }!
        #expect(agentStudioGroup.paneIds.count == 2)
        #expect(Set(agentStudioGroup.paneIds) == Set(agentStudioPanes.map(\.id)))

        // askluna has 1 pane
        let asklunaGroup = result.groups.first { $0.name == "askluna" }!
        #expect(asklunaGroup.paneIds.count == 1)
        #expect(Set(asklunaGroup.paneIds) == Set(asklunaPanes.map(\.id)))
    }

    @Test

    func test_byRepo_sortedAlphabetically() {
        let (panes, repos, tabs) = makeTestPanes()

        let result = DynamicViewProjector.project(
            viewType: .byRepo, panes: panes, tabs: tabs, repos: repos
        )

        let names = result.groups.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - By Worktree

    @Test

    func test_byWorktree_groupsByWorktree() {
        let (panes, repos, tabs) = makeTestPanes()

        let result = DynamicViewProjector.project(
            viewType: .byWorktree, panes: panes, tabs: tabs, repos: repos
        )

        // 3 worktrees + 1 floating
        #expect(result.groups.count == 4)

        let groupNames = Set(result.groups.map(\.name))
        #expect(groupNames.contains("main"))  // wtA1 and wtB1 both named "main" — they're different IDs
        #expect(groupNames.contains("feature-x"))
        #expect(groupNames.contains("Floating"))
    }

    // MARK: - By CWD

    @Test

    func test_byCWD_groupsByCWD() {
        let (panes, repos, tabs) = makeTestPanes()

        let result = DynamicViewProjector.project(
            viewType: .byCWD, panes: panes, tabs: tabs, repos: repos
        )

        // 3 distinct CWDs + 1 with no CWD
        #expect(result.groups.count >= 3)

        // Pane4 (docs webview) has no CWD — should be in "No CWD"
        let noCWDGroup = result.groups.first { $0.name == "No CWD" }
        #expect((noCWDGroup) != nil)
    }

    // MARK: - By Agent Type

    @Test

    func test_byAgentType_groupsByAgent() {
        let (panes, repos, tabs) = makeTestPanes()

        let result = DynamicViewProjector.project(
            viewType: .byAgentType, panes: panes, tabs: tabs, repos: repos
        )

        let groupNames = Set(result.groups.map(\.name))
        #expect(groupNames.contains("Claude Code"))  // pane1 + pane3
        #expect(groupNames.contains("Codex"))  // pane2
        #expect(groupNames.contains("No Agent"))  // pane4

        let claudeGroup = result.groups.first { $0.name == "Claude Code" }!
        #expect(claudeGroup.paneIds.count == 2)
    }

    // MARK: - By Parent Folder

    @Test

    func test_byParentFolder_groupsByRepoParent() {
        let (panes, repos, tabs) = makeTestPanes()

        let result = DynamicViewProjector.project(
            viewType: .byParentFolder, panes: panes, tabs: tabs, repos: repos
        )

        // Both repos are under /Users/dev/projects/
        // So all worktree panes share one parent folder group
        let projectsGroup = result.groups.first { $0.name == "projects" }
        #expect((projectsGroup) != nil)
        if let pg = projectsGroup {
            #expect(pg.paneIds.count == 3)  // 3 worktree panes
        }

        // Floating pane should be in "Floating" group
        #expect(result.groups.contains { $0.name == "Floating" })
    }

    // MARK: - Edge Cases

    @Test

    func test_emptyPanes_producesEmptyGroups() {
        let result = DynamicViewProjector.project(
            viewType: .byRepo, panes: [:], tabs: [], repos: []
        )

        #expect(result.groups.isEmpty)
    }

    @Test

    func test_backgroundedPanes_excluded() {
        var (panes, repos, tabs) = makeTestPanes()
        let backgroundedId = panes.keys.first!
        panes[backgroundedId]!.residency = .backgrounded
        // Also remove from tab panes list
        for i in tabs.indices {
            tabs[i].panes.removeAll { $0 == backgroundedId }
        }

        let result = DynamicViewProjector.project(
            viewType: .byRepo, panes: panes, tabs: tabs, repos: repos
        )

        // The backgrounded pane should not appear in any group
        let allPaneIds = result.groups.flatMap(\.paneIds)
        #expect(!(allPaneIds.contains(backgroundedId)))
    }

    @Test

    func test_panesNotInTabs_excluded() {
        var (panes, repos, tabs) = makeTestPanes()
        // Add a pane that's not in any tab
        let orphan = Pane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Orphan")
        )
        panes[orphan.id] = orphan

        let result = DynamicViewProjector.project(
            viewType: .byRepo, panes: panes, tabs: tabs, repos: repos
        )

        let allPaneIds = result.groups.flatMap(\.paneIds)
        #expect(!(allPaneIds.contains(orphan.id)))
    }

    @Test

    func test_autoTiledLayouts_containAllPanes() {
        let (panes, repos, tabs) = makeTestPanes()

        let result = DynamicViewProjector.project(
            viewType: .byRepo, panes: panes, tabs: tabs, repos: repos
        )

        for group in result.groups {
            #expect(Set(group.layout.paneIds) == Set(group.paneIds), "Layout pane IDs should match group pane IDs for \(group.name)")
        }
    }

    // MARK: - DynamicViewType

    @Test

    func test_dynamicViewType_displayNames() {
        #expect(DynamicViewType.byRepo.displayName == "By Repo")
        #expect(DynamicViewType.byWorktree.displayName == "By Worktree")
        #expect(DynamicViewType.byCWD.displayName == "By CWD")
        #expect(DynamicViewType.byAgentType.displayName == "By Agent Type")
        #expect(DynamicViewType.byParentFolder.displayName == "By Parent Folder")
    }

    @Test

    func test_dynamicViewType_allCases() {
        #expect(DynamicViewType.allCases.count == 5)
    }
}
