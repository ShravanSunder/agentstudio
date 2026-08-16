import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("PanePullRequestToolbarActionFactory")
struct PanePullRequestToolbarActionFactoryTests {
    @Test("resolvable worktree without an exact PR keeps a neutral disabled control")
    func noExactPullRequestIsVisibleAndDisabled() throws {
        let fixture = try makeFixture()
        let recorder = CommandActionRecorder()

        let presentation = try #require(
            PanePullRequestToolbarActionFactory.make(
                paneId: fixture.pane.id,
                store: fixture.store,
                repoCache: fixture.cache,
                commandAction: makeCommandAction(isEnabled: false, recorder: recorder)
            )
        )
        let action = presentation.openAction
        let commandSpec = AppCommand.openPullRequest.definition

        #expect(action.state.icon == commandSpec.icon)
        #expect(action.state.isEnabled == false)
        #expect(action.state.isSelected == false)
        #expect(action.state.selectionEmphasis == .standard)
        #expect(action.state.iconStatusTone == nil)
        #expect(action.state.iconAccentColorHex == nil)
        #expect(action.state.label == commandSpec.label)
        #expect(action.state.tooltip == commandSpec.controlTooltipRenderValue())
        #expect(presentation.blockerIndicator == nil)
        action.perform()
        #expect(recorder.performCount == 0)
    }

    @Test(
        "exact PR maps combined check state to an independent semantic color",
        arguments: [
            (PullRequestCheckStatus.passed, PaneSurfaceToolbarAction.IconStatusTone.success),
            (PullRequestCheckStatus.running, PaneSurfaceToolbarAction.IconStatusTone.warning),
            (PullRequestCheckStatus.failed, PaneSurfaceToolbarAction.IconStatusTone.danger),
            (PullRequestCheckStatus.unknown, nil),
        ]
    )
    func exactPullRequestMapsCheckStatusToColor(
        checkStatus: PullRequestCheckStatus,
        expectedTone: PaneSurfaceToolbarAction.IconStatusTone?
    ) throws {
        let fixture = try makeFixture()
        let exactURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/264")!
        fixture.cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: fixture.worktree.id,
                repoId: fixture.repo.id,
                branch: "feature/pr-toolbar"
            )
        )
        let branchKey = RepoBranchKey(repoId: fixture.repo.id, branch: "feature/pr-toolbar")!
        fixture.cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(
                openCount: 1,
                exactOpenURL: exactURL,
                exactReadiness: PullRequestReadiness(
                    isDraft: false,
                    checkStatus: checkStatus,
                    reviewStatus: .approved,
                    mergeability: .mergeable,
                    mergeState: .clean
                )
            )
        ])
        let recorder = CommandActionRecorder()

        let presentation = try #require(
            PanePullRequestToolbarActionFactory.make(
                paneId: fixture.pane.id,
                store: fixture.store,
                repoCache: fixture.cache,
                commandAction: makeCommandAction(isEnabled: true, recorder: recorder)
            )
        )
        let action = presentation.openAction

        #expect(action.state.isEnabled)
        #expect(!action.state.isSelected)
        #expect(action.state.selectionEmphasis == .standard)
        #expect(action.state.iconStatusTone == expectedTone)
        #expect(action.state.iconAccentColorHex == nil)
        action.perform()
        #expect(recorder.performCount == 1)
    }

    @Test("draft, checks, and merge blockers have separate presentations")
    func draftChecksAndMergeBlockersHaveSeparatePresentations() throws {
        let fixture = try makeFixture()
        let exactURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/264")!
        fixture.cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: fixture.worktree.id,
                repoId: fixture.repo.id,
                branch: "feature/pr-toolbar"
            )
        )
        let branchKey = RepoBranchKey(repoId: fixture.repo.id, branch: "feature/pr-toolbar")!
        fixture.cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(
                openCount: 1,
                exactOpenURL: exactURL,
                exactReadiness: PullRequestReadiness(
                    isDraft: true,
                    checkStatus: .passed,
                    reviewStatus: .changesRequested,
                    mergeability: .conflicting,
                    mergeState: .dirty
                )
            )
        ])

        let optionalPresentation = PanePullRequestToolbarActionFactory.make(
            paneId: fixture.pane.id,
            store: fixture.store,
            repoCache: fixture.cache,
            commandAction: makeCommandAction(isEnabled: true)
        )
        let presentation = try #require(optionalPresentation)
        let action = presentation.openAction
        let blockerIndicator = try #require(presentation.blockerIndicator)

        #expect(action.state.isEnabled)
        #expect(action.state.icon == .octicon(.gitPullRequestDraft))
        #expect(action.state.iconStatusTone == .success)
        #expect(action.state.label == "Open PR, draft, checks passed")
        #expect(action.state.tooltip.text == "Checks passed")
        #expect(blockerIndicator.icon == .system(.xmarkCircleFill))
        #expect(blockerIndicator.iconStatusTone == .danger)
        #expect(blockerIndicator.label == "Merge conflicts")
        #expect(blockerIndicator.tooltip.text == "Merge conflicts")
    }

    @Test("behind does not create a merge blocker indicator")
    func behindDoesNotCreateMergeBlockerIndicator() throws {
        let presentation = try makeExactPullRequestPresentation(
            readiness: PullRequestReadiness(
                isDraft: false,
                checkStatus: .passed,
                reviewStatus: .approved,
                mergeability: .mergeable,
                mergeState: .behind
            )
        )

        #expect(presentation.blockerIndicator == nil)
        #expect(presentation.openAction.state.tooltip.text == "Checks passed")
    }

    @Test(
        "distinct non-CI blockers get one concrete status indicator",
        arguments: [
            (
                PullRequestReviewStatus.changesRequested,
                PullRequestMergeability.mergeable,
                PullRequestMergeState.clean,
                "Changes requested"
            ),
            (
                PullRequestReviewStatus.reviewRequired,
                PullRequestMergeability.mergeable,
                PullRequestMergeState.clean,
                "Review required"
            ),
            (
                PullRequestReviewStatus.approved,
                PullRequestMergeability.conflicting,
                PullRequestMergeState.clean,
                "Merge conflicts"
            ),
            (
                PullRequestReviewStatus.approved,
                PullRequestMergeability.mergeable,
                PullRequestMergeState.blocked,
                "Merge blocked"
            ),
        ]
    )
    func distinctNonCICheckBlockersGetOneConcreteStatusIndicator(
        reviewStatus: PullRequestReviewStatus,
        mergeability: PullRequestMergeability,
        mergeState: PullRequestMergeState,
        expectedDescription: String
    ) throws {
        let presentation = try makeExactPullRequestPresentation(
            readiness: PullRequestReadiness(
                isDraft: false,
                checkStatus: .passed,
                reviewStatus: reviewStatus,
                mergeability: mergeability,
                mergeState: mergeState
            )
        )
        let blockerIndicator = try #require(presentation.blockerIndicator)

        #expect(blockerIndicator.label == expectedDescription)
        #expect(blockerIndicator.tooltip.text == expectedDescription)
    }

    @Test(
        "generic blocked state does not duplicate unfinished checks",
        arguments: [PullRequestCheckStatus.running, .failed, .unknown]
    )
    func genericBlockedStateDoesNotDuplicateUnfinishedChecks(
        checkStatus: PullRequestCheckStatus
    ) throws {
        let presentation = try makeExactPullRequestPresentation(
            readiness: PullRequestReadiness(
                isDraft: false,
                checkStatus: checkStatus,
                reviewStatus: .approved,
                mergeability: .mergeable,
                mergeState: .blocked
            )
        )

        #expect(presentation.blockerIndicator == nil)
    }

    @Test("pane without a resolvable worktree has no PR control")
    func unresolvedPaneHasNoControl() {
        let store = WorkspaceStore()
        let pane = store.createPane(launchDirectory: nil, title: "Detached")

        #expect(
            PanePullRequestToolbarActionFactory.make(
                paneId: pane.id,
                store: store,
                repoCache: RepoCacheAtom(),
                commandAction: makeCommandAction(isEnabled: false)
            ) == nil
        )
    }

    private func makeFixture() throws -> Fixture {
        let store = WorkspaceStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/pr-toolbar"))
        let worktree = try #require(repo.worktrees.first)
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: worktree.id,
                cwd: worktree.path
            )
        )
        return Fixture(store: store, cache: cache, repo: repo, worktree: worktree, pane: pane)
    }

    private func makeExactPullRequestPresentation(
        readiness: PullRequestReadiness
    ) throws -> PanePullRequestToolbarPresentation {
        let fixture = try makeFixture()
        let exactURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/264")!
        fixture.cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: fixture.worktree.id,
                repoId: fixture.repo.id,
                branch: "feature/pr-toolbar"
            )
        )
        let branchKey = RepoBranchKey(repoId: fixture.repo.id, branch: "feature/pr-toolbar")!
        fixture.cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(
                openCount: 1,
                exactOpenURL: exactURL,
                exactReadiness: readiness
            )
        ])

        let optionalPresentation = PanePullRequestToolbarActionFactory.make(
            paneId: fixture.pane.id,
            store: fixture.store,
            repoCache: fixture.cache,
            commandAction: makeCommandAction(isEnabled: true)
        )
        return try #require(optionalPresentation)
    }

    private func makeCommandAction(
        isEnabled: Bool,
        recorder: CommandActionRecorder? = nil
    ) -> TargetedCommandControlAction {
        TargetedCommandControlAction(
            commandSpec: AppCommand.openPullRequest.definition,
            isEnabled: isEnabled,
            perform: {
                recorder?.record()
            }
        )
    }
}

private struct Fixture {
    let store: WorkspaceStore
    let cache: RepoCacheAtom
    let repo: Repo
    let worktree: Worktree
    let pane: Pane
}

@MainActor
private final class CommandActionRecorder {
    private(set) var performCount = 0

    func record() {
        performCount += 1
    }
}
