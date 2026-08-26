import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func createBridgePaneView(
        for pane: Pane,
        state: BridgePaneState,
        initialContributionTargetCommit:
            (@MainActor @Sendable (WorkspaceReviewContributionTarget) -> BridgePaneStateMutationResult)? = nil,
        contributionTargetCommit:
            (@MainActor @Sendable (WorkspaceReviewContributionTarget) -> BridgePaneStateMutationResult)? = nil
    ) -> BridgePaneMountView {
        ensureBridgePaneActivityAuthority(for: pane.id)
        let controller = BridgePaneController(
            paneId: pane.id,
            state: state,
            appRootURL: Bundle.bridgeAppRootURL,
            metadata: bridgePaneControllerMetadata(for: pane, state: state),
            reviewSourceProvider: bridgeReviewSourceProvider(for: pane, state: state),
            gitReadContext: bridgeGitReadContext(for: pane, state: state),
            worktreeProductConstructionCoordinator: worktreeProductConstructionCoordinator,
            worktreeAnnotationStore: worktreeAnnotationStore,
            worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator,
            traceRuntime: traceRuntime,
            initialPaneActivity: .dormant,
            initialContributionTargetCommit: initialContributionTargetCommit
                ?? { [weak self] target in
                    guard let self else { return .paneMissing }
                    return store.paneAtom.setInitialBridgeContributionTargetIfAbsent(
                        pane.id,
                        target: target
                    )
                },
            contributionTargetCommit: contributionTargetCommit
                ?? { [weak self] target in
                    guard let self else { return .paneMissing }
                    return store.paneAtom.setBridgeContributionTarget(
                        pane.id,
                        target: target
                    )
                }
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
