import CoreGraphics
import Foundation

enum WorkspacePersistenceMutationFailure: Equatable, Sendable {
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
    case paneMissing(UUID)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case windowMemory(WorkspaceSnapshotPreparationRejection)
}

enum WorkspacePersistenceMutationResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePersistenceMutationFailure)
}

/// Persistence-aware mutation boundary for installed canonical workspace state.
///
/// This coordinator owns no canonical values. It reserves fixed-revision
/// preimages in the long-lived adapters and commits the corresponding atom
/// mutation through the shared revision owner.
@MainActor
final class WorkspacePersistenceMutationCoordinator {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspacePaneTransitionApplier: WorkspacePaneTransitionApplier
    private let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        workspacePaneTransitionApplier = WorkspacePaneTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom
        )
        self.workspaceWindowMemoryAtom = workspaceWindowMemoryAtom
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
