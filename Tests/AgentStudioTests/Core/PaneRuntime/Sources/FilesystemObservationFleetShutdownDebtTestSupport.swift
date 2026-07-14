import Foundation
import Testing

@testable import AgentStudio

struct ShutdownDebtStartingFixture {
    let mailbox: FilesystemObservationMailbox
    let registration: FSEventRegistrationToken
    let startingLifetime: FilesystemObservationStartingNativeLifetime
}

struct ShutdownDebtClosedFenceFixture {
    let mailbox: FilesystemObservationMailbox
    let binding: FilesystemObservationSlotBinding
    let receipt: DarwinFSEventRegistrationLeaseDrainReceipt
}

struct ShutdownDebtAwaitingPredecessorFixture {
    let mailbox: FilesystemObservationMailbox
    let installedPredecessor: FilesystemRetirementFenceInstalledLifetime
    let awaitingSuccessor: FilesystemClosingAwaitingPredecessorLifetime
}

func makeShutdownDebtAwaitingPredecessorFixture(
    generationValue: UInt64
) async throws -> ShutdownDebtAwaitingPredecessorFixture {
    let generation = AdmissionGeneration(owner: .filesystemObservation, value: generationValue)
    let predecessorRegistration = makeRegistration(registrationGeneration: generationValue)
    let successorRegistration = FSEventRegistrationToken(
        sourceID: predecessorRegistration.sourceID,
        registrationGeneration: generationValue + 1,
        rootGeneration: predecessorRegistration.rootGeneration
    )
    let mailbox = try FilesystemObservationMailbox(
        generation: generation,
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 1,
        limits: fleetMailboxLimits(global: 8, perRegistration: 4, perLease: 1)
    )
    _ = mailbox.installTestConfiguration(predecessorRegistration)
    let predecessorSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
    let predecessorStarting = requireShutdownDebtStartingLifetime(
        mailbox.beginNativeLifetime(predecessorSelection.reservation)
    )
    let predecessorGeneration = try await makeShutdownDebtNativeGeneration(
        mailbox: mailbox,
        starting: predecessorStarting,
        label: "test.shutdown-debt.predecessor"
    )
    _ = mailbox.installTestConfiguration(successorRegistration)
    guard
        case .closed(let predecessorReceipt) = await predecessorGeneration.close(),
        case .installed(let installedPredecessor) = mailbox.lifecyclePort
            .requestRetirementFence(predecessorReceipt)
    else {
        throw ShutdownDebtFixtureError.retirementFenceUnavailable
    }
    let successorSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
    let successorStarting = requireShutdownDebtStartingLifetime(
        mailbox.beginNativeLifetime(successorSelection.reservation)
    )
    let successorGeneration = try await makeShutdownDebtNativeGeneration(
        mailbox: mailbox,
        starting: successorStarting,
        label: "test.shutdown-debt.successor"
    )
    guard
        case .closed(let successorReceipt) = await successorGeneration.close(),
        case .awaitingPredecessor(let awaitingSuccessor) = mailbox.lifecyclePort
            .requestRetirementFence(successorReceipt)
    else {
        throw ShutdownDebtFixtureError.retirementFenceUnavailable
    }
    return ShutdownDebtAwaitingPredecessorFixture(
        mailbox: mailbox,
        installedPredecessor: installedPredecessor,
        awaitingSuccessor: awaitingSuccessor
    )
}

private func makeShutdownDebtNativeGeneration(
    mailbox: FilesystemObservationMailbox,
    starting: FilesystemObservationStartingNativeLifetime,
    label: String
) async throws -> DarwinFSEventRegistrationGeneration {
    let ports = requireShutdownDebtNativePorts(mailbox.nativeGenerationPorts(for: starting))
    let captureLimits = try FSEventCaptureLimits(
        maximumInspectedNativeRecords: 8,
        maximumCopiedRecords: 8,
        maximumCopiedUTF8Bytes: 4096,
        maximumSinglePathUTF8Bytes: 1024
    )
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: starting,
        captureLimits: captureLimits,
        callbackQueueLabel: label
    )
    let adapter = LeaseTransferCallbackAdapter(
        controlBlock: controlBlock,
        callbackAdmissionPort: ports.callbackAdmissionPort
    )
    guard
        case .created(let nativeGeneration) = ports.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: LeaseTransferNativeDriver(),
            callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
        ),
        case .started = await nativeGeneration.start()
    else {
        throw ShutdownDebtFixtureError.nativeGenerationUnavailable
    }
    return nativeGeneration
}

func makeShutdownDebtClosedFenceFixture(
    generationValue: UInt64,
    limits: GatherMailboxLimits = leaseTransferMailboxLimits()
) async throws -> ShutdownDebtClosedFenceFixture {
    let generation = AdmissionGeneration(owner: .filesystemObservation, value: generationValue)
    let registration = makeRegistration(registrationGeneration: generationValue)
    let mailbox = try FilesystemObservationMailbox(
        generation: generation,
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0,
        limits: limits
    )
    _ = mailbox.installTestConfiguration(registration)
    let selection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
    let starting = requireShutdownDebtStartingLifetime(
        mailbox.beginNativeLifetime(selection.reservation)
    )
    let ports = requireShutdownDebtNativePorts(mailbox.nativeGenerationPorts(for: starting))
    let captureLimits = try FSEventCaptureLimits(
        maximumInspectedNativeRecords: 8,
        maximumCopiedRecords: 8,
        maximumCopiedUTF8Bytes: 4096,
        maximumSinglePathUTF8Bytes: 1024
    )
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: starting,
        captureLimits: captureLimits,
        callbackQueueLabel: "test.shutdown-debt.closed-fence"
    )
    let adapter = LeaseTransferCallbackAdapter(
        controlBlock: controlBlock,
        callbackAdmissionPort: ports.callbackAdmissionPort
    )
    guard
        case .created(let nativeGeneration) = ports.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: LeaseTransferNativeDriver(),
            callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
        ),
        case .started = await nativeGeneration.start(),
        case .closed(let receipt) = await nativeGeneration.close()
    else {
        throw ShutdownDebtFixtureError.nativeGenerationUnavailable
    }
    return ShutdownDebtClosedFenceFixture(
        mailbox: mailbox,
        binding: starting.binding,
        receipt: receipt
    )
}

extension FilesystemObservationDesiredUpdateResult {
    var isShutdownDebtEnqueued: Bool {
        guard case .enqueued = self else { return false }
        return true
    }
}

func makeShutdownDebtMailbox(
    generation: AdmissionGeneration,
    slotCount: Int,
    limits: GatherMailboxLimits? = nil
) throws -> FilesystemObservationMailbox {
    try FilesystemObservationMailbox(
        generation: generation,
        maximumSimultaneousSourceCount: slotCount,
        replacementReserveSlotCount: 0,
        limits: limits ?? fleetMailboxLimits(global: 8, perRegistration: 4, perLease: 2)
    )
}

func makeShutdownDebtStartingFixture(
    generation: AdmissionGeneration,
    registrationIndex: Int,
    limits: GatherMailboxLimits? = nil
) throws -> ShutdownDebtStartingFixture {
    let registration = makeFleetRegistration(index: registrationIndex)
    let mailbox = try makeShutdownDebtMailbox(
        generation: generation,
        slotCount: 1,
        limits: limits
    )
    #expect(mailbox.installTestConfiguration(registration).isShutdownDebtEnqueued)
    let selected = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
    let startingLifetime = requireShutdownDebtStartingLifetime(
        mailbox.beginNativeLifetime(selected.reservation)
    )
    return ShutdownDebtStartingFixture(
        mailbox: mailbox,
        registration: registration,
        startingLifetime: startingLifetime
    )
}

func requireAppliedShutdownDebtSnapshot(
    _ result: FilesystemObservationFleetIngressFreezeAndSnapshotResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationFleetShutdownMailboxDebtSnapshot {
    guard case .applied(let snapshot) = result else {
        Issue.record("Expected applied freeze snapshot, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected applied fleet shutdown debt snapshot")
    }
    return snapshot
}

func requireAlreadyAppliedShutdownDebtSnapshot(
    _ result: FilesystemObservationFleetIngressFreezeAndSnapshotResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationFleetShutdownMailboxDebtSnapshot {
    guard case .alreadyApplied(let snapshot) = result else {
        Issue.record(
            "Expected replayed freeze snapshot, got \(result)",
            sourceLocation: sourceLocation
        )
        preconditionFailure("Expected replayed fleet shutdown debt snapshot")
    }
    return snapshot
}

func requireShutdownDebtSelection(
    _ result: FilesystemObservationDesiredSelectionResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationDesiredSelection {
    guard case .selected(let selection) = result else {
        Issue.record("Expected selected source, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected selected source")
    }
    return selection
}

func requireShutdownDebtStartingLifetime(
    _ result: FilesystemObservationNativeLifetimeCommitResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationStartingNativeLifetime {
    guard case .committed(let lifetime) = result else {
        Issue.record("Expected committed native lifetime, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected committed native lifetime")
    }
    return lifetime
}

func requireShutdownDebtRetiringLifetime(
    _ result: FilesystemObservationNativeLifetimeFailureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationRetiringUnpublishedNativeLifetime {
    guard case .retirementRequired(let lifetime) = result else {
        Issue.record("Expected retiring native lifetime, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected retiring native lifetime")
    }
    return lifetime
}

func requireShutdownDebtNativePorts(
    _ result: FilesystemObservationNativeGenerationPortCreationResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationNativeGenerationPorts {
    guard case .created(let ports) = result else {
        Issue.record("Expected native generation ports", sourceLocation: sourceLocation)
        preconditionFailure("Expected native generation ports")
    }
    return ports
}

func requireShutdownDebtAcceptingLifetime(
    _ result: FilesystemObservationAcceptingPublicationResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationAcceptingNativeLifetime {
    guard case .published(let publication) = result else {
        Issue.record("Expected accepting publication, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected accepting publication")
    }
    return publication.acceptingNativeLifetime
}

func requireShutdownDebtLease(
    _ result: FilesystemObservationTakeDrainResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationDrainLease {
    guard case .lease(let lease) = result else {
        Issue.record("Expected filesystem drain lease", sourceLocation: sourceLocation)
        preconditionFailure("Expected filesystem drain lease")
    }
    return lease
}

func admitShutdownDebtCallback(
    _ offer: FilesystemObservationOffer,
    startingLifetime: FilesystemObservationStartingNativeLifetime,
    nativePorts: FilesystemObservationNativeGenerationPorts
) throws -> DarwinFSEventObservationCaptureResult {
    let captureLimits = try FSEventCaptureLimits(
        maximumInspectedNativeRecords: 8,
        maximumCopiedRecords: 4,
        maximumCopiedUTF8Bytes: 1024,
        maximumSinglePathUTF8Bytes: 512
    )
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: startingLifetime,
        captureLimits: captureLimits,
        callbackQueueLabel: "test.filesystem-observation-shutdown-debt"
    )
    guard case .acquired(let lease) = controlBlock.acquireCallbackLease() else {
        throw ShutdownDebtFixtureError.callbackLeaseUnavailable
    }
    defer { _ = lease.release() }
    return nativePorts.callbackAdmissionPort.admit(
        using: lease,
        preflight: FilesystemObservationCallbackPreflight(captureLimits: captureLimits)
    ) { .offer(offer) }
}

func expectShutdownDebtRetainedCallback(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .admitted(_, .admitted(.retained, _)) = result else {
        Issue.record("Expected retained callback, got \(result)", sourceLocation: sourceLocation)
        return
    }
}

private enum ShutdownDebtFixtureError: Error {
    case callbackLeaseUnavailable
    case nativeGenerationUnavailable
    case retirementFenceUnavailable
}
