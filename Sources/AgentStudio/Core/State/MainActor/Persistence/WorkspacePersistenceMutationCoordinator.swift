import CoreGraphics
import Foundation

enum WorkspacePersistenceMutationFailure: Equatable, Sendable {
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
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
    private let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspaceWindowMemoryAtom = workspaceWindowMemoryAtom
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
}
