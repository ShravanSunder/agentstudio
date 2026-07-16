import CoreGraphics
import Foundation

enum WorkspacePersistenceMutationFailure: Equatable, Sendable {
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

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
    }

    func setSidebarWidth(_ sidebarWidth: CGFloat) -> WorkspacePersistenceMutationResult {
        performWindowMemoryMutation { preparation in
            try adapters.workspaceWindowMemory.prepareSetSidebarWidth(
                sidebarWidth,
                for: preparation
            )
        }
    }

    func setWindowFrame(_ windowFrame: CGRect?) -> WorkspacePersistenceMutationResult {
        performWindowMemoryMutation { preparation in
            try adapters.workspaceWindowMemory.prepareSetWindowFrame(
                windowFrame,
                for: preparation
            )
        }
    }

    private func performWindowMemoryMutation(
        _ prepare: (WorkspacePersistenceTransactionPreparation) throws
            -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision>
    ) -> WorkspacePersistenceMutationResult {
        let previousRevision = revisionOwner.committedRevision
        do {
            let committedRevision = try revisionOwner.performSynchronousTransactionDecision(prepare)
            if committedRevision == previousRevision {
                return .unchanged(revision: committedRevision)
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
}
