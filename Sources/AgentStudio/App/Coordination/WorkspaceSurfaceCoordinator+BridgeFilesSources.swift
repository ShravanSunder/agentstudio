import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Push each mounted Bridge its receiver's current Files input. Members that
    /// became known or temporarily unknown since construction reach the mounted
    /// collection in place; nothing here recreates a controller.
    ///
    /// Runs once per applied topology change. Per mounted Bridge it is one
    /// record lookup, one in-memory catalog lookup per member and one binding
    /// comparison; unchanged bindings stop there. No filesystem or Git I/O.
    func refreshMountedBridgeFilesSources() {
        for (paneId, view) in viewRegistry.allBridgeViews {
            guard let receiver = mountedBridgeReceiver(forPaneId: paneId),
                let files = bridgeNavigationCommandHandler.filesBinding(for: receiver)
            else { continue }
            view.controller.enqueueFilesSourceUpdate(files)
        }
    }

    /// The receiver a mounted Bridge pane renders: its terminal's receiver for a
    /// Zoom companion, or the standalone Bridge pane itself.
    func mountedBridgeReceiver(forPaneId paneId: UUID) -> BridgeReceiver? {
        if let sourcePaneId = store.panePresentationAtom.zoomCompanionsBySourcePaneId
            .first(where: { $0.value.companionPaneId == paneId })?.key
        {
            return .terminal(sourcePaneId)
        }
        return store.paneAtom.pane(paneId) == nil ? nil : .standalone(paneId)
    }
}
