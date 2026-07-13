import Foundation

enum FilesystemObservationMailboxConfigurationError: Error, Equatable {
    case invalidGatherLimits
}

enum FilesystemObservationOffer: Sendable {
    case authoritative(FSEventObservation)
    case requiresRecovery(
        FSEventObservation,
        evidence: FilesystemRecoveryEvidence
    )

    var observation: FSEventObservation {
        switch self {
        case .authoritative(let observation), .requiresRecovery(let observation, _):
            observation
        }
    }

    var recoverySignal: GatherRecoverySignal {
        switch self {
        case .authoritative:
            .ordinary
        case .requiresRecovery:
            .authoritativeRecoveryRequired
        }
    }

    var explicitRecoveryEvidence: FilesystemObservationExplicitRecoveryEvidence {
        switch self {
        case .authoritative:
            .notRequired
        case .requiresRecovery(_, let evidence):
            .required(evidence)
        }
    }
}

enum FilesystemObservationExplicitRecoveryEvidence: Sendable {
    case notRequired
    case required(FilesystemRecoveryEvidence)
}

enum FilesystemObservationOfferDisposition: Equatable, Sendable {
    case retained
    case retainedWithRecovery(FilesystemRecoveryEvidenceSnapshot)
    case contractedToRecovery(FilesystemRecoveryEvidenceSnapshot)
}

struct FilesystemObservationOfferReceipt: Equatable, Sendable {
    let disposition: FilesystemObservationOfferDisposition
    let wake: AdmissionWakeDirective
}

enum FilesystemObservationOfferResult: Equatable, Sendable {
    case admitted(FilesystemObservationOfferReceipt)
    case undeclaredRegistration
    case invalidFootprint
    case closed
}

enum FilesystemObservationDrainPayload: Sendable {
    case observations(NonEmptyAdmissionBatch<FSEventObservation>)
    case observationsWithRecovery(
        NonEmptyAdmissionBatch<FSEventObservation>,
        FilesystemRecoveryEvidenceSnapshot
    )
    case recovery(FilesystemRecoveryEvidenceSnapshot)
}

struct FilesystemObservationDrainLease: Sendable {
    let token: AdmissionDrainToken
    let registration: FSEventRegistrationToken
    let payload: FilesystemObservationDrainPayload
}

enum FilesystemObservationTakeDrainResult: Sendable {
    case lease(FilesystemObservationDrainLease)
    case cleanupRequired
    case empty
    case alreadyLeased
    case closed
}

enum FilesystemObservationDrainDisposition: Equatable, Sendable {
    case retry
    case transferredAuthoritative
    case transferredRecovery(FilesystemSourceGateRecoveryAcceptance)
}

enum FilesystemObservationLifecycleStateSnapshot: Equatable, Sendable {
    case open
    case sealed
    case invalidated
    case finished
}

struct FilesystemObservationOutstandingCustody: Equatable, Sendable {
    let retainedContributionCount: Int
    let activeLeaseCount: Int
    let retryEvidenceRegistrationCount: Int
    let recoveryEvidenceRegistrationCount: Int
    let cleanupEntryCount: Int
}

enum FilesystemObservationLifecycleTransitionResult: Equatable, Sendable {
    case applied
    case alreadyApplied
    case invalidState(FilesystemObservationLifecycleStateSnapshot)
    case outstandingCustody(FilesystemObservationOutstandingCustody)
}

enum FilesystemObservationDrainAcknowledgement: Equatable, Sendable {
    case retried(wake: AdmissionWakeDirective)
    case transferredAuthoritative(wake: AdmissionWakeDirective)
    case transferredRecovery(
        evidence: FilesystemRecoveryEvidenceAcknowledgementResult,
        wake: AdmissionWakeDirective
    )
    case dispositionMismatch
    case invalidToken
    case closed

    var wake: AdmissionWakeDirective {
        switch self {
        case .retried(let wake), .transferredAuthoritative(let wake):
            wake
        case .transferredRecovery(_, let wake):
            wake
        case .dispositionMismatch, .invalidToken, .closed:
            .noWake
        }
    }
}

struct FilesystemObservationMailboxDiagnostics: Sendable {
    let gather: GatherAdmissionDiagnostics
    let doorbellState: AdmissionDoorbellStateSnapshot
    let lifecycleState: FilesystemObservationLifecycleStateSnapshot
    private let recoveryEvidenceByRegistration: [FSEventRegistrationToken: FilesystemRecoveryEvidenceSnapshotResult]

    init(
        gather: GatherAdmissionDiagnostics,
        doorbellState: AdmissionDoorbellStateSnapshot,
        lifecycleState: FilesystemObservationLifecycleStateSnapshot,
        recoveryEvidenceByRegistration:
            [FSEventRegistrationToken: FilesystemRecoveryEvidenceSnapshotResult]
    ) {
        self.gather = gather
        self.doorbellState = doorbellState
        self.lifecycleState = lifecycleState
        self.recoveryEvidenceByRegistration = recoveryEvidenceByRegistration
    }

    func recoveryEvidence(
        for registration: FSEventRegistrationToken
    ) -> FilesystemRecoveryEvidenceSnapshotResult {
        recoveryEvidenceByRegistration[registration] ?? .unknownRegistration
    }
}

struct FilesystemObservationCallbackProducerPort: Sendable {
    private let offerImplementation: @Sendable (FilesystemObservationOffer) -> FilesystemObservationOfferResult

    init(
        offer: @escaping @Sendable (FilesystemObservationOffer) -> FilesystemObservationOfferResult
    ) {
        offerImplementation = offer
    }

    func offer(_ offer: FilesystemObservationOffer) -> FilesystemObservationOfferResult {
        offerImplementation(offer)
    }
}

struct FilesystemObservationCallbackSignalerPort: Sendable {
    private let applyImplementation: @Sendable (AdmissionWakeDirective) -> Void

    init(apply: @escaping @Sendable (AdmissionWakeDirective) -> Void) {
        applyImplementation = apply
    }

    func apply(_ wake: AdmissionWakeDirective) {
        applyImplementation(wake)
    }
}

struct FilesystemObservationActorConsumerPort: Sendable {
    private let bindImplementation: @Sendable () -> AdmissionConsumerBindResult
    private let takeImplementation: @Sendable (AdmissionConsumerBinding) -> FilesystemObservationTakeDrainResult
    private let acknowledgeImplementation:
        @Sendable (
            AdmissionDrainToken,
            FilesystemObservationDrainDisposition
        ) -> FilesystemObservationDrainAcknowledgement
    private let cleanupImplementation: @Sendable () -> AdmissionCleanupTurnResult

    init(
        bind: @escaping @Sendable () -> AdmissionConsumerBindResult,
        take: @escaping @Sendable (AdmissionConsumerBinding) -> FilesystemObservationTakeDrainResult,
        acknowledge:
            @escaping @Sendable (
                AdmissionDrainToken,
                FilesystemObservationDrainDisposition
            ) -> FilesystemObservationDrainAcknowledgement,
        cleanup: @escaping @Sendable () -> AdmissionCleanupTurnResult
    ) {
        bindImplementation = bind
        takeImplementation = take
        acknowledgeImplementation = acknowledge
        cleanupImplementation = cleanup
    }

    func bindConsumer() -> AdmissionConsumerBindResult {
        bindImplementation()
    }

    func takeDrain(
        binding: AdmissionConsumerBinding
    ) -> FilesystemObservationTakeDrainResult {
        takeImplementation(binding)
    }

    func acknowledge(
        token: AdmissionDrainToken,
        disposition: FilesystemObservationDrainDisposition
    ) -> FilesystemObservationDrainAcknowledgement {
        acknowledgeImplementation(token, disposition)
    }

    func performCleanup() -> AdmissionCleanupTurnResult {
        cleanupImplementation()
    }
}

struct FilesystemObservationActorWaiterPort: Sendable {
    private let waitImplementation: @Sendable () async -> AdmissionDoorbellResult

    init(wait: @escaping @Sendable () async -> AdmissionDoorbellResult) {
        waitImplementation = wait
    }

    func nextSignal() async -> AdmissionDoorbellResult {
        await waitImplementation()
    }
}

struct FilesystemObservationLifecyclePort: Sendable {
    private let sealImplementation: @Sendable () -> FilesystemObservationLifecycleTransitionResult
    private let invalidateImplementation: @Sendable () -> FilesystemObservationLifecycleTransitionResult
    private let finishImplementation: @Sendable () -> FilesystemObservationLifecycleTransitionResult
    private let diagnosticsImplementation: @Sendable () -> FilesystemObservationMailboxDiagnostics

    init(
        seal: @escaping @Sendable () -> FilesystemObservationLifecycleTransitionResult,
        invalidate: @escaping @Sendable () -> FilesystemObservationLifecycleTransitionResult,
        finish: @escaping @Sendable () -> FilesystemObservationLifecycleTransitionResult,
        diagnostics: @escaping @Sendable () -> FilesystemObservationMailboxDiagnostics
    ) {
        sealImplementation = seal
        invalidateImplementation = invalidate
        finishImplementation = finish
        diagnosticsImplementation = diagnostics
    }

    func seal() -> FilesystemObservationLifecycleTransitionResult {
        sealImplementation()
    }

    func invalidate() -> FilesystemObservationLifecycleTransitionResult {
        invalidateImplementation()
    }

    func finish() -> FilesystemObservationLifecycleTransitionResult {
        finishImplementation()
    }

    var diagnostics: FilesystemObservationMailboxDiagnostics {
        diagnosticsImplementation()
    }

    var stateSnapshot: FilesystemObservationLifecycleStateSnapshot {
        diagnosticsImplementation().lifecycleState
    }
}
