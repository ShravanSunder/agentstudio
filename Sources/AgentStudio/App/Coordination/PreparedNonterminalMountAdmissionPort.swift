import Foundation

/// Generation-bound admission boundary between the nonterminal startup owner
/// and AppKit/WebKit content construction.
///
/// A claim is acquired before any controller, runtime, or host is constructed.
/// Repeated, stale, or wrong-lane admissions therefore cannot replace an
/// already-mounted host.
@MainActor
final class PreparedNonterminalMountAdmissionPort:
    NonterminalContentMountAdmissionPort
{
    private let generation: WorkspaceContentMountGeneration
    private let coordinator: WorkspaceSurfaceCoordinator

    init(
        generation: WorkspaceContentMountGeneration,
        coordinator: WorkspaceSurfaceCoordinator
    ) {
        self.generation = generation
        self.coordinator = coordinator
    }

    func mount(_ descriptor: NonterminalContentMountDescriptor) -> NonterminalContentMountAdmissionResult {
        let paneID = descriptor.paneID
        guard
            coordinator.viewRegistry.claimPreparedContentMount(
                paneID: paneID,
                owner: .nonterminal,
                generation: generation
            ) == .accepted
        else {
            return .failed(.mountRejected)
        }

        let result: NonterminalContentMountAdmissionResult
        let disposition: PreparedContentMountDisposition
        if coordinator.mountPreparedNonterminalContent(pane: descriptor.pane) != nil {
            result = .mounted
            disposition = .mounted
        } else {
            result = .failed(failure(for: descriptor.content))
            disposition = .failed
        }

        coordinator.viewRegistry.settlePreparedContentMount(
            paneID: paneID,
            owner: .nonterminal,
            generation: generation,
            disposition: disposition
        )
        return result
    }

    private func failure(
        for content: NonterminalContentMountContent
    ) -> NonterminalContentMountFailure {
        guard case .unsupported(let pane) = content,
            case .unsupported(let unsupported) = pane.content
        else {
            return .mountRejected
        }
        return .unsupportedContent(type: unsupported.type, version: unsupported.version)
    }
}
