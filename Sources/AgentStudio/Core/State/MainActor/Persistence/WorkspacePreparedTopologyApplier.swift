import Foundation

struct WorkspacePreparedTopologyAcceptance: Equatable, Sendable {
    let workspaceID: UUID
    let revision: WorkspacePersistenceRevision
}

enum WorkspacePreparedTopologyApplyFailure: Equatable, Sendable {
    case lifecycle(WorkspacePersistenceLifecycleRejection)
    case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    case revisionOwnerReentrantTransaction
}

enum WorkspacePreparedTopologyApplyResult: Equatable, Sendable {
    case accepted(WorkspacePreparedTopologyAcceptance)
    case failed(WorkspacePreparedTopologyApplyFailure)
}

/// MainActor install owner for one off-main-prepared topology replacement.
///
/// This owner is independent from composition restore and cannot authorize
/// composition bootstrap mutations.
@MainActor
final class WorkspacePreparedTopologyApplier {
    private enum TransactionAbort: Error {
        case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    }

    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle

    init(adapters: WorkspacePersistenceAdapterBundle) {
        revisionOwner = adapters.revisionOwner
        self.adapters = adapters
    }

    func apply(_ prepared: PreparedWorkspaceTopology) -> WorkspacePreparedTopologyApplyResult {
        do {
            let accessResult = try adapters.withTopologyPreinstallAccess { token in
                try revisionOwner.performSynchronousTransaction { preparation in
                    switch adapters.repositoryTopology.registerInitialReplacement(
                        token: token,
                        prepared.replacement,
                        for: preparation
                    ) {
                    case .registered:
                        return preparation.commit {
                            WorkspacePreparedTopologyAcceptance(
                                workspaceID: prepared.workspaceID,
                                revision: preparation.transaction.proposedRevision
                            )
                        }
                    case .rejected(let rejection):
                        throw TransactionAbort.ownerRegistration(rejection)
                    }
                }
            }
            switch accessResult {
            case .authorized(let acceptance):
                return .accepted(acceptance)
            case .rejected(let rejection):
                return .failed(.lifecycle(rejection))
            }
        } catch let abort as TransactionAbort {
            switch abort {
            case .ownerRegistration(let rejection):
                return .failed(.ownerRegistration(rejection))
            }
        } catch WorkspacePersistenceRevisionOwnerError.reentrantTransaction {
            return .failed(.revisionOwnerReentrantTransaction)
        } catch {
            preconditionFailure("prepared topology transaction emitted an unmodeled error")
        }
    }
}
