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
    @Test("scroll gap samples use bounded burst and frame sequences")
    func scrollGapSamplesUseBoundedBurstAndFrameSequences() {
        var state = RepoExplorerScrollGapState()

        let first = state.sample(atNanoseconds: 1_000_000_000, visibleRowCount: 3)
        let second = state.sample(atNanoseconds: 1_016_000_000, visibleRowCount: 9)
        let nextBurst = state.sample(atNanoseconds: 1_300_000_000, visibleRowCount: 33)

        #expect(first.outcome == .incomplete)
        #expect(first.scrollBurstSequence == 1)
        #expect(first.frameSampleSequence == 1)
        #expect(first.visibleRowCountBucket.rawValue == "1_8")
        #expect(first.traceAttributes["agentstudio.performance.repo_explorer.scroll_active"] == .bool(true))
        #expect(second.outcome == .sampled)
        #expect(second.gapDuration == .milliseconds(16))
        #expect(second.scrollBurstSequence == 1)
        #expect(second.frameSampleSequence == 2)
        #expect(second.visibleRowCountBucket.rawValue == "9_16")
        #expect(nextBurst.outcome == .incomplete)
        #expect(nextBurst.scrollBurstSequence == 2)
        #expect(nextBurst.frameSampleSequence == 1)
        #expect(nextBurst.visibleRowCountBucket.rawValue == "33_plus")
    }

    @Test("scroll-active classification expires at the bounded burst threshold")
    func scrollActiveClassificationExpiresAtBoundedBurstThreshold() {
        let state = RepoExplorerScrollInstrumentationState()

        #expect(state.latestVisibleRowCountBucket == nil)

        _ = state.recordBoundsChange(atNanoseconds: 1_000_000_000, visibleRowCount: 4)

        #expect(state.latestVisibleRowCountBucket == .oneToEight)
        #expect(state.isScrollActive(atNanoseconds: 1_250_000_000))
        #expect(!state.isScrollActive(atNanoseconds: 1_250_000_001))
    }

    @Test("visible row range ignores section and loading entries while retaining worktree leaves")
    func visibleRowRangeIgnoresSectionAndLoadingEntriesWhileRetainingWorktreeLeaves() {
        let groupId = "tab:\(UUIDv7.generate().uuidString)"
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let loadingRepoId = UUIDv7.generate()
        let loadingWorktreeId = UUIDv7.generate()
        let entriesPaneID = UUIDv7.generate()
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
            .resolvedWorktreeRow(
                groupId: groupId,
                repoId: firstRepoId,
                worktreeId: firstWorktreeId,
                rowId: .worktree(
                    groupID: groupId,
                    repoID: firstRepoId,
                    worktreeID: firstWorktreeId
                )
            ),
            .loadingSectionHeader(.repositories),
            .loadingRepoRow(section: .repositories, repo: loadingRepo),
            .resolvedWorktreeRow(
                groupId: groupId,
                repoId: secondRepoId,
                worktreeId: secondWorktreeId,
                rowId: .worktree(
                    groupID: groupId,
                    repoID: secondRepoId,
                    worktreeID: secondWorktreeId
                )
            ),
            .resolvedPaneRow(
                groupId: groupId,
                identity: RepoExplorerPaneListEntryIdentity(
                    repoId: secondRepoId,
                    worktreeId: secondWorktreeId,
                    paneId: entriesPaneID
                ),
                rowId: .associatedPane(
                    groupID: groupId,
                    repoID: secondRepoId,
                    worktreeID: secondWorktreeId,
                    paneID: entriesPaneID
                )
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
                rowRange: NSRange(location: 3, length: 2)
            ).isEmpty
        )
        #expect(
            RepoExplorerVisibleRows.worktreeIds(
                in: entries,
                rowRange: NSRange(location: 5, length: 2)
            ) == [secondWorktreeId]
        )
    }

    @Test("visible row range includes command-bearing worktree rows but excludes pane leaves")
    func visibleRowRangeIncludesOnlyCommandBearingWorktreeRows() {
        let firstRepoId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let paneID = UUIDv7.generate()
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
                rowId: .worktree(
                    groupID: group.id,
                    repoID: firstRepoId,
                    worktreeID: firstWorktreeId
                )
            ),
            .resolvedWorktreeRow(
                groupId: group.id,
                repoId: secondRepoId,
                worktreeId: secondWorktreeId,
                rowId: .worktree(
                    groupID: group.id,
                    repoID: secondRepoId,
                    worktreeID: secondWorktreeId
                )
            ),
            .resolvedPaneRow(
                groupId: group.id,
                identity: RepoExplorerPaneListEntryIdentity(
                    repoId: secondRepoId,
                    worktreeId: secondWorktreeId,
                    paneId: paneID
                ),
                rowId: .associatedPane(
                    groupID: group.id,
                    repoID: secondRepoId,
                    worktreeID: secondWorktreeId,
                    paneID: paneID
                )
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
