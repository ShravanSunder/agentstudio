import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import Foundation

extension AppDelegate {
    func captureScrollbackForTermination() async {
        guard let snapshotter = workspaceSurfaceCoordinator?.scrollbackSnapshotter else { return }
        await captureScrollbackBeforeSurfaceShutdown(
            snapshotter: snapshotter, budget: AppPolicies.Restore.quitCaptureBudget,
            shutdown: { await snapshotter.shutdown() })
    }

    func installScrollbackSnapshotter(using backend: ZmxBackend) {
        guard let datastore = workspaceSQLiteDatastore else { return }
        let workspaceID = store.identityAtom.workspaceId
        let scrollback = ScrollbackStore()
        scrollbackStore = scrollback
        workspaceSurfaceCoordinator.scrollbackSnapshotter = ScrollbackSnapshotter(
            clock: ContinuousClock(), store: scrollback,
            inventory: { await backend.discoverSessionInventory() },
            paneBindings: { try await datastore.scrollbackPaneBindings(workspaceID: workspaceID) },
            capture: { await backend.captureHistory($0) }, delay: .taskSleep)
    }
}
