import Foundation

struct WorkspaceCommittedPaneCreation: Equatable, Sendable {
    let pane: Pane
    let tabID: UUID
    let revision: WorkspacePersistenceRevision
}

enum WorkspacePaneCreationGatewayRejection: Equatable, Sendable {
    case context(WorkspacePaneCreationContextCaptureRejection)
    case transition(WorkspacePaneCreationTransitionRejection)
    case persistence(WorkspacePersistenceMutationFailure)
}

enum WorkspacePaneCreationGatewayResult: Equatable, Sendable {
    case created(WorkspaceCommittedPaneCreation)
    case rejected(WorkspacePaneCreationGatewayRejection)
}

/// The installed semantic entry point for creating one pane and its initial tab.
///
/// Context capture and domain decisions remain persistence-free. Only an
/// accepted transition crosses into the aggregate persistence transaction.
@MainActor
final class WorkspacePaneCreationGateway {
    private let contextBuilder: WorkspacePaneCreationContextBuilder
    private let persistenceMutationCoordinator: WorkspacePersistenceMutationCoordinator

    init(
        contextBuilder: WorkspacePaneCreationContextBuilder,
        persistenceMutationCoordinator: WorkspacePersistenceMutationCoordinator
    ) {
        self.contextBuilder = contextBuilder
        self.persistenceMutationCoordinator = persistenceMutationCoordinator
    }

    func create(_ request: WorkspacePaneCreationRequest) -> WorkspacePaneCreationGatewayResult {
        let context: WorkspacePaneCreationContext
        switch contextBuilder.capture(identities: request.identities) {
        case .captured(let capturedContext):
            context = capturedContext
        case .rejected(let rejection):
            return .rejected(.context(rejection))
        }

        let transition: WorkspacePaneCreationTransition
        switch WorkspacePaneCreationTransitionDecider.decide(
            request: request,
            context: context
        ) {
        case .changed(let acceptedTransition):
            transition = acceptedTransition
        case .rejected(let rejection):
            return .rejected(.transition(rejection))
        }

        switch persistenceMutationCoordinator.commitPaneCreation(transition) {
        case .committed(let revision):
            return .created(
                WorkspaceCommittedPaneCreation(
                    pane: transition.presentationPane,
                    tabID: transition.tab.id,
                    revision: revision
                )
            )
        case .rejected(let rejection):
            return .rejected(.persistence(rejection))
        }
    }
}
