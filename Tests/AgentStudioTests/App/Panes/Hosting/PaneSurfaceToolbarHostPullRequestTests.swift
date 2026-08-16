import AppKit
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInfrastructure
@testable import AgentStudioSharedComponents

@MainActor
@Suite("Pane surface toolbar pull request action", .serialized)
struct PaneSurfaceToolbarHostPullRequestTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("exact branch PR mounts Open PR and opens its exact URL")
    func exactPullRequestMountsAndOpensExactURL() throws {
        let exactURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/264")!
        let fixture = try makeFixture(
            pullRequestFacts: PullRequestFacts(openCount: 1, exactOpenURL: exactURL)
        )
        let opener = ExternalURLRecorder()
        let mount = mountToolbar(fixture: fixture, opener: opener)
        defer {
            mount.window.orderOut(nil)
            mount.window.close()
        }

        let button = try #require(
            findAccessibilityPressBridge(
                in: mount.hostingView,
                identifier: "paneSurfaceToolbar.pullRequest"
            )
        )

        #expect(button.accessibilityLabel() == "Open PR, checks unknown")
        #expect(button.isAccessibilityEnabled())
        #expect(button.accessibilityPerformPress())
        #expect(opener.openedURLs == [exactURL])
    }

    @Test("PR control remains visible and disabled without an exact URL")
    func pullRequestControlWithoutExactURLIsVisibleAndDisabled() throws {
        for pullRequestFacts in [nil, PullRequestFacts(openCount: 0, exactOpenURL: nil)] {
            let opener = ExternalURLRecorder()
            let fixture = try makeFixture(pullRequestFacts: pullRequestFacts)
            let mount = mountToolbar(fixture: fixture, opener: opener)
            defer {
                mount.window.orderOut(nil)
                mount.window.close()
            }

            let button = try #require(
                findAccessibilityPressBridge(
                    in: mount.hostingView,
                    identifier: "paneSurfaceToolbar.pullRequest"
                )
            )
            #expect(!button.isAccessibilityEnabled())
            #expect(!button.accessibilityPerformPress())
            #expect(opener.openedURLs.isEmpty)
        }
    }

    private func makeFixture(pullRequestFacts: PullRequestFacts?) throws -> PullRequestToolbarFixture {
        let store = WorkspaceStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-pr-button"))
        let worktree = try #require(
            store.repos.first(where: { $0.id == repo.id })?.worktrees.first
        )
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: worktree.id,
                cwd: worktree.path
            )
        )
        store.appendTab(Tab(paneId: pane.id))
        cache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repo.id,
                raw: RawRepoOrigin(
                    origin: "git@github.com:ShravanSunder/agentstudio.git",
                    upstream: nil
                ),
                identity: RepoIdentity(
                    groupKey: "remote:ShravanSunder/agentstudio",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date()
            )
        )
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktree.id,
                repoId: repo.id,
                branch: "feature/pr-toolbar"
            )
        )
        if let pullRequestFacts {
            let branchKey = RepoBranchKey(repoId: repo.id, branch: "feature/pr-toolbar")!
            cache.applyPullRequestFacts([branchKey: pullRequestFacts])
        }

        return PullRequestToolbarFixture(
            store: store,
            cache: cache,
            paneId: pane.id
        )
    }

    private func mountToolbar(
        fixture: PullRequestToolbarFixture,
        opener: ExternalURLRecorder
    ) -> MountedToolbar {
        let hostingView = NSHostingView(
            rootView: AnyView(
                PaneSurfaceToolbarHost(
                    anchorPaneId: fixture.paneId,
                    locationTargetPaneId: fixture.paneId,
                    toolbarSurface: .pane,
                    drawer: nil,
                    leadingToolbarActions: [],
                    contextToolbarActions: [],
                    store: fixture.store,
                    repoCache: fixture.cache,
                    octiconLoader: makeTestOcticonLoader(),
                    editorChooser: EditorChooserState(),
                    paneInboxPresentation: nil,
                    workspaceWindowId: nil,
                    actionDispatcher: PaneTabActionDispatcher(
                        dispatch: { _ in },
                        shouldHandleSplitDragPayload: { _ in false },
                        shouldAcceptDrop: { _, _, _, _ in false },
                        handleDrop: { _, _, _, _ in }
                    ),
                    onPaneFocusTrigger: { _ in },
                    openExternalURL: { url in
                        opener.record(url)
                    }
                )
                .frame(width: 640, height: 44)
            )
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 44)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        return MountedToolbar(hostingView: hostingView, window: window)
    }

    private func findAccessibilityPressBridge(
        in root: NSView,
        identifier: String
    ) -> AccessibilityPressBridgeView? {
        if let bridge = root as? AccessibilityPressBridgeView,
            bridge.accessibilityIdentifier() == identifier
        {
            return bridge
        }
        for subview in root.subviews {
            if let bridge = findAccessibilityPressBridge(in: subview, identifier: identifier) {
                return bridge
            }
        }
        return nil
    }
}

@MainActor
private struct PullRequestToolbarFixture {
    let store: WorkspaceStore
    let cache: RepoCacheAtom
    let paneId: UUID
}

@MainActor
private struct MountedToolbar {
    let hostingView: NSHostingView<AnyView>
    let window: NSWindow
}

@MainActor
private final class ExternalURLRecorder {
    private(set) var openedURLs: [URL] = []

    func record(_ url: URL) {
        openedURLs.append(url)
    }
}
