import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer availability capture", .serialized)
struct RepoExplorerAvailabilityCaptureTests {
    @Test("unavailable repositories leave capture while their panes remain unassociated")
    func unavailableRepositoryDoesNotHidePane() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repository = store.addRepo(at: URL(fileURLWithPath: "/tmp/availability-capture"))
            let worktree = try #require(repository.worktrees.first)
            let pane = store.createPane(launchDirectory: worktree.path, facets: .init(cwd: worktree.path))
            store.appendTab(Tab(paneId: pane.id))
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: RepoExplorerSidebarPrefsAtom(),
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil }
            )
            let before = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)
            #expect(before.snapshot.repos.map(\.id) == [repository.id])
            let observation = AvailabilityObservationProbe()
            withObservationTracking {
                capture.observe(.membership, request: before)
            } onChange: {
                MainActor.assumeIsolated { observation.changed = true }
            }

            store.markRepoUnavailable(repository.id)

            let after = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)
            #expect(after.snapshot.repos.isEmpty)
            #expect(observation.changed)
            #expect(store.pane(pane.id)?.residency == .active)
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let panes = capture.captureRequest(query: "", referenceDate: Date(), trigger: .surfaceSwitch)
            #expect(panes.snapshot.unassociatedPaneLocations.contains { $0.paneId == pane.id })
        }
    }
}

@MainActor
private final class AvailabilityObservationProbe {
    var changed = false
}
