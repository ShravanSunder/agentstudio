import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func createBridgePaneView(
        for pane: Pane,
        state: BridgePaneState
    ) -> BridgePaneMountView {
        ensureBridgePaneActivityAuthority(for: pane.id)
        let controller = BridgePaneController(
            paneId: pane.id,
            state: state,
            metadata: bridgePaneControllerMetadata(for: pane, state: state),
            reviewSourceProvider: bridgeReviewSourceProvider(for: pane, state: state),
            gitReadContext: bridgeGitReadContext(for: pane, state: state),
            worktreeProductConstructionCoordinator: worktreeProductConstructionCoordinator,
            traceRuntime: traceRuntime,
            initialPaneActivity: .dormant
        )
        let view = BridgePaneMountView(paneId: pane.id, controller: controller)
        registerHostedView(mountedView: view, for: pane.id)
        refreshBridgePaneActivities()
        registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
        controller.loadApp()
        controller.scheduleInitialReviewPackageLoadIfPossible()
        Self.logger.info("Created bridge panel view for pane \(pane.id)")
        return view
    }
}
