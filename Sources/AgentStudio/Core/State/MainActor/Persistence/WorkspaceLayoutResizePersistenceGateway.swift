import Foundation

enum WorkspaceLayoutResizePersistenceFailure: Equatable, Sendable {
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case planning(WorkspaceLayoutResizeRejection)
    case application(WorkspaceLayoutResizeApplyRejection)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
}

enum WorkspaceLayoutResizePersistenceResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceLayoutResizePersistenceFailure)
}

@MainActor
final class WorkspaceLayoutResizePersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let transitionApplier: WorkspaceLayoutResizeTransitionApplier

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

    func apply(
        _ checkpoint: WorkspaceLayoutResizeCheckpoint
    ) -> WorkspaceLayoutResizePersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        let decision = WorkspaceLayoutResizeTransitionPlanner.plan(
            checkpoint,
            context: planningContext(tabID: checkpoint.tabID)
        )
        switch decision {
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection):
            return .rejected(.planning(rejection))
        case .changed(let transition):
            return commit(transition)
        }
    }

    private func planningContext(tabID: UUID) -> WorkspaceLayoutResizePlanningContext {
        guard let tab = workspaceTabGraphAtom.tabState(tabID) else { return .missingTab }
        guard let activeArrangementID = workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID) else {
            return .missingActiveArrangement(tab: tab)
        }
        return .selectedActiveArrangement(tab: tab, arrangementID: activeArrangementID)
    }

    private func commit(
        _ transition: WorkspaceLayoutResizeTransition
    ) -> WorkspaceLayoutResizePersistenceResult {
        let preparedApplication: WorkspacePreparedLayoutResizeApplication
        switch transitionApplier.preflight(transition) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.application(rejection))
        }

        do {
            let revision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    .init(operations: [.valueChange(transition.tabID)]),
                    for: preparation
                )
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: revision)
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("layout resize persistence gateway emitted an unmodeled error")
        }
    }
}
