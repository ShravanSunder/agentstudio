import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Mount a Bridge controller for `receiver`, constructed from the explicit
    /// source inputs its navigation record supplies. A standalone Bridge pane
    /// is its own receiver; a Zoom companion renders its terminal's receiver.
    func createBridgePaneView(
        for pane: Pane,
        state: BridgePaneState,
        receiver explicitReceiver: BridgeReceiver? = nil,
        viewerOpenTelemetryAnchor: BridgeViewerOpenTelemetryAnchor? = nil
    ) -> BridgePaneMountView {
        let receiver = explicitReceiver ?? .standalone(pane.id)
        if receiver.kind == .standaloneBridge {
            bridgeNavigationCommandHandler.ensureRecord(
                for: receiver,
                seedingKnownWorktreeId: pane.metadata.worktreeId
            )
        }
        let sourceConfiguration = BridgePaneSourceConfiguration(
            review: bridgeNavigationCommandHandler.reviewBinding(for: receiver),
            files: bridgeNavigationCommandHandler.filesBinding(for: receiver)
        )
        ensureBridgePaneActivityAuthority(for: pane.id)
        let controller = BridgePaneController(
            paneId: pane.id,
            state: state,
            sourceConfiguration: sourceConfiguration,
            appRootURL: Bundle.bridgeAppRootURL,
            metadata: bridgePaneControllerMetadata(
                for: pane,
                state: state,
                reviewRootPath: sourceConfiguration.review?.worktreeRootPath
            ),
            reviewSourceProvider: bridgeReviewSourceProvider(
                for: pane,
                reviewRootPath: sourceConfiguration.review?.worktreeRootPath
            ),
            gitReadContext: bridgeGitReadContext(
                for: pane,
                reviewRootPath: sourceConfiguration.review?.worktreeRootPath
            ),
            fileGitReadScheduler: bridgeGitReadScheduler,
            worktreeProductConstructionCoordinator: worktreeProductConstructionCoordinator,
            worktreeAnnotationStore: worktreeAnnotationStore,
            worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator,
            gitWorkingTreeStatusProvider: gitWorkingTreeStatusProvider,
            traceRuntime: traceRuntime,
            viewerOpenTelemetryAnchor: viewerOpenTelemetryAnchor,
            initialPaneActivity: .dormant,
            initialContributionTargetCommit: bridgeNavigationCommandHandler.reviewComparisonCommit(
                for: receiver,
                binding: sourceConfiguration.review,
                onlyIfAbsent: true
            ),
            contributionTargetCommit: bridgeNavigationCommandHandler.reviewComparisonCommit(
                for: receiver,
                binding: sourceConfiguration.review,
                onlyIfAbsent: false
            )
        )
        let view = BridgePaneMountView(paneId: pane.id, controller: controller)
        registerHostedView(mountedView: view, for: pane.id)
        refreshBridgePaneActivities()
        registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
        controller.loadApp()
        Self.logger.info("Created bridge panel view for pane \(pane.id)")
        return view
    }
}
