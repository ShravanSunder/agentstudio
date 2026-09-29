import AgentStudioBridge
import AgentStudioCore
import Foundation

private enum BridgeFilesBindingInvariantFailure: String {
    case missingPreparedSlot = "Bridge receiver has no prepared Files slot or creation seed"
}

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
        let filesBinding: BridgeFilesSourceBinding?
        if let prepared = bridgeNavigationCommandHandler.filesBinding(for: receiver) {
            filesBinding = prepared
        } else if bridgeNavigationCommandHandler.record(for: receiver) != nil {
            assertionFailure(BridgeFilesBindingInvariantFailure.missingPreparedSlot.rawValue)
            Self.logger.error("Bridge receiver Files input missing at view creation")
            let ownWorktreeId = store.paneAtom.pane(receiver.paneId)?.metadata.worktreeId
            let seed = bridgeNavigationCommandHandler.bridgeFilesSeedBinding(
                for: receiver, ownWorktreeId: ownWorktreeId)
            store.bridgeNavigationAtom.assignPreparedFilesBinding(seed, for: receiver, ticket: 0)
            filesBinding = seed
        } else {
            filesBinding = nil
        }
        let sourceConfiguration = BridgePaneSourceConfiguration(
            review: bridgeNavigationCommandHandler.reviewBinding(for: receiver),
            files: filesBinding
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
        bindDisplayedFilesSelection(of: controller, to: receiver)
        let view = BridgePaneMountView(paneId: pane.id, controller: controller)
        registerHostedView(mountedView: view, for: pane.id)
        refreshBridgePaneActivities()
        registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
        controller.loadApp()
        Self.logger.info("Created bridge panel view for pane \(pane.id)")
        return view
    }
}
