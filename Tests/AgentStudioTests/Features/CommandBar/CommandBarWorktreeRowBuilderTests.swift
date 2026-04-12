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
    func test_buildWorktreeActionsLevel_includesOpenCommandsAndNavigateRows() {
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
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: tabId,
                    tabIndex: 0,
                    paneIndexInTab: 0,
                    isActiveInTab: true
                ),
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabIndex: 2,
                    paneIndexInTab: 1,
                    isActiveInTab: false
                ),
            ]
        )

        let level = CommandBarDataSource.buildWorktreeActionsLevel(presence: presence, canOpenInCurrentTab: true)

        #expect(level.title == "main")
        #expect(level.parentLabel == "repo")
        #expect(level.items.count == 4)
        #expect(level.items.filter { $0.group == "Open" }.count == 2)
        #expect(level.items.filter { $0.group == "Navigate to" }.count == 2)
        #expect(level.items.contains { $0.id == "wt-new-tab-\(worktree.id.uuidString)" })
        #expect(level.items.contains { $0.id == "wt-add-pane-\(worktree.id.uuidString)" })
        #expect(level.items[0].id == "wt-new-tab-\(worktree.id.uuidString)")
        #expect(level.items[1].id == "wt-add-pane-\(worktree.id.uuidString)")
    }

    @Test
    func test_buildWorktreeActionsLevel_hidesCurrentTabOptionWhenUnavailable() {
        let presence = makeWorktreePresence(paneCount: 0)

        let level = CommandBarDataSource.buildWorktreeActionsLevel(presence: presence, canOpenInCurrentTab: false)

        #expect(level.items.count == 1)
        #expect(level.items[0].id == "wt-new-tab-\(presence.worktreeId.uuidString)")
        #expect(level.items.allSatisfy { $0.id != "wt-add-pane-\(presence.worktreeId.uuidString)" })
    }

    @Test
    func test_buildWorktreeActionsLevel_usesExistingTargetedCommands() {
        let presence = makeWorktreePresence(paneCount: 1)

        let level = CommandBarDataSource.buildWorktreeActionsLevel(presence: presence, canOpenInCurrentTab: true)

        guard
            case .dispatchTargeted(.openNewTerminalInTab, let newTabTarget, .worktree) = level.items[0].action
        else {
            Issue.record("Expected new-tab row to dispatch existing openNewTerminalInTab command")
            return
        }
        #expect(newTabTarget == presence.worktreeId)

        guard
            case .dispatchTargeted(.openWorktreeInPane, let splitTarget, .worktree) = level.items[1].action
        else {
            Issue.record("Expected current-tab row to dispatch existing openWorktreeInPane command")
            return
        }
        #expect(splitTarget == presence.worktreeId)
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
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: tabId,
                    tabIndex: 1,
                    paneIndexInTab: 0,
                    isActiveInTab: true
                ),
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: tabId,
                    tabIndex: 1,
                    paneIndexInTab: 1,
                    isActiveInTab: false
                ),
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
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabIndex: 0,
                    paneIndexInTab: 0,
                    isActiveInTab: true
                ),
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabIndex: 1,
                    paneIndexInTab: 1,
                    isActiveInTab: false
                ),
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

    @Test
    func test_buildWorktreeActionsLevel_showsPaneNumbersInSubtitles() {
        let presence = WorktreePresence(
            worktreeId: UUID(),
            repoId: UUID(),
            worktreeName: "main",
            repoName: "repo",
            isMainWorktree: true,
            openPanes: [
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabIndex: 1,
                    paneIndexInTab: 0,
                    isActiveInTab: false
                ),
                WorkspacePaneLocation(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabIndex: 1,
                    paneIndexInTab: 1,
                    isActiveInTab: true
                ),
            ]
        )

        let level = CommandBarDataSource.buildWorktreeActionsLevel(presence: presence, canOpenInCurrentTab: true)
        let navigateItems = level.items.filter { $0.group == "Navigate to" }

        #expect(navigateItems.count == 2)
        #expect(navigateItems[0].subtitle == "Tab 2 · Pane 1")
        #expect(navigateItems[1].subtitle == "Tab 2 · Pane 2 · Active")
    }
}
