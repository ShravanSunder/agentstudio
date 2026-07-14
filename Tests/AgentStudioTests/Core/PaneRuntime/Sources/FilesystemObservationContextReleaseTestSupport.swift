import Foundation

@testable import AgentStudio

struct UnpublishedContextReleaseFixture {
    let mailbox: FilesystemObservationMailbox
    let nativeOwner: DarwinFSEventRegistrationNativeOwner
    let binding: FilesystemObservationSlotBinding
    let retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime
    let completion: DarwinFSEventUnpublishedNativeCompletion
    let finalReceipt: FilesystemObservationUnpublishedFinalReceipt
    let contextFinalizer: D3NativeFinalizationLedger
}

func makeUnpublishedContextReleaseFixture(
    generationValue: UInt64 = 1
) throws -> UnpublishedContextReleaseFixture {
    let mailbox = try FilesystemObservationMailbox(
        generation: AdmissionGeneration(
            owner: .filesystemObservation,
            value: generationValue
        ),
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0,
        limits: leaseTransferMailboxLimits()
    )
    _ = mailbox.installTestConfiguration(makeRegistration(generation: 1))
    let selection = try requireSelectedDesiredSource(
        mailbox.selectNextDesiredSource()
    )
    let startingNativeLifetime = try requireCommittedNativeLifetime(
        mailbox.beginNativeLifetime(selection.reservation)
    )
    guard
        case .created(let ports) = mailbox.nativeGenerationPorts(
            for: startingNativeLifetime
        ),
        case .creationAbandoned(let creationAbandonment) =
            ports.nativeOwner.abandonCreation(),
        case .retirementRequired(let retiringLifetime) =
            mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                startingNativeLifetime
            )
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    let completion = DarwinFSEventUnpublishedNativeCompletion.creationAbandoned(
        creationAbandonment
    )
    guard
        case .finalized(let finalReceipt) = mailbox.lifecyclePort
            .finalizeUnpublishedNativeGeneration(
                retiringLifetime,
                completion: completion
            )
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    return UnpublishedContextReleaseFixture(
        mailbox: mailbox,
        nativeOwner: ports.nativeOwner,
        binding: startingNativeLifetime.binding,
        retiringLifetime: retiringLifetime,
        completion: completion,
        finalReceipt: finalReceipt,
        contextFinalizer: D3NativeFinalizationLedger()
    )
}

struct UnpublishedRegistryContextReleaseFixture {
    let registry: FilesystemObservationSlotRegistry
    let sourceID: FilesystemSourceID
    let binding: FilesystemObservationSlotBinding
    let acknowledgement: FilesystemObservationContextReleaseAcknowledgement
}

func makeUnpublishedRegistryContextReleaseFixture() throws
    -> UnpublishedRegistryContextReleaseFixture
{
    let registry = try makeRegistry(physicalSlotCount: 1)
    _ = registry.installTestConfiguration(makeRegistration(generation: 1))
    let selection = try requireSelectedDesiredSource(
        registry.selectNextDesiredSource()
    )
    let startingNativeLifetime = try requireCommittedNativeLifetime(
        registry.beginNativeLifetime(selection.reservation)
    )
    guard
        case .retirementRequired(let retiringLifetime) =
            registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                startingNativeLifetime
            ),
        case .finalized(let receipt) = registry.finalizeUnpublishedNativeGeneration(
            retiringLifetime,
            completion: .creationAbandoned(
                DarwinFSEventRegistrationCreationAbandonment(
                    startingNativeLifetime: startingNativeLifetime
                )
            )
        )
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    let acknowledgement = FilesystemObservationContextReleaseAcknowledgement.unpublished(
        .neverMaterialized(
            receipt: receipt,
            finalization: FilesystemObservationNeverMaterializedFinalization(
                startingNativeLifetime: startingNativeLifetime
            ),
            releaseAuthority: FilesystemObservationContextReleaseAuthority(
                value: UUIDv7.generate()
            )
        )
    )
    return UnpublishedRegistryContextReleaseFixture(
        registry: registry,
        sourceID: startingNativeLifetime.desiredRegistration.sourceID,
        binding: startingNativeLifetime.binding,
        acknowledgement: acknowledgement
    )
}

func replacingUnpublishedRetirementAuthority(
    in acknowledgement: FilesystemObservationContextReleaseAcknowledgement
) -> FilesystemObservationContextReleaseAcknowledgement {
    guard
        case .unpublished(
            .neverMaterialized(let receipt, let finalization, let releaseAuthority)
        ) = acknowledgement
    else {
        preconditionFailure("context-release fixture must use never-materialized lineage")
    }
    return .unpublished(
        .neverMaterialized(
            receipt: FilesystemObservationUnpublishedFinalReceipt(
                retiringLifetime: receipt.retiringLifetime,
                completion: receipt.completion,
                retirementAuthority: FilesystemUnpublishedRetirementAuthority(
                    value: UUIDv7.generate()
                )
            ),
            finalization: finalization,
            releaseAuthority: releaseAuthority
        )
    )
}

func replacingContextReleaseAuthority(
    in acknowledgement: FilesystemObservationContextReleaseAcknowledgement
) -> FilesystemObservationContextReleaseAcknowledgement {
    guard
        case .unpublished(.neverMaterialized(let receipt, let finalization, _)) =
            acknowledgement
    else {
        preconditionFailure("context-release fixture must use never-materialized lineage")
    }
    return .unpublished(
        .neverMaterialized(
            receipt: receipt,
            finalization: finalization,
            releaseAuthority: FilesystemObservationContextReleaseAuthority(
                value: UUIDv7.generate()
            )
        )
    )
}

struct FenceBackedContextReleaseFixture {
    let mailbox: FilesystemObservationMailbox
    let binding: FilesystemObservationSlotBinding
    let retirementReceipt: FilesystemObservationSlotRetirementReceipt
    let acknowledgement: FilesystemObservationContextReleaseAcknowledgement
    let contextFinalizer: D3NativeFinalizationLedger
}

func makeFenceBackedContextReleaseFixture(
    generationValue: UInt64
) async throws -> FenceBackedContextReleaseFixture {
    let mailbox = try FilesystemObservationMailbox(
        generation: AdmissionGeneration(
            owner: .filesystemObservation,
            value: generationValue
        ),
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0,
        limits: leaseTransferMailboxLimits()
    )
    _ = mailbox.installTestConfiguration(makeRegistration(generation: generationValue))
    let selection = try requireSelectedDesiredSource(mailbox.selectNextDesiredSource())
    let startingNativeLifetime = try requireCommittedNativeLifetime(
        mailbox.beginNativeLifetime(selection.reservation)
    )
    guard case .created(let ports) = mailbox.nativeGenerationPorts(for: startingNativeLifetime)
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    let captureLimits = try FSEventCaptureLimits(
        maximumInspectedNativeRecords: 8,
        maximumCopiedRecords: 8,
        maximumCopiedUTF8Bytes: 4096,
        maximumSinglePathUTF8Bytes: 1024
    )
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: startingNativeLifetime,
        captureLimits: captureLimits,
        callbackQueueLabel: "test.context-release.authority"
    )
    let adapter = LeaseTransferCallbackAdapter(
        controlBlock: controlBlock,
        callbackAdmissionPort: ports.callbackAdmissionPort
    )
    guard
        case .created(let generation) = ports.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: LeaseTransferNativeDriver(),
            callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
        ),
        case .started = await ports.nativeOwner.startOrReplay(creation: generation),
        case .closed(let drainReceipt) = await generation.close(),
        case .installed = mailbox.lifecyclePort.requestRetirementFence(drainReceipt)
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    let drainHarness = try FilesystemObservationDrainHarnessActor(
        mailbox: mailbox,
        bindings: [startingNativeLifetime.binding],
        maximumContributionsPerLease: 1
    )
    guard case .lease(let lease) = await drainHarness.takeLease(),
        case .completed(.transferred(let transferReceipt)) = await drainHarness.transferLease(
            lease,
            recoveryContext: .notRequired
        ),
        case .retired(let retirementReceipt) = transferReceipt.outcome,
        case .issued(let retirementPermit) = mailbox.lifecyclePort
            .fenceBackedRetirementPermit(for: retirementReceipt)
    else {
        throw FilesystemObservationContextReleaseTestFailure.retirementFenceUnavailable
    }
    let contextFinalizer = D3NativeFinalizationLedger()
    guard
        case .finalized(let acknowledgement) = ports.nativeOwner.finalizeNativeLifetime(
            using: retirementPermit,
            contextFinalizer: contextFinalizer
        )
    else {
        throw FilesystemObservationContextReleaseTestFailure.acknowledgementUnavailable
    }
    return FenceBackedContextReleaseFixture(
        mailbox: mailbox,
        binding: startingNativeLifetime.binding,
        retirementReceipt: retirementReceipt,
        acknowledgement: acknowledgement,
        contextFinalizer: contextFinalizer
    )
}

func replacingFenceIdentity(
    in acknowledgement: FilesystemObservationContextReleaseAcknowledgement
) -> FilesystemObservationContextReleaseAcknowledgement {
    guard case .fenceBacked(let release) = acknowledgement else {
        preconditionFailure("context-release fixture must use fence-backed lineage")
    }
    return replacingFenceBackedReceipt(
        in: release,
        fenceIdentity: FilesystemObservationRetirementFenceIdentity(value: UUIDv7.generate()),
        retirementAuthority: release.receipt.retirementAuthority,
        releaseAuthority: release.releaseAuthority
    )
}

func replacingFenceRetirementAuthority(
    in acknowledgement: FilesystemObservationContextReleaseAcknowledgement,
    with retirementAuthority: FilesystemObservationSlotRetirementAuthority
) -> FilesystemObservationContextReleaseAcknowledgement {
    guard case .fenceBacked(let release) = acknowledgement else {
        preconditionFailure("context-release fixture must use fence-backed lineage")
    }
    return replacingFenceBackedReceipt(
        in: release,
        fenceIdentity: release.receipt.fenceIdentity,
        retirementAuthority: retirementAuthority,
        releaseAuthority: release.releaseAuthority
    )
}

func replacingFenceReleaseAuthority(
    in acknowledgement: FilesystemObservationContextReleaseAcknowledgement
) -> FilesystemObservationContextReleaseAcknowledgement {
    guard case .fenceBacked(let release) = acknowledgement else {
        preconditionFailure("context-release fixture must use fence-backed lineage")
    }
    return replacingFenceBackedReceipt(
        in: release,
        fenceIdentity: release.receipt.fenceIdentity,
        retirementAuthority: release.receipt.retirementAuthority,
        releaseAuthority: FilesystemObservationContextReleaseAuthority(value: UUIDv7.generate())
    )
}

private func replacingFenceBackedReceipt(
    in release: FilesystemFenceContextReleaseAcknowledgement,
    fenceIdentity: FilesystemObservationRetirementFenceIdentity,
    retirementAuthority: FilesystemObservationSlotRetirementAuthority,
    releaseAuthority: FilesystemObservationContextReleaseAuthority
) -> FilesystemObservationContextReleaseAcknowledgement {
    .fenceBacked(
        FilesystemFenceContextReleaseAcknowledgement(
            receipt: FilesystemObservationSlotRetirementReceipt(
                binding: release.receipt.binding,
                fenceIdentity: fenceIdentity,
                disposition: release.receipt.disposition,
                retirementAuthority: retirementAuthority
            ),
            finalization: release.finalization,
            releaseAuthority: releaseAuthority
        )
    )
}

enum FilesystemObservationContextReleaseTestFailure: Error {
    case fixtureConstructionFailed
    case acknowledgementUnavailable
    case expectedAppliedAcknowledgement
    case nativeCloseFailed
    case retirementFenceUnavailable
    case successorDidNotAwaitPredecessor
    case leaseUnavailable
    case transferDidNotComplete
    case predecessorRetirementUnavailable
}
