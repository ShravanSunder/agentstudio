import Foundation

struct WorkspacePaneReactivationMountIntent: Equatable, Sendable {
    let paneID: UUID
}

enum WorkspacePaneBackgroundLifecycleResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePaneResidencyPersistenceFailure)
}

enum WorkspacePaneReactivationLifecycleResult: Equatable, Sendable {
    case changed(
        revision: WorkspacePersistenceRevision,
        mountIntent: WorkspacePaneReactivationMountIntent
    )
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePaneResidencyPersistenceFailure)
}

/// Owns runtime-only retained drawer payloads for pane residency transitions.
@MainActor
final class WorkspacePaneResidencyLifecycleOwner {
    private let persistenceMutationCoordinator: WorkspacePersistenceMutationCoordinator
    private var retainedDrawerPayloadsByPaneID: [UUID: WorkspaceBackgroundedDrawerPayload] = [:]

    init(
        persistenceMutationCoordinator: WorkspacePersistenceMutationCoordinator
    ) {
        self.persistenceMutationCoordinator = persistenceMutationCoordinator
    }

    func retainedDrawerPayload(
        forPane paneID: UUID
    ) -> WorkspaceRetainedDrawerPayloadWitness {
        retainedDrawerPayloadsByPaneID[paneID]
            .map(WorkspaceRetainedDrawerPayloadWitness.present) ?? .absent
    }

    func backgroundPane(
        _ request: WorkspaceBackgroundPaneRequest
    ) -> WorkspacePaneBackgroundLifecycleResult {
        switch persistenceMutationCoordinator.backgroundPane(
            request,
            retainedDrawerPayload: retainedDrawerPayload(forPane: request.paneID)
        ) {
        case .changed(let revision, let effect):
            applyBackgroundEffect(effect, request: request)
            return .changed(revision: revision)
        case .unchanged(let revision):
            return .unchanged(revision: revision)
        case .rejected(let failure):
            return .rejected(failure)
        }
    }

    func reactivatePane(
        _ request: WorkspaceReactivatePaneRequest
    ) -> WorkspacePaneReactivationLifecycleResult {
        switch persistenceMutationCoordinator.reactivatePane(
            request,
            retainedDrawerPayload: retainedDrawerPayload(forPane: request.paneID)
        ) {
        case .changed(let revision, let effect):
            let mountIntent = applyReactivationEffect(effect, request: request)
            return .changed(revision: revision, mountIntent: mountIntent)
        case .unchanged(let revision):
            return .unchanged(revision: revision)
        case .rejected(let failure):
            return .rejected(failure)
        }
    }

    private func applyBackgroundEffect(
        _ effect: WorkspacePaneResidencyRuntimeEffect,
        request: WorkspaceBackgroundPaneRequest
    ) {
        guard
            case .replaceRetainedDrawerPayload(let paneID, let replacement) = effect,
            paneID == request.paneID
        else {
            preconditionFailure("background persistence returned a mismatched runtime effect")
        }
        switch replacement {
        case .absent:
            retainedDrawerPayloadsByPaneID.removeValue(forKey: paneID)
        case .present(let payload):
            retainedDrawerPayloadsByPaneID[paneID] = payload
        }
    }

    private func applyReactivationEffect(
        _ effect: WorkspacePaneResidencyRuntimeEffect,
        request: WorkspaceReactivatePaneRequest
    ) -> WorkspacePaneReactivationMountIntent {
        guard case .consumeRetainedDrawerPayloadAndMount(let paneID) = effect,
            paneID == request.paneID
        else {
            preconditionFailure("reactivation persistence returned a mismatched runtime effect")
        }
        retainedDrawerPayloadsByPaneID.removeValue(forKey: paneID)
        return WorkspacePaneReactivationMountIntent(paneID: paneID)
    }
}
