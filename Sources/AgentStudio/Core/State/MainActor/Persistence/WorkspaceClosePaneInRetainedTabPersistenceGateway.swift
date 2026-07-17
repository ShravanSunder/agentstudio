import Foundation

enum WorkspaceClosePaneInRetainedTabPersistenceFailure: Error, Equatable, Sendable {
    case application(WorkspaceClosePaneInRetainedTabApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case changedActivePaneMissing(UUID)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case planning(WorkspaceClosePaneInRetainedTabRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
}

enum WorkspaceClosePaneInRetainedTabPersistenceResult: Equatable, Sendable {
    case closed(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceClosePaneInRetainedTabPersistenceFailure)
}

private struct WorkspaceClosePaneInRetainedTabPersistenceCaptures {
    let activeArrangements: [WorkspaceActiveArrangementPersistenceCapture]
    let activePanes: [WorkspaceActivePanePersistenceCapture]

    var isEmpty: Bool {
        activeArrangements.isEmpty && activePanes.isEmpty
    }
}

@MainActor
final class WorkspaceClosePaneInRetainedTabPersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let transitionApplier: WorkspaceClosePaneInRetainedTabTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        transitionApplier = .init(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceDrawerCursorAtom: workspaceDrawerCursorAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
    }

    func close(
        _ request: WorkspaceClosePaneInRetainedTabRequest
    ) -> WorkspaceClosePaneInRetainedTabPersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        switch WorkspaceClosePaneInRetainedTabTransitionPlanner.plan(
            request,
            context: planningContext(request)
        ) {
        case .changed(let transition):
            return commit(transition)
        case .rejected(let rejection):
            return .rejected(.planning(rejection))
        }
    }

    private func planningContext(
        _ request: WorkspaceClosePaneInRetainedTabRequest
    ) -> WorkspaceClosePaneInRetainedTabPlanningContext {
        let tab = workspaceTabGraphAtom.tabState(request.tabID)
        return .init(
            pane: workspacePaneGraphAtom.paneState(request.paneID)
                .map(WorkspaceClosePaneWitness.present) ?? .missing,
            ownership: workspaceTabGraphAtom.tabID(containingPane: request.paneID)
                .map(WorkspaceClosePaneOwnershipWitness.owned) ?? .absent,
            tab: tab.map(WorkspaceClosePaneTabWitness.present) ?? .missing,
            activeArrangement: workspaceArrangementCursorAtom.activeArrangementId(
                forTab: request.tabID
            ).map(WorkspaceActiveArrangementSelection.selected) ?? .missing,
            paneCursors: tab.map(activePaneCursorWitnesses) ?? [],
            drawerCursor: .init(expandedDrawerID: workspaceDrawerCursorAtom.expandedDrawerId),
            zoom: workspacePanePresentationAtom.zoomedPaneId(forTab: request.tabID)
                .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
        )
    }

    private func activePaneCursorWitnesses(
        _ tab: TabGraphState
    ) -> [WorkspaceClosePaneCursorWitness] {
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

    private func commit(
        _ transition: WorkspaceClosePaneInRetainedTabTransition
    ) -> WorkspaceClosePaneInRetainedTabPersistenceResult {
        let preparedApplication: WorkspacePreparedClosePaneInRetainedTabApplication
        switch transitionApplier.preflight(transition) {
        case .ready(let prepared):
            preparedApplication = prepared
        case .rejected(let rejection):
            return .rejected(.application(rejection))
        }

        let captures: WorkspaceClosePaneInRetainedTabPersistenceCaptures
        switch persistenceCaptures(transition) {
        case .success(let value):
            captures = value
        case .failure(let failure):
            return .rejected(failure)
        }

        do {
            let revision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspacePaneGraph.capturePersistencePreimages(
                    .init(operations: [.removal(transition.previousPane.id)]),
                    for: preparation
                )
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    .init(operations: [.valueChange(transition.previousTab.tabId)]),
                    for: preparation
                )
                if !captures.isEmpty {
                    try adapters.workspaceArrangementCursor.capturePersistencePreimages(
                        .init(
                            activeArrangements: captures.activeArrangements,
                            activePanes: captures.activePanes,
                            activeDrawerChildren: []
                        ),
                        for: preparation
                    )
                }
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .closed(revision: revision)
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("retained-tab pane close gateway emitted an unmodeled error")
        }
    }

    private func persistenceCaptures(
        _ transition: WorkspaceClosePaneInRetainedTabTransition
    ) -> Result<
        WorkspaceClosePaneInRetainedTabPersistenceCaptures,
        WorkspaceClosePaneInRetainedTabPersistenceFailure
    > {
        let activeArrangements: [WorkspaceActiveArrangementPersistenceCapture]
        switch transition.activeArrangement {
        case .witness:
            activeArrangements = []
        case .replace(let tabID, _, _):
            activeArrangements = [.valueChange(tabID: tabID)]
        }

        var activePanes: [WorkspaceActivePanePersistenceCapture] = []
        for mutation in transition.activePanes {
            switch activePaneCapture(mutation) {
            case .success(let capture):
                if let capture { activePanes.append(capture) }
            case .failure(let failure):
                return .failure(failure)
            }
        }
        return .success(
            .init(activeArrangements: activeArrangements, activePanes: activePanes)
        )
    }

    private func activePaneCapture(
        _ mutation: WorkspaceClosePaneActivePaneMutation
    ) -> Result<WorkspaceActivePanePersistenceCapture?, WorkspaceClosePaneInRetainedTabPersistenceFailure> {
        switch mutation {
        case .witness:
            return .success(nil)
        case .replace(let arrangementID, let previous, let replacement):
            switch previous {
            case .missing:
                return .failure(.changedActivePaneMissing(arrangementID))
            case .present(.noSelection):
                switch replacement {
                case .noSelection:
                    return .success(nil)
                case .selected:
                    return .success(.insertion(arrangementID: arrangementID))
                }
            case .present(.selected):
                switch replacement {
                case .noSelection:
                    return .success(.removal(arrangementID: arrangementID))
                case .selected:
                    return .success(.valueChange(arrangementID: arrangementID))
                }
            }
        }
    }
}
