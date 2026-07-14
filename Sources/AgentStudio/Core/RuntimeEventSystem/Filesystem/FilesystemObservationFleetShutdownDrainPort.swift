// swiftlint:disable:next type_name
struct FilesystemObservationFleetShutdownActorDebtSnapshot: Equatable, Sendable {
    let semanticReplay: FilesystemObservationSemanticShutdownDebtSnapshot
    let sourceGatesInBindingDeclarationOrder: [FilesystemSourceGateShutdownDebtSnapshot]

    var isSemanticTransferQuiescent: Bool {
        semanticReplay.isQuiescent
    }

    var hasReadySourceGate: Bool {
        sourceGatesInBindingDeclarationOrder.contains {
            $0.shutdownBeginReadiness == .ready
        }
    }

    var haveAllSourceGatesBegunShutdown: Bool {
        sourceGatesInBindingDeclarationOrder.allSatisfy {
            $0.shutdownBeginReadiness == .alreadyBegan
        }
    }

    var isQuiescent: Bool {
        isSemanticTransferQuiescent && haveAllSourceGatesBegunShutdown
    }
}

enum FilesystemObservationRecoveryContextResolution: Sendable {
    case resolved(FilesystemObservationRecoveryAdmissionContext)
    case unavailable
}

struct FilesystemObservationRecoveryContextResolver: Sendable {
    private let resolveImplementation:
        @Sendable (
            FilesystemObservationSlotBinding,
            FixedFilesystemRecoveryEvidenceSnapshot
        ) -> FilesystemObservationRecoveryContextResolution

    init(
        _ resolve:
            @escaping @Sendable (
                FilesystemObservationSlotBinding,
                FixedFilesystemRecoveryEvidenceSnapshot
            ) -> FilesystemObservationRecoveryContextResolution
    ) {
        resolveImplementation = resolve
    }

    func resolve(
        binding: FilesystemObservationSlotBinding,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot
    ) -> FilesystemObservationRecoveryContextResolution {
        resolveImplementation(binding, evidence)
    }

    static let unavailable = Self { _, _ in
        .unavailable
    }
}

// swiftlint:disable:next type_name
enum FilesystemObservationFleetShutdownDrainConfigurationRejection: Equatable, Sendable {
    case physicalSlotCoverageMismatch(
        mailboxPhysicalSlotIDsInDeclarationOrder: [FilesystemObservationPhysicalSlotID],
        actorBindingsInDeclarationOrder: [FilesystemObservationSlotBinding]
    )
}

enum FilesystemObservationFleetShutdownDrainNoProgress: Equatable, Sendable {
    case configurationRejected(
        FilesystemObservationFleetShutdownDrainConfigurationRejection
    )
    case mailboxEmpty
    case activeLeaseAlreadyTaken
    case mailboxClosed
    case undeclaredBinding(FilesystemObservationSlotBinding)
    case recoveryContextUnavailable(
        binding: FilesystemObservationSlotBinding,
        evidence: FixedFilesystemRecoveryEvidenceRevision
    )
}

// swiftlint:disable:next type_name
enum FilesystemObservationFleetShutdownDrainAdvanceResult: Equatable, Sendable {
    case leaseTransfer(
        binding: FilesystemObservationSlotBinding,
        FilesystemObservationLeaseTransferResult
    )
    case cleanup(AdmissionCleanupTurnResult)
    case noProgress(FilesystemObservationFleetShutdownDrainNoProgress)
}

enum FilesystemObservationSourceGateShutdownTurnResult: Equatable, Sendable {
    case applied(
        binding: FilesystemObservationSlotBinding,
        debt: FilesystemSourceGateShutdownDebtSnapshot
    )
    case allGatesAlreadyShutdown(FilesystemObservationFleetShutdownActorDebtSnapshot)
    case outstandingDebt(FilesystemObservationFleetShutdownActorDebtSnapshot)
}

/// Actor-hopping fleet-shutdown operations over the existing drain owner.
///
/// The port owns no actor, task, queue, lock, payload, or shutdown identity.
/// Its closures preserve the owning actor's isolation while fleet coordination
/// retains only payload-free results.
struct FilesystemObservationFleetShutdownDrainPort: Sendable {
    private let snapshotImplementation: @Sendable () async -> FilesystemObservationFleetShutdownActorDebtSnapshot
    private let advanceOneTurnImplementation: @Sendable () async -> FilesystemObservationFleetShutdownDrainAdvanceResult
    private let beginOneReadySourceGateShutdownImplementation:
        @Sendable () async -> FilesystemObservationSourceGateShutdownTurnResult

    init(
        snapshot:
            @escaping @Sendable () async ->
            FilesystemObservationFleetShutdownActorDebtSnapshot,
        advanceOneTurn:
            @escaping @Sendable () async ->
            FilesystemObservationFleetShutdownDrainAdvanceResult,
        beginOneReadySourceGateShutdown:
            @escaping @Sendable () async ->
            FilesystemObservationSourceGateShutdownTurnResult
    ) {
        snapshotImplementation = snapshot
        advanceOneTurnImplementation = advanceOneTurn
        beginOneReadySourceGateShutdownImplementation =
            beginOneReadySourceGateShutdown
    }

    func snapshot() async -> FilesystemObservationFleetShutdownActorDebtSnapshot {
        await snapshotImplementation()
    }

    func advanceOneTurn() async -> FilesystemObservationFleetShutdownDrainAdvanceResult {
        await advanceOneTurnImplementation()
    }

    func beginOneReadySourceGateShutdown() async
        -> FilesystemObservationSourceGateShutdownTurnResult
    {
        await beginOneReadySourceGateShutdownImplementation()
    }
}
