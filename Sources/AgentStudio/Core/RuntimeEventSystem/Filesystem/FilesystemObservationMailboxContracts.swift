import Foundation

enum FilesystemObservationMailboxConfigurationError: Error, Equatable {
    case invalidGatherLimits
}

enum FilesystemObservationRecoveryAuthoritySeed: Equatable, Sendable {
    case initial
    case preseeded(GatherRecoveryStamp)
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

enum FilesystemObservationMailboxContribution: Sendable {
    case observation(
        identity: FilesystemObservationContributionIdentity,
        observation: FSEventObservation
    )
    case retirementFence(
        identity: FilesystemObservationContributionIdentity,
        fence: FilesystemObservationSlotRetirementFence
    )

    var identity: FilesystemObservationContributionIdentity {
        switch self {
        case .observation(let identity, _), .retirementFence(let identity, _): identity
        }
    }
}

enum FilesystemObservationCallbackAuthorityRejection: Equatable, Sendable {
    case released
    case foreignControlBlock
    case registrationMismatch
    case slotBindingMismatch
    case captureConfigurationMismatch
    case alreadyConsumed
}

enum FilesystemObservationCallbackMailboxRejection: Equatable, Sendable {
    case undeclaredSlot
    case invalidFootprint
    case captureConfigurationMismatch
    case fenced
    case fleetOrdinaryAdmissionSealed
    case closed
}

struct FilesystemObservationCallbackPreflight: Equatable, Sendable {
    let captureLimits: FSEventCaptureLimits
    let maximumFootprint: GatherFootprint

    init(
        captureLimits: FSEventCaptureLimits,
        maximumFootprint: GatherFootprint
    ) {
        self.captureLimits = captureLimits
        self.maximumFootprint = maximumFootprint
    }

    init(captureLimits: FSEventCaptureLimits) {
        self.init(
            captureLimits: captureLimits,
            maximumFootprint: GatherFootprint(
                itemCount: captureLimits.maximumCopiedRecords,
                byteCount: captureLimits.maximumCopiedUTF8Bytes
            )
        )
    }

    var matchesCaptureConfiguration: Bool {
        maximumFootprint
            == GatherFootprint(
                itemCount: captureLimits.maximumCopiedRecords,
                byteCount: captureLimits.maximumCopiedUTF8Bytes
            )
    }
}

enum FilesystemObservationCallbackWakeApplication: Equatable, Sendable {
    case notRequested
    case applied
}

enum FilesystemObservationCallbackAdmissionResult: Equatable, Sendable {
    case admitted(
        FilesystemObservationOfferDisposition,
        FilesystemObservationCallbackWakeApplication
    )
    case authorityRejected(FilesystemObservationCallbackAuthorityRejection)
    case mailboxRejected(FilesystemObservationCallbackMailboxRejection)
}

protocol FilesystemObservationCallbackSynchronization: Sendable {
    func afterAuthorityConsumedBeforeMailboxOffer()
    func afterMailboxOfferBeforeWakeApplication()
}

// swiftlint:disable:next type_name
struct ImmediateFilesystemObservationCallbackSynchronization:
    FilesystemObservationCallbackSynchronization
{
    func afterAuthorityConsumedBeforeMailboxOffer() {}
    func afterMailboxOfferBeforeWakeApplication() {}
}

enum FilesystemObservationOfferDisposition: Equatable, Sendable {
    case retained
    case retainedWithRecovery(FixedFilesystemRecoveryEvidenceSnapshot)
    case contractedToRecovery(FixedFilesystemRecoveryEvidenceSnapshot)
}

struct FilesystemObservationOfferReceipt: Equatable, Sendable {
    let disposition: FilesystemObservationOfferDisposition
    let wake: AdmissionWakeDirective
}

enum FilesystemObservationOfferResult: Equatable, Sendable {
    case admitted(FilesystemObservationOfferReceipt)
    case undeclaredSlot
    case bindingMismatch
    case invalidFootprint
    case fleetOrdinaryAdmissionSealed
    case closed
}

enum FilesystemObservationDrainPayload: Sendable {
    case contributions(NonEmptyAdmissionBatch<FilesystemObservationMailboxContribution>)
    case contributionsWithRecovery(
        NonEmptyAdmissionBatch<FilesystemObservationMailboxContribution>,
        FixedFilesystemRecoveryEvidenceSnapshot
    )
    case recovery(FixedFilesystemRecoveryEvidenceSnapshot)
}

struct FilesystemObservationDrainLease: Sendable {
    let token: AdmissionDrainToken
    let binding: FilesystemObservationSlotBinding
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
    let retiringLifecycleCount: Int
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
        evidence: FixedFilesystemRecoveryAcknowledgeResult,
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

    var didAdvanceCustody: Bool {
        switch self {
        case .retried, .transferredAuthoritative, .transferredRecovery:
            true
        case .dispositionMismatch, .invalidToken, .closed:
            false
        }
    }

    func mergingWake(
        _ additionalWake: AdmissionWakeDirective
    ) -> Self {
        let mergedWake: AdmissionWakeDirective =
            wake == .scheduleDrain || additionalWake == .scheduleDrain
            ? .scheduleDrain : .noWake
        switch self {
        case .retried:
            return .retried(wake: mergedWake)
        case .transferredAuthoritative:
            return .transferredAuthoritative(wake: mergedWake)
        case .transferredRecovery(let evidence, _):
            return .transferredRecovery(evidence: evidence, wake: mergedWake)
        case .dispositionMismatch, .invalidToken, .closed:
            return self
        }
    }
}

struct FilesystemObservationMailboxDiagnostics: Sendable {
    let gather: GatherAdmissionDiagnostics
    let doorbellState: AdmissionDoorbellStateSnapshot
    let lifecycleState: FilesystemObservationLifecycleStateSnapshot
    private let recoveryEvidenceByPhysicalSlotID:
        [FilesystemObservationPhysicalSlotID: FixedFilesystemRecoveryEvidenceSnapshotResult]

    init(
        gather: GatherAdmissionDiagnostics,
        doorbellState: AdmissionDoorbellStateSnapshot,
        lifecycleState: FilesystemObservationLifecycleStateSnapshot,
        recoveryEvidenceByPhysicalSlotID:
            [FilesystemObservationPhysicalSlotID: FixedFilesystemRecoveryEvidenceSnapshotResult]
    ) {
        self.gather = gather
        self.doorbellState = doorbellState
        self.lifecycleState = lifecycleState
        self.recoveryEvidenceByPhysicalSlotID = recoveryEvidenceByPhysicalSlotID
    }

    func recoveryEvidence(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FixedFilesystemRecoveryEvidenceSnapshotResult {
        recoveryEvidenceByPhysicalSlotID[physicalSlotID] ?? .undeclaredPhysicalSlot
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
    private let requestRetirementFenceImplementation:
        @Sendable (DarwinFSEventRegistrationLeaseDrainReceipt) ->
            FilesystemObservationRetirementFenceRequestResult
    private let sealImplementation: @Sendable () -> FilesystemObservationLifecycleTransitionResult
    private let invalidateImplementation: @Sendable () -> FilesystemObservationLifecycleTransitionResult
    private let finishImplementation: @Sendable () -> FilesystemObservationLifecycleTransitionResult
    private let diagnosticsImplementation: @Sendable () -> FilesystemObservationMailboxDiagnostics

    init(
        requestRetirementFence:
            @escaping @Sendable (DarwinFSEventRegistrationLeaseDrainReceipt) ->
            FilesystemObservationRetirementFenceRequestResult,
        seal: @escaping @Sendable () -> FilesystemObservationLifecycleTransitionResult,
        invalidate: @escaping @Sendable () -> FilesystemObservationLifecycleTransitionResult,
        finish: @escaping @Sendable () -> FilesystemObservationLifecycleTransitionResult,
        diagnostics: @escaping @Sendable () -> FilesystemObservationMailboxDiagnostics
    ) {
        requestRetirementFenceImplementation = requestRetirementFence
        sealImplementation = seal
        invalidateImplementation = invalidate
        finishImplementation = finish
        diagnosticsImplementation = diagnostics
    }

    func requestRetirementFence(
        _ receipt: DarwinFSEventRegistrationLeaseDrainReceipt
    ) -> FilesystemObservationRetirementFenceRequestResult {
        requestRetirementFenceImplementation(receipt)
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
