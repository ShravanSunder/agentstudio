import Foundation

enum WorkspaceVisibilityPersistenceFailure: Equatable, Sendable {
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case planning(WorkspaceActiveArrangementVisibilityRejection)
    case application(WorkspaceVisibilityApplyRejection)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
}

enum WorkspaceVisibilityPersistenceResult: Equatable, Sendable {
    case changed(
        revision: WorkspacePersistenceRevision,
        effect: WorkspaceActiveArrangementVisibilityEffect
    )
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceVisibilityPersistenceFailure)
}

/// Owns fixed-revision persistence for discrete active-arrangement visibility mutations.
@MainActor
// swiftlint:disable:next type_name
final class WorkspaceActiveArrangementVisibilityPersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let transitionApplier: WorkspaceVisibilityTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        transitionApplier = WorkspaceVisibilityTransitionApplier(
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
    }

    func switchArrangement(
        _ request: WorkspaceSwitchArrangementRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        guardInstalled {
            commit(
                WorkspaceSwitchArrangementTransitionPlanner.plan(
                    request,
                    context: WorkspaceSwitchArrangementPlanningContext(
                        tab: tabWitness(request.tabID),
                        activeArrangement: activeArrangementSelection(request.tabID),
                        targetPaneCursor: paneCursorWitness(request.arrangementID),
                        zoom: zoomSelection(request.tabID)
                    )
                )
            )
        }
    }

    func setShowsMinimizedPanes(
        _ request: WorkspaceSetShowsMinimizedPanesRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        guardInstalled {
            commit(
                WorkspaceSetShowsMinimizedPanesTransitionPlanner.plan(
                    request,
                    context: WorkspaceSetShowsMinimizedPanesPlanningContext(
                        tab: tabWitness(request.tabID),
                        activeArrangement: activeArrangementSelection(request.tabID)
                    )
                )
            )
        }
    }

    func minimizePane(
        _ request: WorkspaceMinimizePaneRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        guardInstalled {
            commit(
                WorkspaceMinimizePaneTransitionPlanner.plan(
                    request,
                    context: WorkspaceMinimizePanePlanningContext(
                        tab: tabWitness(request.tabID),
                        activeArrangementPaneCursor: activeArrangementPaneCursorWitness(
                            request.tabID
                        ),
                        zoom: zoomSelection(request.tabID)
                    )
                )
            )
        }
    }

    func expandPane(
        _ request: WorkspaceExpandPaneRequest
    ) -> WorkspaceVisibilityPersistenceResult {
        guardInstalled {
            commit(
                WorkspaceExpandPaneTransitionPlanner.plan(
                    request,
                    context: WorkspaceExpandPanePlanningContext(
                        tab: tabWitness(request.tabID),
                        activeArrangementPaneCursor: activeArrangementPaneCursorWitness(
                            request.tabID
                        )
                    )
                )
            )
        }
    }

    private func tabWitness(_ tabID: UUID) -> WorkspaceTabGraphStateWitness {
        workspaceTabGraphAtom.tabState(tabID)
            .map(WorkspaceTabGraphStateWitness.present) ?? .missing
    }

    private func activeArrangementSelection(
        _ tabID: UUID
    ) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activeArrangementPaneCursorWitness(
        _ tabID: UUID
    ) -> WorkspaceActiveArrangementPaneCursorWitness {
        guard let arrangementID = workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
        else {
            return .missing
        }
        return .selected(
            arrangementID: arrangementID,
            paneCursor: paneCursorWitness(arrangementID)
        )
    }

    private func paneCursorWitness(
        _ arrangementID: UUID
    ) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else {
            return .missing
        }
        let selection =
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
            .map(WorkspacePaneSelection.selected) ?? .noSelection
        return .present(selection)
    }

    private func zoomSelection(_ tabID: UUID) -> WorkspaceZoomSelection {
        workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
    }

    private func guardInstalled(
        _ mutation: () -> WorkspaceVisibilityPersistenceResult
    ) -> WorkspaceVisibilityPersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        return mutation()
    }

    private func commit(
        _ decision: WorkspaceVisibilityTransitionDecision
    ) -> WorkspaceVisibilityPersistenceResult {
        switch decision {
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection):
            return .rejected(.planning(rejection))
        case .changed(let transition):
            return commit(transition)
        }
    }

    private func commit(
        _ transition: WorkspaceActiveArrangementVisibilityTransition
    ) -> WorkspaceVisibilityPersistenceResult {
        let preparedApplication: WorkspacePreparedVisibilityApplication
        switch transitionApplier.preflight(transition) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.application(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try capturePreimages(transition, for: preparation)
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision, effect: transition.effect)
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("visibility persistence gateway emitted an unmodeled error")
        }
    }

    private func capturePreimages(
        _ transition: WorkspaceActiveArrangementVisibilityTransition,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        if case .replace(let tabID, _, _) = transition.tabGraph {
            try adapters.workspaceTabGraph.capturePersistencePreimages(
                WorkspaceTabGraphPersistenceCapture(operations: [.valueChange(tabID)]),
                for: preparation
            )
        }

        let activeArrangementCaptures: [WorkspaceActiveArrangementPersistenceCapture]
        switch transition.activeArrangement {
        case .witness:
            activeArrangementCaptures = []
        case .insert(let tabID, _):
            activeArrangementCaptures = [.insertion(tabID: tabID)]
        case .replace(let tabID, _, _):
            activeArrangementCaptures = [.valueChange(tabID: tabID)]
        }

        let activePaneCaptures: [WorkspaceActivePanePersistenceCapture]
        switch transition.activePane {
        case .notRead, .witness:
            activePaneCaptures = []
        case .insert(let arrangementID, _, _):
            activePaneCaptures = [.insertion(arrangementID: arrangementID)]
        case .replace(let arrangementID, _, _):
            activePaneCaptures = [.valueChange(arrangementID: arrangementID)]
        case .remove(let arrangementID, _):
            activePaneCaptures = [.removal(arrangementID: arrangementID)]
        }

        guard !activeArrangementCaptures.isEmpty || !activePaneCaptures.isEmpty else {
            return
        }
        try adapters.workspaceArrangementCursor.capturePersistencePreimages(
            WorkspaceArrangementCursorPersistenceCapture(
                activeArrangements: activeArrangementCaptures,
                activePanes: activePaneCaptures,
                activeDrawerChildren: []
            ),
            for: preparation
        )
    }
}
