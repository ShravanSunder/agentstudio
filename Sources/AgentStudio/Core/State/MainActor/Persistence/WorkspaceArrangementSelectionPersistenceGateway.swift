import Foundation

enum WorkspaceArrangementSelectionPersistenceFailure: Equatable, Sendable {
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case planning(WorkspaceArrangementSelectionRejection)
    case application(WorkspaceArrangementSelectionApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
}

enum WorkspaceArrangementSelectionPersistenceResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceArrangementSelectionPersistenceFailure)
}

/// Owns fixed-revision persistence for discrete active-pane selection mutations.
@MainActor
final class WorkspaceArrangementSelectionPersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let transitionApplier: WorkspaceArrangementSelectionTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        transitionApplier = .init(
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
        )
    }

    func setActivePane(
        _ request: WorkspaceSetActivePaneRequest
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        guardInstalled {
            commit(
                WorkspaceSetActivePaneTransitionPlanner.plan(
                    request,
                    context: activePanePlanningContext(tabID: request.tabID)
                )
            )
        }
    }

    func setActiveDrawerChild(
        _ request: WorkspaceSetActiveDrawerChildRequest
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        guardInstalled {
            commit(
                WorkspaceSetActiveDrawerChildTransitionPlanner.plan(
                    request,
                    context: activeDrawerChildPlanningContext(request: request)
                )
            )
        }
    }

    private func activePanePlanningContext(
        tabID: UUID
    ) -> WorkspaceActivePaneSelectionPlanningContext {
        guard let tab = workspaceTabGraphAtom.tabState(tabID) else { return .missingTab }
        guard let arrangementID = workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID) else {
            return .missingActiveArrangement(tab: tab)
        }
        let cursor: WorkspaceActivePaneCursorWitness
        if workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) {
            cursor = .present(
                workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                    .map(WorkspacePaneSelection.selected) ?? .noSelection
            )
        } else {
            cursor = .missing
        }
        return .selectedActiveArrangement(
            tab: tab,
            arrangementID: arrangementID,
            cursor: cursor
        )
    }

    private func activeDrawerChildPlanningContext(
        request: WorkspaceSetActiveDrawerChildRequest
    ) -> WorkspaceActiveDrawerChildSelectionPlanningContext {
        guard let tab = workspaceTabGraphAtom.tabState(request.tabID) else { return .missingTab }
        guard let arrangementID = workspaceArrangementCursorAtom.activeArrangementId(forTab: request.tabID) else {
            return .missingActiveArrangement(tab: tab)
        }
        let cursorKey = ArrangementDrawerCursorKey(
            arrangementId: arrangementID,
            drawerId: request.drawerID
        )
        let cursor: WorkspaceActiveDrawerChildCursorWitness
        if workspaceArrangementCursorAtom.hasDrawerCursor(cursorKey) {
            cursor = .present(
                workspaceArrangementCursorAtom.activeChildId(
                    forArrangement: arrangementID,
                    drawerId: request.drawerID
                ).map(WorkspaceDrawerChildSelection.selected) ?? .noSelection
            )
        } else {
            cursor = .missing
        }
        return .selectedActiveArrangement(
            tab: tab,
            arrangementID: arrangementID,
            cursor: cursor
        )
    }

    private func guardInstalled(
        _ mutation: () -> WorkspaceArrangementSelectionPersistenceResult
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(.compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase))
        }
        return mutation()
    }

    private func commit(
        _ decision: WorkspaceArrangementSelectionDecision
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        switch decision {
        case .unchanged:
            .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection):
            .rejected(.planning(rejection))
        case .changed(let transition):
            commit(transition)
        }
    }

    private func commit(
        _ transition: WorkspaceArrangementSelectionTransition
    ) -> WorkspaceArrangementSelectionPersistenceResult {
        let preparedApplication: WorkspacePreparedArrangementSelectionApplication
        switch transitionApplier.preflight(transition) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.application(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceArrangementCursor.capturePersistencePreimages(
                    transition.persistenceCapture,
                    for: preparation
                )
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("arrangement selection persistence gateway emitted an unmodeled error")
        }
    }
}

extension WorkspaceArrangementSelectionTransition {
    fileprivate var persistenceCapture: WorkspaceArrangementCursorPersistenceCapture {
        switch self {
        case .activePane(let transition):
            .init(
                activeArrangements: [],
                activePanes: [transition.mutation.persistenceCapture],
                activeDrawerChildren: []
            )
        case .activeDrawerChild(let transition):
            .init(
                activeArrangements: [],
                activePanes: [],
                activeDrawerChildren: [transition.mutation.persistenceCapture]
            )
        }
    }
}

extension WorkspaceActivePaneSelectionMutation {
    fileprivate var persistenceCapture: WorkspaceActivePanePersistenceCapture {
        switch self {
        case .insert(let arrangementID, _, _): .insertion(arrangementID: arrangementID)
        case .replace(let arrangementID, _, _): .valueChange(arrangementID: arrangementID)
        case .remove(let arrangementID, _): .removal(arrangementID: arrangementID)
        }
    }
}

extension WorkspaceActiveDrawerChildSelectionMutation {
    fileprivate var persistenceCapture: WorkspaceActiveDrawerChildPersistenceCapture {
        switch self {
        case .insert(let key, _, _): .insertion(key)
        case .replace(let key, _, _): .valueChange(key)
        }
    }
}
