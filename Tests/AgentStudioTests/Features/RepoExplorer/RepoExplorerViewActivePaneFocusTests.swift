import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

/// Split from `RepoExplorerViewProjectionHelperTests` (SwiftLint `file_length`/`type_body_length`):
/// tests for the active-pane chip's real-attention composition (F5) and its keyboard-routing/
/// observation-admission extensions (N2a, N2b from the sidebar-grouping re-audit).
extension RepoExplorerViewProjectionHelperTests {
    @Test("visible Repo observation consumes its registration when surface demand is lost")
    func visibleRepoObservationTracksDemandLoss() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let invalidationRecorder = RepoProjectionInvalidationRecorder()

            withObservationTracking {
                _ = view.projectionInputRevision
            } onChange: {
                invalidationRecorder.record()
            }
            atoms.workspaceSidebarState.setSidebarSurface(.inbox)

            #expect(invalidationRecorder.invalidationCount == 1)
        }
    }

    @Test("By Repository does not observe pane attention transitions")
    func byRepositoryDoesNotObservePaneAttention() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)
            let invalidationRecorder = RepoProjectionInvalidationRecorder()

            withObservationTracking {
                _ = view.projectionInputRevision
            } onChange: {
                invalidationRecorder.record()
            }
            atoms.commandBarSurface.present(scope: .everything, workspaceWindowId: windowId)

            #expect(invalidationRecorder.invalidationCount == 0)
        }
    }

    @Test("hidden Repo surface registers no projection inputs")
    func hiddenRepoSurfaceRegistersNoProjectionInputs() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.pane)
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: preferences,
                isProjectionDemanded: false,
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let invalidationRecorder = RepoProjectionInvalidationRecorder()

            withObservationTracking {
                _ = view.projectionInputRevision
            } onChange: {
                invalidationRecorder.record()
            }
            atoms.commandBarSurface.present(
                scope: .everything,
                workspaceWindowId: UUIDv7.generate()
            )
            preferences.setGroupingMode(.tab)

            #expect(invalidationRecorder.invalidationCount == 0)
        }
    }

    @Test("F5: the active pane chip requires real attention, not merely tab selection")
    func activePaneRowFactRequiresRealAttentionNotJustTabSelection() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-active-attention"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)

            // Baseline: workspace window key, management layer inactive, sidebar unfocused -- this
            // pane genuinely holds attention.
            #expect(view.paneRowFactsByPaneId()[pane.id]?.isActive == true)

            // Sidebar keyboard focus must suppress the chip even though this pane is still the
            // tab's selected pane -- the old implementation only consulted tab selection and never
            // consulted keyboard ownership at all.
            atoms.workspaceSidebarState.setSidebarHasFocus(true)
            #expect(view.paneRowFactsByPaneId()[pane.id]?.isActive == false)
            atoms.workspaceSidebarState.setSidebarHasFocus(false)

            // Losing key window status covers both "another window is focused" and "the app itself
            // is inactive": WindowLifecycleAtom.isWorkspaceWindowKey intentionally conflates those
            // two cases into one fact, and AttendedPaneDerived already keys off it.
            atoms.windowLifecycle.recordWindowResignedKey(windowId)
            #expect(view.paneRowFactsByPaneId()[pane.id]?.isActive == false)
        }
    }

    @Test("N2b: an open command bar suppresses the active pane chip even though the window is key")
    func activePaneRowFactDropsWhenCommandBarIsOpen() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-command-bar-active"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)

            // Baseline: window key, sidebar unfocused, no transient surface -- genuinely active.
            #expect(view.paneRowFactsByPaneId()[pane.id]?.isActive == true)

            // The window/management-layer/sidebar-focus facts alone are unchanged and would still
            // resolve KeyboardOwner to mainWindowChain, but an open command bar means the pane
            // chain does not actually own keyboard input right now.
            atoms.commandBarSurface.present(scope: .everything, workspaceWindowId: windowId)
            #expect(view.paneRowFactsByPaneId()[pane.id]?.isActive == false)

            atoms.commandBarSurface.dismiss(workspaceWindowId: windowId)
            #expect(view.paneRowFactsByPaneId()[pane.id]?.isActive == true)
        }
    }

    @Test("N2a: a focus-only transition wakes the projection input observation gate")
    func projectionInputRevisionObservesFocusTransitions() {
        // N2a (re-audit): paneRowFactsByPaneId's isActive composition depends on
        // KeyboardRoutingContext + attendedPane, but the separate admission gate
        // (projectionInputRevision) that decides whether a cached projection gets rebuilt did not
        // read those same inputs -- a focus-only transition (nothing else about the projection
        // changing) would never wake the gate, leaving a stale isActive on screen until an
        // unrelated input happened to tick. Prove the gate itself now observes a command-bar
        // transition, using the exact withObservationTracking wiring the production code uses.
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.pane)
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: preferences,
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)

            let invalidationRecorder = RepoProjectionInvalidationRecorder()
            withObservationTracking {
                _ = view.projectionInputRevision
            } onChange: {
                invalidationRecorder.record()
            }

            atoms.commandBarSurface.present(scope: .everything, workspaceWindowId: windowId)

            #expect(invalidationRecorder.invalidationCount == 1)
        }
    }
}
