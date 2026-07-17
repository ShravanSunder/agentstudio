import Foundation

enum WorkspaceCrossTabPaneMovePersistenceFailure: Error, Equatable, Sendable {
    case application(WorkspaceCrossTabPaneMoveApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case changedActivePaneMissing(UUID)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case planning(WorkspaceCrossTabPaneMoveRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabCursorCapture(WorkspaceTabCursorPersistenceCaptureError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
}

enum WorkspaceCrossTabPaneMovePersistenceResult: Equatable, Sendable {
    case moved(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceCrossTabPaneMovePersistenceFailure)
}

private struct WorkspaceCrossTabPaneMovePersistenceCaptures {
    let activeArrangements: [WorkspaceActiveArrangementPersistenceCapture]
    let activePanes: [WorkspaceActivePanePersistenceCapture]
    let activeTab: WorkspaceTabCursorPersistenceCapture?
}

@MainActor
final class WorkspaceCrossTabPaneMovePersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let transitionApplier: WorkspaceCrossTabPaneMoveTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        transitionApplier = .init(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
    }

    func move(
        _ request: CrossTabPaneMoveRequest
    ) -> WorkspaceCrossTabPaneMovePersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        let decision = WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
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
        _ request: CrossTabPaneMoveRequest
    ) -> WorkspaceCrossTabPaneMovePlanningContext {
        let sourceTab = workspaceTabGraphAtom.tabState(request.sourceTabId)
        let destinationTab = workspaceTabGraphAtom.tabState(request.destTabId)
        return .init(
            pane: workspacePaneGraphAtom.paneState(request.paneId)
                .map(WorkspaceCrossTabPaneWitness.present) ?? .missing,
            ownership: workspaceTabGraphAtom.tabID(containingPane: request.paneId)
                .map(WorkspaceCrossTabPaneOwnershipWitness.owned) ?? .absent,
            sourceTab: sourceTab.map(WorkspaceCrossTabTabWitness.present) ?? .missing,
            destinationTab: destinationTab.map(WorkspaceCrossTabTabWitness.present) ?? .missing,
            sourceActiveArrangement: activeArrangementWitness(request.sourceTabId),
            destinationActiveArrangement: activeArrangementWitness(request.destTabId),
            sourcePaneCursors: sourceTab.map(activePaneCursorWitnesses) ?? [],
            destinationPaneCursors: destinationTab.map(activePaneCursorWitnesses) ?? [],
            activeTab: workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected)
                ?? .noSelection,
            sourceZoom: zoomWitness(request.sourceTabId),
            destinationZoom: zoomWitness(request.destTabId)
        )
    }

    private func activeArrangementWitness(_ tabID: UUID) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneCursorWitnesses(
        _ tab: TabGraphState
    ) -> [WorkspaceCrossTabPaneCursorWitness] {
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
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> WorkspaceCrossTabPaneMovePersistenceResult {
        let preparedApplication: WorkspacePreparedCrossTabPaneMoveApplication
        switch transitionApplier.preflight(transition) {
        case .ready(let prepared): preparedApplication = prepared
        case .rejected(let rejection): return .rejected(.application(rejection))
        }
        let captures: WorkspaceCrossTabPaneMovePersistenceCaptures
        switch persistenceCaptures(transition) {
        case .success(let value): captures = value
        case .failure(let failure): return .rejected(failure)
        }
        do {
            let revision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    .init(
                        operations: [
                            .valueChange(transition.previousSourceTab.tabId),
                            .valueChange(transition.previousDestinationTab.tabId),
                        ]
                    ),
                    for: preparation
                )
                if !captures.activeArrangements.isEmpty || !captures.activePanes.isEmpty {
                    try adapters.workspaceArrangementCursor.capturePersistencePreimages(
                        .init(
                            activeArrangements: captures.activeArrangements,
                            activePanes: captures.activePanes,
                            activeDrawerChildren: []
                        ),
                        for: preparation
                    )
                }
                if let activeTab = captures.activeTab {
                    try adapters.workspaceTabCursor.capturePersistencePreimage(
                        activeTab,
                        for: preparation
                    )
                }
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .moved(revision: revision)
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspaceTabCursorPersistenceCaptureError {
            return .rejected(.tabCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("cross-tab pane move persistence gateway emitted an unmodeled error")
        }
    }

    private func persistenceCaptures(
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> Result<WorkspaceCrossTabPaneMovePersistenceCaptures, WorkspaceCrossTabPaneMovePersistenceFailure> {
        var activeArrangements: [WorkspaceActiveArrangementPersistenceCapture] = []
        if case .replace(let tabID, _, _) = transition.sourceActiveArrangement {
            activeArrangements = [.valueChange(tabID: tabID)]
        }
        var activePanes: [WorkspaceActivePanePersistenceCapture] = []
        for mutation in transition.sourceActivePanes {
            switch activePaneCapture(mutation) {
            case .success(let capture):
                if let capture { activePanes.append(capture) }
            case .failure(let failure): return .failure(failure)
            }
        }
        for mutation in transition.destinationActivePanes {
            switch activePaneCapture(mutation) {
            case .success(let capture):
                if let capture { activePanes.append(capture) }
            case .failure(let failure): return .failure(failure)
            }
        }
        let activeTab: WorkspaceTabCursorPersistenceCapture?
        switch transition.activeTab {
        case .witness:
            activeTab = nil
        case .replace(let previous, _):
            switch previous {
            case .noSelection: activeTab = .insertion
            case .selected: activeTab = .valueChange
            }
        }
        return .success(
            .init(
                activeArrangements: activeArrangements,
                activePanes: activePanes,
                activeTab: activeTab
            )
        )
    }

    private func activePaneCapture(
        _ mutation: WorkspaceCrossTabActivePaneMutation
    ) -> Result<WorkspaceActivePanePersistenceCapture?, WorkspaceCrossTabPaneMovePersistenceFailure> {
        switch mutation {
        case .witness:
            return .success(nil)
        case .replace(let arrangementID, let previous, let replacement):
            switch previous {
            case .missing:
                return .failure(.changedActivePaneMissing(arrangementID))
            case .present(.noSelection):
                switch replacement {
                case .noSelection: return .success(nil)
                case .selected: return .success(.insertion(arrangementID: arrangementID))
                }
            case .present(.selected):
                switch replacement {
                case .noSelection: return .success(.removal(arrangementID: arrangementID))
                case .selected: return .success(.valueChange(arrangementID: arrangementID))
                }
            }
        }
    }
}
