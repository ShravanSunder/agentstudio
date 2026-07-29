import AppKit
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneManagementTrailingControlTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("main panes use Move to Tab while drawer panes retain Detach")
    func paneManagementTrailingControlMatchesPaneResidency() {
        #expect(PaneManagementTrailingControl.resolve(isDrawerChild: false) == .movePaneToTab)
        #expect(PaneManagementTrailingControl.resolve(isDrawerChild: true) == .detachDrawerPane)
    }

    @Test("Move and Detach use the same management edge-tab geometry")
    func moveAndDetachShareManagementEdgeTabGeometry() throws {
        let moveState = try mountedTrailingControlState(isDrawerChild: false)
        let detachState = try mountedTrailingControlState(isDrawerChild: true)
        let expectedSize = CGSize(
            width: AppStyles.Shell.PaneChrome.paneSplitButtonSize,
            height: AppStyles.Shell.PaneChrome.paneSplitButtonSize + 12
        )

        #expect(moveState.controlFrame.size == expectedSize)
        #expect(detachState.controlFrame.size == expectedSize)
    }

    @Test("main-pane Move sits directly above the identity card")
    func moveControlAnchorsAboveIdentityCard() throws {
        let state = try mountedTrailingControlState(
            isDrawerChild: false,
            worktreeBacked: true
        )
        let identityFrame = try #require(state.identityFrame)

        #expect(abs(state.controlFrame.maxY - identityFrame.minY) < 0.5)
        #expect(
            abs(
                state.controlFrame.maxX
                    - (state.hostingBounds.maxX - AppStyles.General.Layout.paneGap)
            ) < 0.5
        )
    }

    private struct MountedTrailingControlState {
        let controlFrame: CGRect
        let identityFrame: CGRect?
        let hostingBounds: CGRect
    }

    private func mountedTrailingControlState(
        isDrawerChild: Bool,
        worktreeBacked: Bool = false
    ) throws -> MountedTrailingControlState {
        let store = WorkspaceStore()
        let parentPane: Pane
        if worktreeBacked {
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/agent-studio/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            let storedWorktree = store.repos[0].worktrees[0]
            parentPane = store.createPane(
                launchDirectory: storedWorktree.path,
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: repo.name,
                    worktreeId: storedWorktree.id,
                    worktreeName: storedWorktree.name,
                    cwd: storedWorktree.path
                )
            )
        } else {
            parentPane = store.createPane()
        }
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let targetPane: Pane
        let accessibilityIdentifier: String
        if isDrawerChild {
            targetPane = try #require(store.addDrawerPane(to: parentPane.id))
            accessibilityIdentifier = "paneManagement.detachDrawerPane"
        } else {
            targetPane = parentPane
            accessibilityIdentifier = "paneManagement.movePaneToTab"
            let destinationPane = store.createPane()
            store.appendTab(Tab(paneId: destinationPane.id))
        }

        atom(\.managementLayer).activate()
        defer { atom(\.managementLayer).deactivate() }

        let hostingView = NSHostingView(
            rootView: PaneLeafContainer(
                paneHost: PaneHostView(paneId: targetPane.id),
                octiconLoader: makeTestOcticonLoader(),
                tabId: tab.id,
                isActive: true,
                isSplit: false,
                isSplitResizing: false,
                store: store,
                repoCache: RepoCacheAtom(),
                editorChooser: makeTestAtomRegistry().editorChooser,
                closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
                actionDispatcher: makeNoOpPaneActionDispatcher(),
                onPaneFocusTrigger: { _ in },
                onOpenPaneGitHub: { _ in },
                toolbarPresentation: .hidden
            )
            .frame(width: 640, height: 360)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()
        let controlView = try #require(
            findAccessibilityView(
                in: hostingView,
                identifier: accessibilityIdentifier
            )
        )
        let identityView = findAccessibilityView(
            in: hostingView,
            identifier: "paneManagement.identityStrip"
        )
        return MountedTrailingControlState(
            controlFrame: controlView.convert(controlView.bounds, to: hostingView),
            identityFrame: identityView?.convert(identityView?.bounds ?? .zero, to: hostingView),
            hostingBounds: hostingView.bounds
        )
    }

    private func makeNoOpPaneActionDispatcher() -> PaneTabActionDispatcher {
        PaneTabActionDispatcher(
            dispatch: { _ in },
            shouldHandleSplitDragPayload: { _ in false },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
    }

    private func findAccessibilityView(
        in root: NSView,
        identifier: String
    ) -> NSView? {
        if root.accessibilityIdentifier() == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = findAccessibilityView(in: subview, identifier: identifier) {
                return match
            }
        }
        return nil
    }
}
