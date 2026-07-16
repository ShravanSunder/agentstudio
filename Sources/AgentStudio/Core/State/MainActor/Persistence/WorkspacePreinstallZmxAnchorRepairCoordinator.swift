import Foundation

enum WorkspacePreinstallZmxAnchorRepairFailure: Equatable, Sendable {
    case lifecycle(WorkspacePersistenceLifecycleRejection)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
}

enum WorkspacePreinstallZmxAnchorRepairResult: Equatable, Sendable {
    case changed(
        revision: WorkspacePersistenceRevision,
        report: WorkspacePaneZmxAnchorRepairReport
    )
    case unchanged(
        revision: WorkspacePersistenceRevision,
        report: WorkspacePaneZmxAnchorRepairReport
    )
    case rejected(WorkspacePreinstallZmxAnchorRepairFailure)
}

/// Composition-bootstrap repair for hydrated zmx session anchors.
///
/// This route exists only before composition participant installation. It
/// classifies stale candidates without mutating atoms, captures every accepted
/// pane preimage, and applies the accepted subset in one canonical revision.
@MainActor
final class WorkspacePreinstallZmxAnchorRepairCoordinator {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspacePaneTransitionApplier: WorkspacePaneTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        workspacePaneTransitionApplier = WorkspacePaneTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom
        )
    }

    func repair(
        _ requests: [WorkspacePaneZmxAnchorRepairRequest]
    ) -> WorkspacePreinstallZmxAnchorRepairResult {
        var currentPaneStateByID: [UUID: PaneGraphState] = [:]
        currentPaneStateByID.reserveCapacity(requests.count)
        for request in requests {
            if let paneState = workspacePaneGraphAtom.paneState(request.paneID) {
                currentPaneStateByID[request.paneID] = paneState
            }
        }

        do {
            let accessResult = try adapters.withCompositionPreinstallAccess { _ in
                switch WorkspacePaneZmxAnchorRepairPlanner.plan(
                    requests,
                    currentPaneStateByID: currentPaneStateByID
                ) {
                case .changed(let transition, let report):
                    let revision = try commit(transition)
                    return WorkspacePreinstallZmxAnchorRepairResult.changed(
                        revision: revision,
                        report: report
                    )
                case .unchanged(let report):
                    return .unchanged(
                        revision: revisionOwner.committedRevision,
                        report: report
                    )
                }
            }
            switch accessResult {
            case .authorized(let result):
                return result
            case .rejected(let rejection):
                return .rejected(.lifecycle(rejection))
            }
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("preinstall zmx-anchor repair emitted an unmodeled error")
        }
    }

    private func commit(
        _ transition: WorkspacePaneGraphTransition
    ) throws -> WorkspacePersistenceRevision {
        try revisionOwner.performSynchronousTransaction { preparation in
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
    }
}
