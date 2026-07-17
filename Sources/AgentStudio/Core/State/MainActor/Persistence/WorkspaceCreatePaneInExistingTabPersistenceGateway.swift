import Foundation

enum WorkspaceCreatePaneInExistingTabPersistenceFailure: Equatable, Sendable {
    case application(WorkspaceCreatePaneInExistingTabApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case planning(WorkspaceCreatePaneInExistingTabRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
}

enum WorkspaceCreatePaneInExistingTabPersistenceResult: Equatable, Sendable {
    case created(WorkspaceCommittedPaneCreation)
    case rejected(WorkspaceCreatePaneInExistingTabPersistenceFailure)
}

@MainActor
final class WorkspaceCreatePaneInExistingTabPersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let transitionApplier: WorkspaceCreatePaneInExistingTabTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        transitionApplier = .init(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
    }

    func create(
        _ request: WorkspaceCreatePaneInExistingTabRequest
    ) -> WorkspaceCreatePaneInExistingTabPersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        let decision = WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
            request,
            context: planningContext(request)
        )
        switch decision {
        case .rejected(let rejection):
            return .rejected(.planning(rejection))
        case .changed(let transition):
            return commit(transition)
        }
    }

    private func planningContext(
        _ request: WorkspaceCreatePaneInExistingTabRequest
    ) -> WorkspaceCreatePaneInExistingTabPlanningContext {
        let paneID = request.identities.paneID.uuid
        let targetTab = workspaceTabGraphAtom.tabState(request.targetTabID)
        return .init(
            proposedPane: paneIdentityWitness(paneID),
            proposedDrawer: drawerIdentityWitness(request.identities.drawerID),
            targetTab: targetTab.map(WorkspaceCreatePaneTargetTabWitness.present) ?? .missing,
            activeArrangement:
                workspaceArrangementCursorAtom.activeArrangementId(forTab: request.targetTabID)
                .map(WorkspaceActiveArrangementSelection.selected) ?? .missing,
            activePaneCursors: targetTab.map(activePaneCursorWitnesses) ?? [],
            zoom: zoomWitness(request.targetTabID)
        )
    }

    private func paneIdentityWitness(_ paneID: UUID) -> WorkspaceProposedPaneIdentityWitness {
        let paneExists = workspacePaneGraphAtom.paneState(paneID) != nil
        let tabOwner = workspaceTabGraphAtom.tabID(containingPane: paneID)
        if paneExists {
            return tabOwner.map { .paneGraphOccupiedAndTabOwned(tabID: $0) } ?? .paneGraphOccupied
        }
        return tabOwner.map { .tabOwned(tabID: $0) } ?? .vacant
    }

    private func drawerIdentityWitness(_ drawerID: UUID) -> WorkspaceProposedDrawerIdentityWitness {
        workspacePaneGraphAtom.parentPaneID(containingDrawer: drawerID)
            .map(WorkspaceProposedDrawerIdentityWitness.owned) ?? .vacant
    }

    private func activePaneCursorWitnesses(
        _ tab: TabGraphState
    ) -> [WorkspaceCreatePaneArrangementCursorWitness] {
        tab.arrangements.map { arrangement in
            let cursor: WorkspaceActivePaneCursorWitness
            if workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangement.id) {
                cursor = .present(
                    workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangement.id)
                        .map(WorkspacePaneSelection.selected) ?? .noSelection
                )
            } else {
                cursor = .missing
            }
            return .init(arrangementID: arrangement.id, cursor: cursor)
        }
    }

    private func zoomWitness(_ tabID: UUID) -> WorkspaceZoomSelection {
        workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
    }

    private func commit(
        _ transition: WorkspaceCreatePaneInExistingTabTransition
    ) -> WorkspaceCreatePaneInExistingTabPersistenceResult {
        let preparedApplication: WorkspacePreparedExistingTabPaneCreation
        switch transitionApplier.preflight(transition) {
        case .ready(let preparation): preparedApplication = preparation
        case .rejected(let rejection): return .rejected(.application(rejection))
        }
        do {
            let revision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspacePaneGraph.capturePersistencePreimages(
                    .init(operations: [.insertion(transition.paneInsertion.id)]),
                    for: preparation
                )
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    .init(operations: [.valueChange(transition.previousTab.tabId)]),
                    for: preparation
                )
                try adapters.workspaceArrangementCursor.capturePersistencePreimages(
                    .init(
                        activeArrangements: [],
                        activePanes: transition.activePaneMutations.compactMap(\.persistenceCapture),
                        activeDrawerChildren: []
                    ),
                    for: preparation
                )
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .created(
                .init(
                    pane: transition.presentationPane,
                    tabID: transition.previousTab.tabId,
                    revision: revision
                )
            )
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("create-pane-in-existing-tab persistence gateway emitted an unmodeled error")
        }
    }
}

extension WorkspaceCreatePaneActivePaneMutation {
    fileprivate var persistenceCapture: WorkspaceActivePanePersistenceCapture? {
        switch self {
        case .witness: nil
        case .replace(let arrangementID, _, _): .valueChange(arrangementID: arrangementID)
        }
    }
}
