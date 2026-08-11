import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("PanePullRequestToolbarActionFactory")
struct PanePullRequestToolbarActionFactoryTests {
    @Test("resolvable worktree without an exact PR keeps a neutral disabled control")
    func noExactPullRequestIsVisibleAndDisabled() throws {
        let fixture = try makeFixture()
        let recorder = OpenedURLRecorder()

        let action = try #require(
            PanePullRequestToolbarActionFactory.make(
                paneId: fixture.pane.id,
                store: fixture.store,
                repoCache: fixture.cache,
                openExternalURL: recorder.open
            )
        )

        #expect(action.state.icon == .octicon(.gitPullRequest))
        #expect(action.state.isEnabled == false)
        #expect(action.state.isSelected == false)
        #expect(action.state.selectionEmphasis == .standard)
        action.perform()
        #expect(recorder.openedURLs.isEmpty)
    }

    @Test("exact branch PR enables the accented control and opens that browser URL")
    func exactPullRequestEnablesAndOpensURL() throws {
        let fixture = try makeFixture()
        let exactURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/264")!
        fixture.cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: fixture.worktree.id,
                repoId: fixture.repo.id,
                branch: "feature/pr-toolbar"
            )
        )
        fixture.cache.applyPullRequestFacts(
            repoId: fixture.repo.id,
            factsByBranch: [
                "feature/pr-toolbar": PullRequestFacts(openCount: 1, exactOpenURL: exactURL)
            ]
        )
        let recorder = OpenedURLRecorder()

        let action = try #require(
            PanePullRequestToolbarActionFactory.make(
                paneId: fixture.pane.id,
                store: fixture.store,
                repoCache: fixture.cache,
                openExternalURL: recorder.open
            )
        )

        #expect(action.state.isEnabled)
        #expect(action.state.isSelected)
        #expect(action.state.selectionEmphasis == .accent)
        action.perform()
        #expect(recorder.openedURLs == [exactURL])
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
                openExternalURL: { _ in true }
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
}

private struct Fixture {
    let store: WorkspaceStore
    let cache: RepoCacheAtom
    let repo: Repo
    let worktree: Worktree
    let pane: Pane
}

@MainActor
private final class OpenedURLRecorder {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}
