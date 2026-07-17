import AppKit
import Foundation

@MainActor
protocol PreparedTerminalMountHandling: AnyObject {
    func mountPreparedTerminalContent(
        admission: TerminalActivationAdmission,
        initialFrame: NSRect?
    ) -> TerminalActivationAttemptResult
}

/// Generation-bound admission boundary between the off-main terminal scheduler
/// and MainActor surface creation.
///
/// One registry claim spans every scheduler attempt for a pane. A retry keeps
/// that claim in `.mounting`; only a ready result or terminal failure settles it.
@MainActor
final class PreparedTerminalMountAdmissionPort: TerminalActivationAdmissionPort {
    private enum TrustedFrameState {
        case awaitingInstallation
        case installed([PaneId: NSRect])
        case activationStarted([PaneId: NSRect])
    }

    private let generation: WorkspaceContentMountGeneration
    private let viewRegistry: ViewRegistry
    private let mountHandler: any PreparedTerminalMountHandling
    private var trustedFrameState: TrustedFrameState

    init(
        generation: WorkspaceContentMountGeneration,
        initialFramesByPaneID: [PaneId: NSRect],
        viewRegistry: ViewRegistry,
        mountHandler: any PreparedTerminalMountHandling
    ) {
        self.generation = generation
        self.viewRegistry = viewRegistry
        self.mountHandler = mountHandler
        trustedFrameState = .installed(initialFramesByPaneID)
    }

    init(
        generation: WorkspaceContentMountGeneration,
        viewRegistry: ViewRegistry,
        mountHandler: any PreparedTerminalMountHandling
    ) {
        self.generation = generation
        self.viewRegistry = viewRegistry
        self.mountHandler = mountHandler
        trustedFrameState = .awaitingInstallation
    }

    func installTrustedInitialFrames(_ initialFramesByPaneID: [PaneId: NSRect]) -> Bool {
        guard case .awaitingInstallation = trustedFrameState else { return false }
        trustedFrameState = .installed(initialFramesByPaneID)
        return true
    }

    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult {
        guard admission.generation == generation else {
            return rejected(code: "stale_generation")
        }
        guard acquireOrVerifyClaim(for: admission) else {
            return rejected(code: admission.attempt == 1 ? "claim_rejected" : "retry_claim_mismatch")
        }
        let initialFramesByPaneID: [PaneId: NSRect]
        switch trustedFrameState {
        case .awaitingInstallation:
            let result = TerminalActivationAttemptResult.failed(
                failure: .surfaceCreationFailed(code: "trusted_initial_frames_not_installed"),
                retry: .doNotRetry
            )
            settleIfTerminal(result, admission: admission)
            return result
        case .installed(let frames):
            trustedFrameState = .activationStarted(frames)
            initialFramesByPaneID = frames
        case .activationStarted(let frames):
            initialFramesByPaneID = frames
        }

        let result = mountHandler.mountPreparedTerminalContent(
            admission: admission,
            initialFrame: initialFramesByPaneID[admission.descriptor.paneID]
        )
        settleIfTerminal(result, admission: admission)
        return result
    }

    private func acquireOrVerifyClaim(for admission: TerminalActivationAdmission) -> Bool {
        let paneID = admission.descriptor.paneID
        switch admission.attempt {
        case 1:
            return viewRegistry.claimPreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        case 2:
            return viewRegistry.preparedContentMountState(for: paneID, generation: generation)
                == .mounting(owner: .terminal)
        default:
            return false
        }
    }

    private func settleIfTerminal(
        _ result: TerminalActivationAttemptResult,
        admission: TerminalActivationAdmission
    ) {
        let disposition: PreparedContentMountDisposition
        switch result {
        case .ready:
            disposition = .mounted
        case .failed(_, .doNotRetry):
            disposition = .failed
        case .failed(_, .retry):
            guard admission.attempt >= 2 else { return }
            disposition = .failed
        }
        viewRegistry.settlePreparedContentMount(
            paneID: admission.descriptor.paneID,
            owner: .terminal,
            generation: generation,
            disposition: disposition
        )
    }

    private func rejected(code: String) -> TerminalActivationAttemptResult {
        .failed(
            failure: .attachmentRejected(code: code),
            retry: .doNotRetry
        )
    }
}
