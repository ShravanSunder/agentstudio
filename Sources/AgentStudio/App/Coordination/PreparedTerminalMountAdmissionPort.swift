import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
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
/// Implements the propose/claim/activate handshake declared by
/// `TerminalActivationAdmissionPort`, upholding guarantees G1 and G3-G8 from
/// the program design's "MainActor admission" section. `claimPreparedTerminal`
/// contains no suspension point: the revision comparison, the trusted-frame
/// check, and the `ViewRegistry` `pending -> mounting` transition either all
/// happen or none do.
///
/// `recordCurrentVisibleQueuedTerminals` here is a minimal always-incrementing
/// implementation. Equality suppression and the App-side visibility wiring
/// that actually calls it are a later slice's responsibility; nothing in this
/// generation of the scheduler calls it, so every proposal it makes carries
/// the zero-ordinal baseline this port also starts from.
@MainActor
final class PreparedTerminalMountAdmissionPort: TerminalActivationAdmissionPort {
    private enum TrustedFrameState {
        case awaitingInstallation
        case installed([PaneId: NSRect])
    }

    /// A pane's claim lifecycle as tracked by this port. Independent of
    /// `ViewRegistry` custody, which distinguishes only pending/mounting/
    /// completed/deferred — not which specific claim or attempt is live.
    private enum PaneClaimTracking {
        /// `claimID` has been minted and not yet consumed by
        /// `activateClaimedTerminal`.
        case claimed(claimID: UUID, admission: TerminalActivationAdmission, frame: NSRect?)
        /// The prior attempt was consumed and returned a retryable failure.
        /// Custody remains `mounting`; only the next-numbered attempt may claim.
        case awaitingRetryProposal(lastAttempt: Int, frame: NSRect?)
    }

    private let generation: WorkspaceContentMountGeneration
    private let viewRegistry: ViewRegistry
    private let mountHandler: any PreparedTerminalMountHandling
    private let descriptorsByPaneID: [PaneId: TerminalActivationDescriptor]
    private var trustedFrameState: TrustedFrameState
    private var currentVisibleQueuedSnapshot: TerminalVisibleQueuedSnapshot
    private var claimTrackingByPaneID: [PaneId: PaneClaimTracking] = [:]
    private var issuedClaimIDs: Set<UUID> = []

    init(
        generation: WorkspaceContentMountGeneration,
        initialFramesByPaneID: [PaneId: NSRect],
        viewRegistry: ViewRegistry,
        mountHandler: any PreparedTerminalMountHandling,
        descriptorsByPaneID: [PaneId: TerminalActivationDescriptor]
    ) {
        self.generation = generation
        self.viewRegistry = viewRegistry
        self.mountHandler = mountHandler
        self.descriptorsByPaneID = descriptorsByPaneID
        trustedFrameState = .installed(initialFramesByPaneID)
        currentVisibleQueuedSnapshot = Self.initialSnapshot(generation: generation)
    }

    init(
        generation: WorkspaceContentMountGeneration,
        viewRegistry: ViewRegistry,
        mountHandler: any PreparedTerminalMountHandling,
        descriptorsByPaneID: [PaneId: TerminalActivationDescriptor]
    ) {
        self.generation = generation
        self.viewRegistry = viewRegistry
        self.mountHandler = mountHandler
        self.descriptorsByPaneID = descriptorsByPaneID
        trustedFrameState = .awaitingInstallation
        currentVisibleQueuedSnapshot = Self.initialSnapshot(generation: generation)
    }

    func installTrustedInitialFrames(_ initialFramesByPaneID: [PaneId: NSRect]) -> Bool {
        guard case .awaitingInstallation = trustedFrameState else { return false }
        trustedFrameState = .installed(initialFramesByPaneID)
        return true
    }

    // MARK: - TerminalActivationAdmissionPort

    @discardableResult
    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision {
        let nextRevision = TerminalVisibilityRevision(
            generation: generation,
            ordinal: currentVisibleQueuedSnapshot.revision.ordinal + 1
        )
        currentVisibleQueuedSnapshot = TerminalVisibleQueuedSnapshot(revision: nextRevision, terminals: terminals)
        return nextRevision
    }

    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        guard proposal.generation == generation else {
            return .rejected(.staleGeneration)
        }
        guard let descriptor = descriptorsByPaneID[proposal.paneID] else {
            return .rejected(.paneNotInCohort)
        }
        guard proposal.appliedVisibilityRevision == currentVisibleQueuedSnapshot.revision else {
            return .visibilityChanged(currentVisibleQueuedSnapshot)
        }

        if let tracking = claimTrackingByPaneID[proposal.paneID] {
            switch tracking {
            case .claimed:
                // A claim is already outstanding and unconsumed for this pane;
                // this proposal cannot be a legitimate retry of it.
                return .rejected(.custodyUnavailableForClaim)
            case .awaitingRetryProposal(let lastAttempt, let frame):
                guard proposal.attempt == lastAttempt + 1 else {
                    return .rejected(.retryClaimMismatch)
                }
                return mintClaim(descriptor: descriptor, attempt: proposal.attempt, frame: frame, proposal: proposal)
            }
        }

        guard proposal.attempt == 1 else {
            return .rejected(.retryClaimMismatch)
        }
        guard
            viewRegistry.preparedContentMountState(for: proposal.paneID, generation: generation)
                == .pending(owner: .terminal)
        else {
            return .rejected(.custodyUnavailableForClaim)
        }
        guard let frame = installedFrame(for: proposal.paneID) else {
            return .rejected(.trustedFrameUnavailable)
        }
        guard
            viewRegistry.claimPreparedContentMount(
                paneID: proposal.paneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        else {
            return .rejected(.custodyUnavailableForClaim)
        }
        return mintClaim(descriptor: descriptor, attempt: proposal.attempt, frame: frame, proposal: proposal)
    }

    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        guard issuedClaimIDs.contains(claim.claimID) else {
            return .rejected(.claimNotIssued)
        }
        let paneID = claim.admission.descriptor.paneID
        guard
            case .claimed(let liveClaimID, let admission, let frame) = claimTrackingByPaneID[paneID],
            liveClaimID == claim.claimID
        else {
            return .rejected(.claimAlreadyConsumed)
        }

        let result = mountHandler.mountPreparedTerminalContent(admission: admission, initialFrame: frame)
        settle(result: result, admission: admission, frame: frame, paneID: paneID)
        return .attempted(result)
    }

    // MARK: - Private

    private func mintClaim(
        descriptor: TerminalActivationDescriptor,
        attempt: Int,
        frame: NSRect?,
        proposal: TerminalAdmissionProposal
    ) -> TerminalAdmissionClaimOutcome {
        let admission = TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: attempt)
        let claimID = UUIDv7.generate()
        issuedClaimIDs.insert(claimID)
        claimTrackingByPaneID[proposal.paneID] = .claimed(claimID: claimID, admission: admission, frame: frame)
        return .claimed(
            ClaimedTerminalAdmission(
                claimID: claimID,
                admission: admission,
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision
            )
        )
    }

    private func settle(
        result: TerminalActivationAttemptResult,
        admission: TerminalActivationAdmission,
        frame: NSRect?,
        paneID: PaneId
    ) {
        switch result {
        case .ready:
            claimTrackingByPaneID.removeValue(forKey: paneID)
            viewRegistry.settlePreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation,
                disposition: .mounted
            )
        case .failed(_, .doNotRetry):
            claimTrackingByPaneID.removeValue(forKey: paneID)
            viewRegistry.settlePreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation,
                disposition: .failed
            )
        case .failed(_, .retry):
            if admission.attempt >= 2 {
                claimTrackingByPaneID.removeValue(forKey: paneID)
                viewRegistry.settlePreparedContentMount(
                    paneID: paneID,
                    owner: .terminal,
                    generation: generation,
                    disposition: .failed
                )
            } else {
                claimTrackingByPaneID[paneID] = .awaitingRetryProposal(lastAttempt: admission.attempt, frame: frame)
            }
        }
    }

    private func installedFrame(for paneID: PaneId) -> NSRect? {
        switch trustedFrameState {
        case .awaitingInstallation:
            return nil
        case .installed(let frames):
            return frames[paneID]
        }
    }

    private static func initialSnapshot(generation: WorkspaceContentMountGeneration) -> TerminalVisibleQueuedSnapshot {
        TerminalVisibleQueuedSnapshot(
            revision: TerminalVisibilityRevision(generation: generation, ordinal: 0),
            terminals: TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [],
                visibleMainSiblingPaneIDs: [],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )
    }
}
