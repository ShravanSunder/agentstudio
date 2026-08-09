import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class VisibleWorktreeCallbackRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

@MainActor
@Suite("RepoExplorer visible rows")
struct RepoExplorerVisibleRowsTests {
    @Test("visible row range ignores section and loading entries while retaining worktree leaves")
    func visibleRowRangeIgnoresSectionAndLoadingEntriesWhileRetainingWorktreeLeaves() {
        let groupId = "tab:\(UUIDv7.generate().uuidString)"
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let loadingRepoId = UUIDv7.generate()
        let loadingWorktreeId = UUIDv7.generate()
        let group = RepoPresentationGroup(
            id: groupId,
            repoTitle: "Tab 1",
            organizationName: nil,
            repos: []
        )
        let loadingRepo = RepoPresentationItem(
            id: loadingRepoId,
            name: "loading-repository",
            repoPath: URL(fileURLWithPath: "/tmp/loading-repository"),
            stableKey: "loading-repository",
            worktrees: [
                Worktree(
                    id: loadingWorktreeId,
                    repoId: loadingRepoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/loading-repository")
                )
            ]
        )
        let entries: [RepoExplorerListEntry] = [
            .sectionHeader(.tabs),
            .resolvedGroupHeader(group),
            .groupSectionHeader(groupId: groupId, kind: .favorites),
            .resolvedWorktreeRow(
                groupId: groupId,
                repoId: firstRepoId,
                worktreeId: firstWorktreeId,
                rowId: "first"
            ),
            .loadingSectionHeader(.repositories),
            .loadingRepoRow(section: .repositories, repo: loadingRepo),
            .groupSectionHeader(groupId: groupId, kind: .repositories),
            .resolvedWorktreeRow(
                groupId: groupId,
                repoId: secondRepoId,
                worktreeId: secondWorktreeId,
                rowId: "second"
            ),
            .resolvedPaneRow(
                groupId: groupId,
                identity: RepoExplorerPaneListEntryIdentity(
                    repoId: secondRepoId,
                    worktreeId: secondWorktreeId,
                    paneId: UUIDv7.generate()
                ),
                rowId: "pane"
            ),
        ]

        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 0, length: entries.count)
            ) == [firstWorktreeId, secondWorktreeId]
        )
        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 4, length: 3)
            ).isEmpty
        )
        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 6, length: 2)
            ) == [secondWorktreeId]
        )
    }

    @Test("visible row range includes command-bearing worktree rows but excludes pane leaves")
    func visibleRowRangeIncludesOnlyCommandBearingWorktreeRows() {
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let group = RepoPresentationGroup(
            id: "remote:askluna/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "askluna",
            repos: []
        )
        let entries: [RepoExplorerListEntry] = [
            .resolvedGroupHeader(group),
            .resolvedWorktreeRow(
                groupId: group.id,
                repoId: firstRepoId,
                worktreeId: firstWorktreeId,
                rowId: "first"
            ),
            .resolvedWorktreeRow(
                groupId: group.id,
                repoId: secondRepoId,
                worktreeId: secondWorktreeId,
                rowId: "second"
            ),
            .resolvedPaneRow(
                groupId: group.id,
                identity: RepoExplorerPaneListEntryIdentity(
                    repoId: secondRepoId,
                    worktreeId: secondWorktreeId,
                    paneId: UUIDv7.generate()
                ),
                rowId: "pane"
            ),
        ]

        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 0, length: 2)
            ) == [firstWorktreeId]
        )
        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 2, length: 2)
            ) == [secondWorktreeId]
        )
        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 3, length: 1)
            ).isEmpty
        )
        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: NSNotFound, length: 0)
            ).isEmpty
        )
    }

    @Test("visible worktree publication replaces atom state and invokes callback")
    func visibleWorktreePublicationReplacesAtomStateAndInvokesCallback() {
        let atom = SidebarVisibleWorktreesRuntimeAtom()
        let recorder = VisibleWorktreeCallbackRecorder()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        atom.setVisibleWorktreeIds([firstWorktreeId])

        RepoExplorerVisibleRows.publish(
            [secondWorktreeId],
            into: atom,
            onChange: recorder.record
        )

        #expect(atom.visibleWorktreeIds == [secondWorktreeId])
        #expect(recorder.callCount == 1)

        RepoExplorerVisibleRows.publish([], into: atom, onChange: recorder.record)

        #expect(atom.visibleWorktreeIds.isEmpty)
        #expect(recorder.callCount == 2)
    }
}
