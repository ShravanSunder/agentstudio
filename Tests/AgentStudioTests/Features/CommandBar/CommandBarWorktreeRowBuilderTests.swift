import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarWorktreeRowBuilderTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    @Test
    func test_buildWorktreePaneDrillInLevel_includesNavigateAndOpenRows() {
        let worktree = Worktree(
            repoId: UUID(),
            name: "main",
            path: URL(filePath: "/tmp/drill-in-main"),
            isMainWorktree: true
        )
        let repo = Repo(
            id: worktree.repoId,
            name: "repo",
            repoPath: URL(filePath: "/tmp/drill-in-main"),
            worktrees: [worktree]
        )
        let tabId = UUID()
        let presence = WorktreePresence(
            worktreeId: worktree.id,
            repoId: repo.id,
            worktreeName: worktree.name,
            repoName: repo.name,
            isMainWorktree: true,
            openPanes: [
                WorktreePaneLocation(paneId: UUID(), tabId: tabId, tabIndex: 0, isActiveInTab: true),
                WorktreePaneLocation(paneId: UUID(), tabId: UUID(), tabIndex: 2, isActiveInTab: false),
            ]
        )

        let level = CommandBarDataSource.buildWorktreePaneDrillInLevel(
            presence: presence,
            worktree: worktree,
            repo: repo
        )

        #expect(level.title == "main")
        #expect(level.parentLabel == "repo")
        #expect(level.items.count == 4)
        #expect(level.items.filter { $0.group == "Navigate to" }.count == 2)
        #expect(level.items.filter { $0.group == "Open new" }.count == 2)
        #expect(level.items.contains { $0.id == "wt-new-tab-\(worktree.id.uuidString)" })
        #expect(level.items.contains { $0.id == "wt-add-pane-\(worktree.id.uuidString)" })
    }

    @Test
    func test_buildWorktreeOpenChoiceLevel_hidesCurrentTabOptionWhenNoTabs() {
        let worktree = Worktree(
            repoId: UUID(),
            name: "main",
            path: URL(filePath: "/tmp/open-choice-main"),
            isMainWorktree: true
        )
        let repo = Repo(
            id: worktree.repoId,
            name: "repo",
            repoPath: URL(filePath: "/tmp/open-choice-main"),
            worktrees: [worktree]
        )

        let level = CommandBarDataSource.buildWorktreeOpenChoiceLevel(
            worktree: worktree,
            repo: repo,
            hasTabsOpen: false
        )

        #expect(level.items.count == 1)
        #expect(level.items[0].id == "wt-choice-new-tab-\(worktree.id.uuidString)")
    }

    @Test
    func test_buildWorktreeOpenChoiceLevel_includesCurrentTabOptionWhenTabsExist() {
        let worktree = Worktree(
            repoId: UUID(),
            name: "main",
            path: URL(filePath: "/tmp/open-choice-main"),
            isMainWorktree: true
        )
        let repo = Repo(
            id: worktree.repoId,
            name: "repo",
            repoPath: URL(filePath: "/tmp/open-choice-main"),
            worktrees: [worktree]
        )

        let level = CommandBarDataSource.buildWorktreeOpenChoiceLevel(
            worktree: worktree,
            repo: repo,
            hasTabsOpen: true
        )

        #expect(level.items.count == 2)
        #expect(level.items.contains { $0.id == "wt-choice-new-tab-\(worktree.id.uuidString)" })
        #expect(level.items.contains { $0.id == "wt-choice-add-pane-\(worktree.id.uuidString)" })
    }

    @Test
    func test_worktreePresenceSubtitle_multiplePanesSingleTab_usesSingleTabFormat() {
        let tabId = UUID()
        let presence = WorktreePresence(
            worktreeId: UUID(),
            repoId: UUID(),
            worktreeName: "main",
            repoName: "repo",
            isMainWorktree: true,
            openPanes: [
                WorktreePaneLocation(paneId: UUID(), tabId: tabId, tabIndex: 1, isActiveInTab: true),
                WorktreePaneLocation(paneId: UUID(), tabId: tabId, tabIndex: 1, isActiveInTab: false),
            ]
        )
        let worktree = Worktree(
            repoId: presence.repoId,
            name: "main",
            path: URL(filePath: "/tmp/subtitle-main"),
            isMainWorktree: true
        )

        let subtitle = CommandBarDataSource.worktreePresenceSubtitle(
            presence: presence,
            worktree: worktree
        )

        #expect(subtitle == "● 2 panes · Tab 2")
    }

    @Test
    func test_worktreePresenceSubtitle_multiplePanesMultiTab_usesMultiTabFormat() {
        let presence = WorktreePresence(
            worktreeId: UUID(),
            repoId: UUID(),
            worktreeName: "main",
            repoName: "repo",
            isMainWorktree: true,
            openPanes: [
                WorktreePaneLocation(paneId: UUID(), tabId: UUID(), tabIndex: 0, isActiveInTab: true),
                WorktreePaneLocation(paneId: UUID(), tabId: UUID(), tabIndex: 1, isActiveInTab: false),
            ]
        )
        let worktree = Worktree(
            repoId: presence.repoId,
            name: "main",
            path: URL(filePath: "/tmp/subtitle-main"),
            isMainWorktree: true
        )

        let subtitle = CommandBarDataSource.worktreePresenceSubtitle(
            presence: presence,
            worktree: worktree
        )

        #expect(subtitle == "● 2 panes · 2 tabs")
    }

    @Test
    func test_worktreePresenceSubtitle_nonMainNotOpen_returnsNil() {
        let presence = WorktreePresence(
            worktreeId: UUID(),
            repoId: UUID(),
            worktreeName: "feature",
            repoName: "repo",
            isMainWorktree: false,
            openPanes: []
        )
        let worktree = Worktree(
            repoId: presence.repoId,
            name: "feature",
            path: URL(filePath: "/tmp/subtitle-feature"),
            isMainWorktree: false
        )

        let subtitle = CommandBarDataSource.worktreePresenceSubtitle(
            presence: presence,
            worktree: worktree
        )

        #expect(subtitle == nil)
    }
}
