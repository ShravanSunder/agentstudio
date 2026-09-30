import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

/// Split from `RepoExplorerViewProjectionHelperTests` (SwiftLint `file_length`/`type_body_length`):
/// tests for sidebar focus and observation admission. Activity-based Active and clock
/// behavior is covered by RepoExplorerPaneActivityProjectionTests.
extension RepoExplorerViewProjectionHelperTests {
    private func makeProjectionInputCapture(
        store: WorkspaceStore,
        preferences: RepoExplorerSidebarPrefsAtom,
        atoms: CoreAtoms,
        bridgeAttendanceSnapshot: @escaping BridgeAttendanceSnapshot = { _ in nil }
    ) -> RepoExplorerProjectionInputCapture {
        RepoExplorerProjectionInputCapture(
            store: store,
            preferences: preferences,
            repoCache: atoms.repoCache,
            sidebarState: atoms.workspaceSidebarState,
            sidebarCache: atoms.sidebarCache,
            coreAtoms: atoms,
            bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
            latestPaneMessageSnapshot: { _ in nil }
        )
    }

    @Test("fixed Panes organization ignores mutable sort and grouping settings")
    func fixedPanesOrganizationIgnoresMutableSettings() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let preferences = RepoExplorerSidebarPrefsAtom()
            let capture = makeProjectionInputCapture(
                store: store,
                preferences: preferences,
                atoms: atoms
            )
            let invalidationRecorder = RepoProjectionInvalidationRecorder()
            let request = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)

            withObservationTracking {
                capture.observe(.presentation, request: request)
            } onChange: {
                invalidationRecorder.record()
            }
            preferences.setSortDirection(.ascending, for: .panes)
            preferences.setSortField(.name, for: .panes)
            preferences.setGroupingMode(.tab, for: .panes)

            #expect(invalidationRecorder.invalidationCount == 0)
            let current = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)
            #expect(current.snapshot.groupingMode == .activity)
            #expect(current.snapshot.subgroupMode == .ungrouped)
            #expect(current.snapshot.sortField == .activity)
            #expect(current.snapshot.sortOrder == .descending)
        }
    }

    @Test("legacy Inbox selection does not revoke sole Repo surface demand")
    func legacyInboxSelectionKeepsRepoSurfaceDemand() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let preferences = RepoExplorerSidebarPrefsAtom()
            let capture = makeProjectionInputCapture(
                store: store,
                preferences: preferences,
                atoms: atoms
            )
            let invalidationRecorder = RepoProjectionInvalidationRecorder()

            withObservationTracking {
                capture.observe(.demand, request: nil)
            } onChange: {
                invalidationRecorder.record()
            }
            atoms.workspaceSidebarState.setSidebarSurface(.inbox)

            #expect(atoms.workspaceSidebarState.sidebarSurface == .repos)
            #expect(invalidationRecorder.invalidationCount == 0)
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
            let preferences = RepoExplorerSidebarPrefsAtom()
            let capture = makeProjectionInputCapture(
                store: store,
                preferences: preferences,
                atoms: atoms
            )
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)
            let request = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)
            let tokens = capture.observationTokens(for: request)
            atoms.commandBarSurface.present(scope: .everything, workspaceWindowId: windowId)

            #expect(!tokens.contains(.attention))
        }
    }

    @Test("hidden Panes surface registers no projection inputs")
    func hiddenPanesSurfaceRegistersNoProjectionInputs() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.repo, for: .panes)
            let capture = makeProjectionInputCapture(
                store: store,
                preferences: preferences,
                atoms: atoms
            )
            let adapter = RepoExplorerProjectionAdapter(inputCapture: capture)
            defer { adapter.stop() }

            adapter.updateDemand(isVisible: false, query: "")
            atoms.commandBarSurface.present(
                scope: .everything,
                workspaceWindowId: UUIDv7.generate()
            )
            #expect(adapter.observationTokens.isEmpty)
        }
    }

    @Test("N2a: a focus-only transition wakes the projection input observation gate")
    func projectionInputRevisionObservesFocusTransitions() {
        // The attention observation gate still announces focus transitions to the projection
        // adapter. Active row chips now come from the activity bucket, covered separately.
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.repo, for: .panes)
            let capture = makeProjectionInputCapture(
                store: store,
                preferences: preferences,
                atoms: atoms
            )
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)

            let invalidationRecorder = RepoProjectionInvalidationRecorder()
            withObservationTracking {
                capture.observe(.attention, request: nil)
            } onChange: {
                invalidationRecorder.record()
            }

            atoms.commandBarSurface.present(scope: .everything, workspaceWindowId: windowId)

            #expect(invalidationRecorder.invalidationCount == 1)
        }
    }
}
