import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorktreePresenceTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    @Test
    func test_build_worktreeWithNoPanes_returnsEmptyPresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-test"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-test"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.worktreeId == storedWorktree.id)
        #expect(presence.repoId == repo.id)
        #expect(presence.openPanes.isEmpty)
        #expect(presence.openState == .notOpen)
    }

    @Test
    func test_build_worktreeWithOnePane_returnsSinglePanePresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-single"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/presence-single/feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }
        let pane = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "Terminal"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.openPanes.count == 1)
        #expect(presence.openPanes[0].paneId == pane.id)
        #expect(presence.openPanes[0].tabId == tab.id)
        #expect(presence.openPanes[0].tabIndex == 0)
        #expect(presence.openPanes[0].paneIndexInTab == 0)
        #expect(presence.openState == .singlePane)
    }

    @Test
    func test_build_worktreeWithMultiplePanes_returnsMultiPanePresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-multi"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-multi"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        let paneA = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "A"
        )
        let tabA = Tab(paneId: paneA.id)
        store.appendTab(tabA)

        let paneB = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "B"
        )
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabB)

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.openPanes.count == 2)
        #expect(presence.openState == .multiplePanes)
        let tabIds = Set(presence.openPanes.map(\.tabId))
        #expect(tabIds.contains(tabA.id))
        #expect(tabIds.contains(tabB.id))
    }

    @Test
    func test_build_computesDistinctTabCount() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-tabs"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-tabs"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        let paneA = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "A"
        )
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let paneB = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "B"
        )
        store.insertPane(
            paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.openPanes.count == 2)
        #expect(presence.distinctTabCount == 1)
        #expect(presence.openState == .multiplePanes)
        #expect(presence.openPanes[0].paneIndexInTab == 0)
        #expect(presence.openPanes[1].paneIndexInTab == 1)
    }

    @Test
    func test_build_sortsPanesByTabVisibleOrder_notByPaneId() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-pane-order"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-pane-order")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        let paneA = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "A"
        )
        let paneB = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "B"
        )
        let paneC = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "C"
        )
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
        store.insertPane(
            paneC.id, inTab: tab.id, at: paneB.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.openPanes.map(\.paneId) == [paneA.id, paneB.id, paneC.id])
        #expect(presence.openPanes.map(\.paneIndexInTab) == [0, 1, 2])
    }

    @Test
    func test_build_excludesBackgroundedPanesFromPresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-backgrounded"))
        let worktree = Worktree(repoId: repo.id, name: "main", path: URL(filePath: "/tmp/presence-backgrounded"))
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        _ = store.createPane(
            source: .worktree(worktreeId: storedWorktree.id, repoId: repo.id, launchDirectory: storedWorktree.path),
            title: "Backgrounded",
            residency: .backgrounded
        )

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.openPanes.isEmpty)
        #expect(presence.openState == .notOpen)
    }

    @Test
    func test_build_excludesActivePanesWithoutOwningTab() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-orphan"))
        let worktree = Worktree(repoId: repo.id, name: "main", path: URL(filePath: "/tmp/presence-orphan"))
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        _ = store.createPane(
            source: .worktree(worktreeId: storedWorktree.id, repoId: repo.id, launchDirectory: storedWorktree.path),
            title: "Orphaned"
        )

        let presence = CommandBarDataSource.buildWorktreePresence(worktree: storedWorktree, repo: repo, store: store)

        #expect(presence.openPanes.isEmpty)
        #expect(presence.openState == .notOpen)
    }
}
