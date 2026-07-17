import CoreGraphics
import Foundation

enum WorkspacePersistenceMutationFailure: Equatable, Sendable {
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case drawerCursorApplication(WorkspaceDrawerCursorApplyRejection)
    case drawerCursorCapture(WorkspaceDrawerCursorPersistenceCaptureError)
    case drawerTogglePlanning(WorkspaceDrawerToggleRejection)
    case paneContextPlanning(WorkspacePaneContextTransitionRejection)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
    case paneMissing(UUID)
    case paneTabApplication(WorkspacePaneTabTransitionApplicationRejection)
    case paneWebviewStatePlanning(WorkspacePaneWebviewStateTransitionRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabLeafApplication(WorkspaceTabLeafTransitionApplicationRejection)
    case tabLeafPlanning(WorkspaceTabLeafTransitionRejection)
    case tabCursorCapture(WorkspaceTabCursorPersistenceCaptureError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
    case tabGraphLeafApplication(WorkspaceTabGraphLeafApplyRejection)
    case tabGraphLeafPlanning(WorkspaceTabGraphLeafTransitionRejection)
    case tabShellCapture(WorkspaceTabShellPersistencePreparationError)
    case windowMemory(WorkspaceSnapshotPreparationRejection)
}

enum WorkspacePersistenceMutationResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePersistenceMutationFailure)
}

enum WorkspacePaneCreationPersistenceCommitResult: Equatable, Sendable {
    case committed(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePersistenceMutationFailure)
}

/// Persistence-aware mutation boundary for installed canonical workspace state.
///
/// This coordinator owns no canonical values. It reserves fixed-revision
/// preimages in the long-lived adapters and commits the corresponding atom
/// mutation through the shared revision owner.
@MainActor
final class WorkspacePersistenceMutationCoordinator {
    private let activeArrangementVisibilityGateway: WorkspaceActiveArrangementVisibilityPersistenceGateway
    private let arrangementLifecycleGateway: WorkspaceArrangementLifecyclePersistenceGateway
    private let arrangementSelectionGateway: WorkspaceArrangementSelectionPersistenceGateway
    private let createPaneInExistingTabGateway: WorkspaceCreatePaneInExistingTabPersistenceGateway
    private let crossTabPaneMoveGateway: WorkspaceCrossTabPaneMovePersistenceGateway
    private let layoutResizeGateway: WorkspaceLayoutResizePersistenceGateway
    private let paneResidencyGateway: WorkspacePaneResidencyPersistenceGateway
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    private let workspaceDrawerCursorTransitionApplier: WorkspaceDrawerCursorTransitionApplier
    private let workspacePaneTabTransitionApplier: WorkspacePaneTabTransitionApplier
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let workspacePaneTransitionApplier: WorkspacePaneTransitionApplier
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceTabGraphLeafTransitionApplier: WorkspaceTabGraphLeafTransitionApplier
    private let workspaceTabLeafTransitionApplier: WorkspaceTabLeafTransitionApplier
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    ) {
        activeArrangementVisibilityGateway = WorkspaceActiveArrangementVisibilityPersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
        arrangementLifecycleGateway = WorkspaceArrangementLifecyclePersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
        )
        arrangementSelectionGateway = WorkspaceArrangementSelectionPersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
        )
        createPaneInExistingTabGateway = WorkspaceCreatePaneInExistingTabPersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
        crossTabPaneMoveGateway = WorkspaceCrossTabPaneMovePersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
        layoutResizeGateway = WorkspaceLayoutResizePersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
        )
        paneResidencyGateway = WorkspacePaneResidencyPersistenceGateway(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabShellAtom: workspaceTabShellAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
        workspaceDrawerCursorTransitionApplier = WorkspaceDrawerCursorTransitionApplier(
            workspaceDrawerCursorAtom: workspaceDrawerCursorAtom
        )
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        workspacePaneTransitionApplier = WorkspacePaneTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom
        )
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        workspaceTabGraphLeafTransitionApplier = WorkspaceTabGraphLeafTransitionApplier(
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
        )
        workspaceTabLeafTransitionApplier = WorkspaceTabLeafTransitionApplier(
            workspaceTabShellAtom: workspaceTabShellAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom
        )
        workspacePaneTabTransitionApplier = WorkspacePaneTabTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabTransitionApplier: WorkspaceTabTransitionApplier(
                workspaceTabShellAtom: workspaceTabShellAtom,
                workspaceTabGraphAtom: workspaceTabGraphAtom,
                workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
            )
        )
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceWindowMemoryAtom = workspaceWindowMemoryAtom
    }

    func createPaneInExistingTab(
        _ request: WorkspaceCreatePaneInExistingTabRequest
    ) -> WorkspaceCreatePaneInExistingTabPersistenceResult {
        createPaneInExistingTabGateway.create(request)
    }

    func movePaneAcrossTabs(
        _ request: CrossTabPaneMoveRequest
    ) -> WorkspaceCrossTabPaneMovePersistenceResult {
        crossTabPaneMoveGateway.move(request)
    }

    func selectTab(
        _ request: WorkspaceSelectTabRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceSelectTabTransitionPlanner.plan(request, context: tabLeafPlanningContext) {
            case .changed(let transition):
                performTabLeafTransition(.cursorOnly(transition))
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabLeafPlanning(rejection))
            }
        }
    }

    func renameTab(
        _ request: WorkspaceRenameTabRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceRenameTabTransitionPlanner.plan(request, context: tabLeafPlanningContext) {
            case .changed(let transition):
                performTabLeafTransition(.shellOnly(transition))
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabLeafPlanning(rejection))
            }
        }
    }

    func moveTabByDelta(
        _ request: WorkspaceMoveTabByDeltaRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceMoveTabByDeltaTransitionPlanner.plan(request, context: tabLeafPlanningContext) {
            case .changed(let transition):
                performTabLeafTransition(.shellOnly(transition))
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabLeafPlanning(rejection))
            }
        }
    }

    func reorderAndSelectTab(
        _ request: WorkspaceReorderAndSelectTabRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceReorderAndSelectTabTransitionPlanner.plan(request, context: tabLeafPlanningContext) {
            case .changed(let transition):
                performTabLeafTransition(transition)
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabLeafPlanning(rejection))
            }
        }
    }

    func equalizePanes(
        _ request: WorkspaceEqualizePanesRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceEqualizePanesTransitionPlanner.plan(
                request,
                context: tabGraphLeafPlanningContext(tabID: request.tabID),
                activeArrangement: workspaceArrangementSelection(forTab: request.tabID)
            ) {
            case .changed(let transition):
                performTabGraphLeafTransition(transition)
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabGraphLeafPlanning(rejection))
            }
        }
    }

    func equalizeDrawerPanes(
        _ request: WorkspaceEqualizeDrawerPanesRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceEqualizeDrawerPanesTransitionPlanner.plan(
                request,
                context: tabGraphLeafPlanningContext(tabID: request.tabID),
                activeArrangement: workspaceArrangementSelection(forTab: request.tabID)
            ) {
            case .changed(let transition):
                performTabGraphLeafTransition(transition)
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabGraphLeafPlanning(rejection))
            }
        }
    }

    func renameArrangement(
        _ request: WorkspaceRenameArrangementRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceRenameArrangementTransitionPlanner.plan(
                request,
                context: tabGraphLeafPlanningContext(tabID: request.tabID)
            ) {
            case .changed(let transition):
                performTabGraphLeafTransition(transition)
            case .unchanged:
                .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                .rejected(.tabGraphLeafPlanning(rejection))
            }
        }
    }

    func setActivePane(
        _ request: WorkspaceSetActivePaneRequest
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        arrangementSelectionGateway.setActivePane(request)
    }

    func setActiveDrawerChild(
        _ request: WorkspaceSetActiveDrawerChildRequest
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        arrangementSelectionGateway.setActiveDrawerChild(request)
    }

    func createArrangement(
        _ request: WorkspaceCreateArrangementRequest
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        arrangementLifecycleGateway.createArrangement(request)
    }

    func removeArrangement(
        _ request: WorkspaceRemoveArrangementRequest
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        arrangementLifecycleGateway.removeArrangement(request)
    }

    func applyLayoutResizeCheckpoint(
        _ checkpoint: WorkspaceLayoutResizeCheckpoint
    ) -> WorkspaceLayoutResizePersistenceResult {
        layoutResizeGateway.apply(checkpoint)
    }

    func resizePaneByDelta(
        _ request: WorkspaceKeyboardResizeRequest
    ) -> WorkspaceKeyboardResizePersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        let context: WorkspaceKeyboardResizePlanningContext
        if let tab = workspaceTabGraphAtom.tabState(request.tabID) {
            let activeArrangement =
                workspaceArrangementCursorAtom.activeArrangementId(forTab: request.tabID)
                .map(WorkspaceActiveArrangementSelection.selected)
                ?? .missing
            let zoom =
                workspacePanePresentationAtom.zoomedPaneId(forTab: request.tabID)
                .map(WorkspaceZoomSelection.zoomed)
                ?? .notZoomed
            context = .present(
                tab: tab,
                activeArrangement: activeArrangement,
                zoom: zoom
            )
        } else {
            context = .missingTab
        }

        switch WorkspaceKeyboardResizeCheckpointPlanner.plan(request, context: context) {
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection):
            return .rejected(.planning(rejection))
        case .changed(let checkpoint):
            switch layoutResizeGateway.apply(checkpoint) {
            case .changed(let revision):
                return .changed(revision: revision)
            case .unchanged(let revision):
                return .unchanged(revision: revision)
            case .rejected(let failure):
                return .rejected(.layoutResize(failure))
            }
        }
    }

    func switchArrangement(
        _ request: WorkspaceSwitchArrangementRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        activeArrangementVisibilityGateway.switchArrangement(request)
    }

    func setShowsMinimizedPanes(
        _ request: WorkspaceSetShowsMinimizedPanesRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        activeArrangementVisibilityGateway.setShowsMinimizedPanes(request)
    }

    func minimizePane(
        _ request: WorkspaceMinimizePaneRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        activeArrangementVisibilityGateway.minimizePane(request)
    }

    func expandPane(
        _ request: WorkspaceExpandPaneRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        activeArrangementVisibilityGateway.expandPane(request)
    }

    func backgroundPane(
        _ request: WorkspaceBackgroundPaneRequest,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyPersistenceResult {
        paneResidencyGateway.backgroundPane(
            request,
            retainedDrawerPayload: retainedDrawerPayload
        )
    }

    func reactivatePane(
        _ request: WorkspaceReactivatePaneRequest,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyPersistenceResult {
        paneResidencyGateway.reactivatePane(
            request,
            retainedDrawerPayload: retainedDrawerPayload
        )
    }

    func toggleDrawer(
        _ request: WorkspaceDrawerToggleRequest
    ) -> WorkspacePersistenceMutationResult {
        guardCompositionDomainIsInstalled {
            switch WorkspaceDrawerToggleTransitionPlanner.plan(
                request,
                currentPaneState: workspacePaneGraphAtom.paneState(request.parentPaneID),
                currentExpandedDrawerID: workspaceDrawerCursorAtom.expandedDrawerId
            ) {
            case .changed(let transition):
                performDrawerToggleTransition(transition)
            case .rejected(let rejection):
                .rejected(.drawerTogglePlanning(rejection))
            }
        }
    }

    func commitPaneCreation(
        _ transition: WorkspacePaneCreationTransition
    ) -> WorkspacePaneCreationPersistenceCommitResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        let preparedApplication: WorkspacePreparedPaneTabTransitionApplication
        switch workspacePaneTabTransitionApplier.preflight(
            paneState: transition.paneState,
            tabTransition: transition.tabTransition
        ) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.paneTabApplication(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try capturePaneCreationPreimages(
                    transition,
                    for: preparation
                )
                return preparation.commit { [workspacePaneTabTransitionApplier] in
                    workspacePaneTabTransitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .committed(revision: committedRevision)
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspaceTabShellPersistencePreparationError {
            return .rejected(.tabShellCapture(error))
        } catch let error as WorkspaceTabCursorPersistenceCaptureError {
            return .rejected(.tabCursorCapture(error))
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("pane-creation persistence mutation emitted an unmodeled error")
        }
    }

    func updatePaneTitle(
        _ request: WorkspacePaneTitleUpdateRequest
    ) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }

        switch WorkspacePaneTitleTransitionPlanner.plan(
            request,
            currentPaneState: workspacePaneGraphAtom.paneState(request.paneID)
        ) {
        case .changed(let transition):
            return performPaneTransition(transition)
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(.paneMissing(let paneID)):
            return .rejected(.paneMissing(paneID))
        case .rejected(.paneIdentityMismatch(let requestedPaneID, let currentPaneID)):
            return .rejected(
                .paneIdentityMismatch(
                    requestedPaneID: requestedPaneID,
                    currentPaneID: currentPaneID
                )
            )
        }
    }

    func updatePaneMetadata(
        _ request: WorkspacePaneMetadataUpdateRequest
    ) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }

        switch WorkspacePaneMetadataTransitionPlanner.plan(
            request,
            currentPaneState: workspacePaneGraphAtom.paneState(request.paneID)
        ) {
        case .changed(let transition):
            return performPaneTransition(transition)
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(.paneMissing(let paneID)):
            return .rejected(.paneMissing(paneID))
        case .rejected(.paneIdentityMismatch(let requestedPaneID, let currentPaneID)):
            return .rejected(
                .paneIdentityMismatch(
                    requestedPaneID: requestedPaneID,
                    currentPaneID: currentPaneID
                )
            )
        }
    }

    func updatePaneContext(
        _ request: WorkspacePaneContextUpdateRequest
    ) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }

        switch WorkspacePaneContextTransitionPlanner.plan(
            request,
            currentPaneState: workspacePaneGraphAtom.paneState(request.paneID)
        ) {
        case .changed(let transition):
            return performPaneTransition(transition)
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection):
            return .rejected(.paneContextPlanning(rejection))
        }
    }

    func updatePaneWebviewState(
        _ request: WorkspacePaneWebviewStateUpdateRequest
    ) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }

        switch WorkspacePaneWebviewStateTransitionPlanner.plan(
            request,
            currentPaneState: workspacePaneGraphAtom.paneState(request.paneID)
        ) {
        case .changed(let transition):
            return performPaneTransition(transition)
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection):
            return .rejected(.paneWebviewStatePlanning(rejection))
        }
    }

    func setSidebarWidth(_ sidebarWidth: CGFloat) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        guard workspaceWindowMemoryAtom.sidebarWidth != sidebarWidth else {
            return .unchanged(revision: revisionOwner.committedRevision)
        }
        return performWindowMemoryMutation { [workspaceWindowMemoryAtom] in
            workspaceWindowMemoryAtom.setSidebarWidth(sidebarWidth)
        }
    }

    func setWindowFrame(_ windowFrame: CGRect) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        guard workspaceWindowMemoryAtom.windowFrame != windowFrame else {
            return .unchanged(revision: revisionOwner.committedRevision)
        }
        return performWindowMemoryMutation { [workspaceWindowMemoryAtom] in
            workspaceWindowMemoryAtom.setWindowFrame(windowFrame)
        }
    }

    private func performWindowMemoryMutation(
        _ mutate: @escaping @MainActor () -> Void
    ) -> WorkspacePersistenceMutationResult {
        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceWindowMemory.capturePersistencePreimage(
                    .currentWindowMemory,
                    for: preparation
                )
                return preparation.commit {
                    mutate()
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspaceWindowMemorySnapshotPreparationError {
            return .rejected(.windowMemory(error.rejection))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("window-memory persistence mutation emitted an unmodeled error")
        }
    }

    private var tabLeafPlanningContext: WorkspaceTabLeafPlanningContext {
        WorkspaceTabLeafPlanningContext(
            tabShells: workspaceTabShellAtom.tabShells,
            activeTab: workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected)
                ?? .noSelection
        )
    }

    private func workspaceArrangementSelection(
        forTab tabID: UUID
    ) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected)
            ?? .missing
    }

    private func guardCompositionDomainIsInstalled(
        _ mutation: () -> WorkspacePersistenceMutationResult
    ) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        return mutation()
    }

    private func performTabLeafTransition(
        _ transition: WorkspaceReorderAndSelectTabTransition
    ) -> WorkspacePersistenceMutationResult {
        let preparedApplication: WorkspacePreparedTabLeafTransitionApplication
        switch workspaceTabLeafTransitionApplier.preflight(transition) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.tabLeafApplication(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try captureTabLeafPreimages(transition, for: preparation)
                return preparation.commit { [workspaceTabLeafTransitionApplier] in
                    workspaceTabLeafTransitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspaceTabShellPersistencePreparationError {
            return .rejected(.tabShellCapture(error))
        } catch let error as WorkspaceTabCursorPersistenceCaptureError {
            return .rejected(.tabCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("tab-leaf persistence mutation emitted an unmodeled error")
        }
    }

    private func performTabGraphLeafTransition(
        _ transition: WorkspaceTabGraphLeafTransition
    ) -> WorkspacePersistenceMutationResult {
        let preparedApplication: WorkspacePreparedTabGraphLeafApplication
        switch workspaceTabGraphLeafTransitionApplier.preflight(transition) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.tabGraphLeafApplication(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    WorkspaceTabGraphPersistenceCapture(
                        operations: [.valueChange(transition.previousTab.tabId)]
                    ),
                    for: preparation
                )
                return preparation.commit { [workspaceTabGraphLeafTransitionApplier] in
                    workspaceTabGraphLeafTransitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("tab-graph leaf persistence mutation emitted an unmodeled error")
        }
    }

    private func tabGraphLeafPlanningContext(
        tabID: UUID
    ) -> WorkspaceTabGraphLeafPlanningContext {
        workspaceTabGraphAtom.tabState(tabID)
            .map(WorkspaceTabGraphLeafPlanningContext.present) ?? .missingTab
    }

    private func performDrawerToggleTransition(
        _ transition: WorkspaceDrawerToggleTransition
    ) -> WorkspacePersistenceMutationResult {
        let preparedApplication: WorkspacePreparedDrawerCursorApplication
        switch workspaceDrawerCursorTransitionApplier.preflight(transition) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.drawerCursorApplication(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceDrawerCursor.capturePersistencePreimage(
                    transition.persistenceCapture,
                    for: preparation
                )
                return preparation.commit { [workspaceDrawerCursorTransitionApplier] in
                    workspaceDrawerCursorTransitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspaceDrawerCursorPersistenceCaptureError {
            return .rejected(.drawerCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("drawer-toggle persistence mutation emitted an unmodeled error")
        }
    }

    private func captureTabLeafPreimages(
        _ transition: WorkspaceReorderAndSelectTabTransition,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        switch transition {
        case .shellOnly(let shells):
            try captureTabShellPreimages(shells, for: preparation)
        case .cursorOnly(let cursor):
            try captureTabCursorPreimage(cursor, for: preparation)
        case .shellAndCursor(let shells, let cursor):
            try captureTabShellPreimages(shells, for: preparation)
            try captureTabCursorPreimage(cursor, for: preparation)
        }
    }

    private func captureTabShellPreimages(
        _ transition: WorkspaceTabShellCollectionTransition,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        try adapters.workspaceTabShell.capturePersistencePreimages(
            WorkspaceTabShellPersistenceCapture(
                operations: transition.affectedShells.map { .valueChange($0.previous.shell.id) }
            ),
            for: preparation
        )
    }

    private func captureTabCursorPreimage(
        _ transition: WorkspaceTabCursorReplacement,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let capture: WorkspaceTabCursorPersistenceCapture
        switch (transition.previous, transition.replacement) {
        case (.noSelection, .selected):
            capture = .insertion
        case (.selected, .selected):
            capture = .valueChange
        case (.selected, .noSelection):
            capture = .removal
        case (.noSelection, .noSelection):
            preconditionFailure("a changed tab-cursor transition cannot preserve no selection")
        }
        try adapters.workspaceTabCursor.capturePersistencePreimage(capture, for: preparation)
    }

    private func capturePaneCreationPreimages(
        _ transition: WorkspacePaneCreationTransition,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let tabID = transition.tab.id
        try adapters.workspacePaneGraph.capturePersistencePreimages(
            WorkspacePaneGraphPersistenceCapture(
                operations: [.insertion(transition.paneState.id)]
            ),
            for: preparation
        )
        try adapters.workspaceTabShell.capturePersistencePreimages(
            WorkspaceTabShellPersistenceCapture(
                operations: [.insertion(tabID)]
            ),
            for: preparation
        )
        try adapters.workspaceTabCursor.capturePersistencePreimage(
            workspaceTabShellAtom.activeTabId == nil ? .insertion : .valueChange,
            for: preparation
        )
        try adapters.workspaceTabGraph.capturePersistencePreimages(
            WorkspaceTabGraphPersistenceCapture(
                operations: [.insertion(tabID)]
            ),
            for: preparation
        )

        let activeArrangementCaptures = transition.tabTransition.activeArrangement.persistenceCaptures
        let activePaneCaptures = transition.tabTransition.activePanes.map(\.persistenceCapture)
        let activeDrawerCaptures = transition.tabTransition.activeDrawerChildren.map(\.persistenceCapture)
        try adapters.workspaceArrangementCursor.capturePersistencePreimages(
            WorkspaceArrangementCursorPersistenceCapture(
                activeArrangements: activeArrangementCaptures,
                activePanes: activePaneCaptures,
                activeDrawerChildren: activeDrawerCaptures
            ),
            for: preparation
        )
    }

    private func performPaneTransition(
        _ transition: WorkspacePaneGraphTransition
    ) -> WorkspacePersistenceMutationResult {
        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspacePaneGraph.capturePersistencePreimages(
                    WorkspacePaneGraphPersistenceCapture(
                        operations: transition.replacements.map { .valueChange($0.paneID) }
                    ),
                    for: preparation
                )
                return preparation.commit { [workspacePaneTransitionApplier] in
                    workspacePaneTransitionApplier.apply(transition)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("pane persistence mutation emitted an unmodeled error")
        }
    }
}

extension WorkspaceActiveArrangementTransition {
    fileprivate var persistenceCaptures: [WorkspaceActiveArrangementPersistenceCapture] {
        switch self {
        case .insert(let tabID, _):
            [.insertion(tabID: tabID)]
        }
    }
}

extension WorkspaceActivePaneTransition {
    fileprivate var persistenceCapture: WorkspaceActivePanePersistenceCapture {
        switch self {
        case .insert(let arrangementID, _):
            .insertion(arrangementID: arrangementID)
        }
    }
}

extension WorkspaceActiveDrawerChildTransition {
    fileprivate var persistenceCapture: WorkspaceActiveDrawerChildPersistenceCapture {
        switch self {
        case .insert(let key, _):
            .insertion(key)
        }
    }
}

extension WorkspaceDrawerToggleTransition {
    fileprivate var persistenceCapture: WorkspaceDrawerCursorPersistenceCapture {
        switch operation {
        case .expand(let drawerID):
            .insertion(drawerID)
        case .collapse(let drawerID):
            .removal(drawerID)
        case .switchExpandedDrawer(let previousDrawerID, let replacementDrawerID):
            .replacement(removing: previousDrawerID, inserting: replacementDrawerID)
        }
    }
}
