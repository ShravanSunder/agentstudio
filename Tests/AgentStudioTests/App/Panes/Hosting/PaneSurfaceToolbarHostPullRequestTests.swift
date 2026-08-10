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

    @Test("Open PR uses the existing GitHub pull request octicon")
    func openPullRequestUsesGitHubPullRequestOcticon() {
        let icon = LocalActionSpec.openPullRequest.actionSpec.icon

        guard case .octicon(let symbol) = icon else {
            Issue.record("Open PR should use a GitHub octicon, got \(icon)")
            return
        }

        #expect(symbol.rawValue == "octicon-git-pull-request")
    }

    @Test("cached PR worktree mounts Open PR and opens its pulls URL")
    func cachedPullRequestMountsAndOpensPullsURL() throws {
        let fixture = try makeFixture(pullRequestCount: 1)
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

        #expect(button.accessibilityLabel() == "Open PR")
        #expect(button.isAccessibilityEnabled())
        #expect(button.accessibilityPerformPress())
        #expect(
            opener.openedURLs == [
                URL(string: "https://github.com/ShravanSunder/agentstudio/pulls")!
            ]
        )
    }

    @Test("cached merged PR mounts Open PR and opens its exact URL")
    func cachedMergedPullRequestMountsAndOpensExactURL() throws {
        let pullRequestURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/263")!
        let fixture = try makeFixture(pullRequestCount: 0, pullRequestURL: pullRequestURL)
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

        #expect(button.accessibilityLabel() == "Open PR")
        #expect(button.accessibilityPerformPress())
        #expect(opener.openedURLs == [pullRequestURL])
    }

    @Test("PR control is hidden without a positive cached PR count")
    func pullRequestControlRequiresPositiveCount() throws {
        for pullRequestCount in [nil, 0] as [Int?] {
            let fixture = try makeFixture(pullRequestCount: pullRequestCount)
            let mount = mountToolbar(fixture: fixture, opener: ExternalURLRecorder())
            defer {
                mount.window.orderOut(nil)
                mount.window.close()
            }

            #expect(
                findAccessibilityPressBridge(
                    in: mount.hostingView,
                    identifier: "paneSurfaceToolbar.pullRequest"
                ) == nil
            )
        }
    }

    private func makeFixture(pullRequestCount: Int?, pullRequestURL: URL? = nil) throws -> PullRequestToolbarFixture {
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
        if let pullRequestCount {
            cache.setPullRequestCount(pullRequestCount, for: worktree.id)
        }
        if let pullRequestURL {
            cache.setPullRequestURL(pullRequestURL, for: worktree.id)
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
