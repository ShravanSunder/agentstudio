import Foundation
import Testing

@testable import AgentStudio

enum FilesystemContentRepairProjectorTestError: Error {
    case registration
    case capture
    case acceptance
    case binding
    case recoveryEvidence
}

actor FilesystemContentRepairTestLedger {
    private var deliveryResults: [FilesystemContentRepairConsumerDeliveryResult]
    private var sourceGateResults: [FilesystemSourceGateTransitionResult]
    private(set) var delivered: [ContentRepairDeliveryRequest] = []
    private(set) var accepted: [FilesystemRepairAcknowledgementToken] = []
    private(set) var rejected: [FilesystemRepairAcknowledgementToken] = []
    private var activeDeliveries = 0
    private(set) var maximumActiveDeliveries = 0

    init(
        deliveryResults: [FilesystemContentRepairConsumerDeliveryResult] = [],
        sourceGateResults: [FilesystemSourceGateTransitionResult] = []
    ) {
        self.deliveryResults = deliveryResults
        self.sourceGateResults = sourceGateResults
    }

    func deliver(
        _ request: ContentRepairDeliveryRequest
    ) -> FilesystemContentRepairConsumerDeliveryResult {
        activeDeliveries += 1
        maximumActiveDeliveries = max(maximumActiveDeliveries, activeDeliveries)
        delivered.append(request)
        activeDeliveries -= 1
        return deliveryResults.isEmpty
            ? .disposition(.rebuiltCurrent(consumerRevision: UInt64(delivered.count)))
            : deliveryResults.removeFirst()
    }

    func accept(
        _ token: FilesystemRepairAcknowledgementToken
    ) -> FilesystemSourceGateTransitionResult {
        accepted.append(token)
        return sourceGateResults.isEmpty ? .applied : sourceGateResults.removeFirst()
    }

    func reject(
        _ token: FilesystemRepairAcknowledgementToken
    ) -> FilesystemSourceGateTransitionResult {
        rejected.append(token)
        return sourceGateResults.isEmpty ? .applied : sourceGateResults.removeFirst()
    }

    func appendDeliveryResult(_ result: FilesystemContentRepairConsumerDeliveryResult) {
        deliveryResults.append(result)
    }

    func appendSourceGateResult(_ result: FilesystemSourceGateTransitionResult) {
        sourceGateResults.append(result)
    }
}

actor FilesystemContentRepairDeliverySuspension {
    private var deliveryContinuation: CheckedContinuation<Void, Never>?
    private var observerContinuation: CheckedContinuation<Void, Never>?

    func suspendDelivery() async {
        await withCheckedContinuation { continuation in
            deliveryContinuation = continuation
            observerContinuation?.resume()
            observerContinuation = nil
        }
    }

    func waitUntilSuspended() async {
        if deliveryContinuation != nil { return }
        await withCheckedContinuation { continuation in
            observerContinuation = continuation
        }
    }

    func resumeDelivery() {
        deliveryContinuation?.resume()
        deliveryContinuation = nil
    }
}

actor FilesystemContentRepairEligibilitySuspension {
    private enum Phase {
        case waitingForValidation
        case waitingForValidationWithObserver(CheckedContinuation<Void, Never>)
        case suspended(CheckedContinuation<Void, Never>)
        case released
    }

    private var phase: Phase = .waitingForValidation

    func validate(
        _ generation: ContentRepairActivatedGeneration,
        registry: WorktreeContentRepairConsumerRegistry
    ) async -> ContentRepairProjectionEligibilityResult {
        switch phase {
        case .waitingForValidation, .waitingForValidationWithObserver:
            break
        case .released:
            return await registry.validateProjectionEligibility(generation)
        case .suspended:
            preconditionFailure("only one eligibility validation may suspend")
        }
        await withCheckedContinuation { validationContinuation in
            switch phase {
            case .waitingForValidation:
                phase = .suspended(validationContinuation)
            case .waitingForValidationWithObserver(let observerContinuation):
                phase = .suspended(validationContinuation)
                observerContinuation.resume()
            case .suspended, .released:
                preconditionFailure("eligibility suspension phase changed before installation")
            }
        }
        return await registry.validateProjectionEligibility(generation)
    }

    func waitUntilSuspended() async {
        switch phase {
        case .suspended, .released:
            return
        case .waitingForValidation:
            await withCheckedContinuation { observerContinuation in
                phase = .waitingForValidationWithObserver(observerContinuation)
            }
        case .waitingForValidationWithObserver:
            preconditionFailure("only one suspension observer may wait")
        }
    }

    func resumeValidation() {
        guard case .suspended(let continuation) = phase else {
            preconditionFailure("eligibility validation must be suspended before resume")
        }
        phase = .released
        continuation.resume()
    }
}

actor ContentRepairForwardingEligibilitySuspension {
    private enum Phase {
        case waiting
        case observing(CheckedContinuation<Void, Never>)
        case suspended(CheckedContinuation<Void, Never>)
        case released
    }

    private var phase: Phase = .waiting

    func validate(
        _ acknowledgement: ContentRepairAcceptedAcknowledgement,
        registry: WorktreeContentRepairConsumerRegistry
    ) async -> ContentRepairForwardingEligibilityResult {
        switch phase {
        case .waiting, .observing:
            break
        case .released:
            return await registry.validateAcknowledgementForwardingEligibility(acknowledgement)
        case .suspended:
            preconditionFailure("only one forwarding validation may suspend")
        }
        await withCheckedContinuation { continuation in
            switch phase {
            case .waiting:
                phase = .suspended(continuation)
            case .observing(let observer):
                phase = .suspended(continuation)
                observer.resume()
            case .suspended, .released:
                preconditionFailure("forwarding suspension phase changed before installation")
            }
        }
        return await registry.validateAcknowledgementForwardingEligibility(acknowledgement)
    }

    func waitUntilSuspended() async {
        switch phase {
        case .suspended, .released:
            return
        case .waiting:
            await withCheckedContinuation { phase = .observing($0) }
        case .observing:
            preconditionFailure("only one forwarding observer may wait")
        }
    }

    func resumeValidation() {
        guard case .suspended(let continuation) = phase else {
            preconditionFailure("forwarding validation must suspend before resume")
        }
        phase = .released
        continuation.resume()
    }
}

actor FilesystemContentRepairRegistryAcknowledgementGate {
    private(set) var acknowledgementAttempts = 0

    func acknowledge(
        registry: WorktreeContentRepairConsumerRegistry,
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken,
        disposition: ContentRepairConsumerDisposition
    ) async -> ContentRepairAcknowledgementResult {
        acknowledgementAttempts += 1
        guard acknowledgementAttempts > 1 else {
            return .debtRetained(.repairNotBound)
        }
        return await registry.acknowledge(
            repairGenerationID: repairGenerationID,
            consumer: consumer,
            disposition: disposition
        )
    }
}

struct FilesystemContentRepairProjectorFixture {
    let registry: WorktreeContentRepairConsumerRegistry
    let projector: FilesystemContentRepairProjector
    let request: FilesystemContentRepairProjectionRequest
    let consumers: [ContentRepairConsumerRegistration]
    let ledger: FilesystemContentRepairTestLedger
}

func makeContentRepairProjectorFixture(
    consumerCount: Int,
    deliveryResults: [FilesystemContentRepairConsumerDeliveryResult] = [],
    sourceGateResults: [FilesystemSourceGateTransitionResult] = [],
    acceptanceKind: ContentRepairTestAcceptanceKind = .continuity,
    registration: FSEventRegistrationToken = contentRepairTestRegistration(),
    identity: FilesystemContentRepairProjectorIdentity = .generate()
) async throws -> FilesystemContentRepairProjectorFixture {
    let registry = WorktreeContentRepairConsumerRegistry()
    var consumers: [ContentRepairConsumerRegistration] = []
    for _ in 0..<consumerCount {
        guard
            case .registered(let consumer) = await registry.register(
                registration: registration,
                eligibility: .eligible
            )
        else { throw FilesystemContentRepairProjectorTestError.registration }
        consumers.append(consumer)
    }
    guard
        case .prepared(let capture) = await registry.prepareCapture(
            identity: .generate(),
            registration: registration
        )
    else { throw FilesystemContentRepairProjectorTestError.capture }

    let projectorParticipant = identity.participant(generation: 7)
    let participants = capture.sourceGateParticipants.union([
        projectorParticipant,
        contentRepairTestParticipant(.gitWorkingDirectoryProjector),
        contentRepairTestParticipant(.paneFilesystemProjection),
    ])
    let acceptance = try makeContentRepairAcceptance(
        kind: acceptanceKind,
        registration: registration,
        participants: participants
    )
    guard
        case .boundActive(let active) = await registry.bind(
            capture,
            to: acceptance.repairGeneration
        )
    else { throw FilesystemContentRepairProjectorTestError.binding }

    let ledger = FilesystemContentRepairTestLedger(
        deliveryResults: deliveryResults,
        sourceGateResults: sourceGateResults
    )
    let projector = FilesystemContentRepairProjector(
        identity: identity,
        participantGeneration: 7,
        consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
            await ledger.deliver(request)
        },
        registryPort: FilesystemContentRepairRegistryPort(registry: registry),
        sourceGatePort: FilesystemContentRepairSourceGatePort(
            accept: { token in await ledger.accept(token) },
            reject: { token, _ in await ledger.reject(token) }
        )
    )
    return FilesystemContentRepairProjectorFixture(
        registry: registry,
        projector: projector,
        request: FilesystemContentRepairProjectionRequest(
            acceptance: acceptance,
            activatedGeneration: active
        ),
        consumers: consumers,
        ledger: ledger
    )
}

enum ContentRepairTestAcceptanceKind {
    case mailbox
    case continuity
}

func makeContentRepairAcceptance(
    kind: ContentRepairTestAcceptanceKind,
    registration: FSEventRegistrationToken,
    participants: Set<FilesystemRepairParticipantToken>
) throws -> FilesystemContentRepairAdmissionAcceptance {
    switch kind {
    case .continuity:
        let binding = contentRepairTestBinding(registration: registration)
        var gate = FilesystemSourceGate(binding: binding)
        let authority = FilesystemContinuityRepairHandoffAuthority(
            acceptingBinding: binding,
            handoffIdentity: FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate()),
            desiredIdentity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 1)
        )
        guard
            case .admitted(let acceptance) = gate.acceptContinuityRepairHandoff(
                authority,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: participants
            )
        else { throw FilesystemContentRepairProjectorTestError.acceptance }
        return .continuity(acceptance)
    case .mailbox:
        let evidence = try makeContentRepairRecoveryEvidence(registration: registration)
        var gate = FilesystemSourceGate(binding: evidence.revision.binding)
        guard
            case .admitted(let acceptance) = gate.acceptMailboxRecovery(
                evidence,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: participants
            )
        else { throw FilesystemContentRepairProjectorTestError.acceptance }
        return .mailbox(acceptance)
    }
}

func makeManualContentRepairAcceptance(
    registration: FSEventRegistrationToken,
    sequence: UInt64,
    participants: Set<FilesystemRepairParticipantToken>
) -> FilesystemContentRepairAdmissionAcceptance {
    let binding = contentRepairTestBinding(registration: registration)
    return .continuity(
        FilesystemSourceGateContinuityRepairAcceptance(
            authority: FilesystemContinuityRepairHandoffAuthority(
                acceptingBinding: binding,
                handoffIdentity: FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate()),
                desiredIdentity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
                acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: sequence)
            ),
            repairGeneration: RepairGeneration(
                id: RepairGenerationID(registration: registration, sequence: sequence),
                watermark: .recoveryRevision(sequence),
                trigger: .continuityLoss,
                participants: participants
            )
        )
    )
}

func contentRepairTestRegistration() -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUIDv7.generate()
        ),
        registrationGeneration: 3,
        rootGeneration: 5
    )
}

func contentRepairTestRegistration(
    sourceID: FilesystemSourceID,
    registrationGeneration: UInt64
) -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: sourceID,
        registrationGeneration: registrationGeneration,
        rootGeneration: 5
    )
}

func requireContentRepairRetirementReceipt(
    _ result: ContentRepairSourceRetirementResult
) throws -> ContentRepairSourceRetirementReceipt {
    guard case .retired(let receipt) = result else {
        Issue.record("Expected owner-issued content repair retirement receipt")
        throw FilesystemContentRepairProjectorTestError.registration
    }
    return receipt
}

func contentRepairTestParticipant(
    _ kind: FilesystemRepairParticipantKind
) -> FilesystemRepairParticipantToken {
    FilesystemRepairParticipantToken(
        kind: kind,
        participantID: UUIDv7.generate(),
        participantGeneration: 1
    )
}

func contentRepairTestBinding(
    registration: FSEventRegistrationToken
) -> FilesystemObservationSlotBinding {
    FilesystemObservationSlotBinding(
        fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity(value: UUIDv7.generate()),
        physicalSlotID: FilesystemObservationPhysicalSlotID(value: UUIDv7.generate()),
        identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
        registration: registration,
        controlBlockIdentity: FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
    )
}

func makeContentRepairRecoveryEvidence(
    registration: FSEventRegistrationToken
) throws -> FixedFilesystemRecoveryEvidenceSnapshot {
    let mailbox = try FilesystemObservationMailbox(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0,
        limits: GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 1,
            maximumRetainedBytes: 256,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 256,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 256,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 256)
        )
    )
    _ = mailbox.installTestConfiguration(registration)
    guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
        case .committed(let starting) = mailbox.beginNativeLifetime(selection.reservation),
        case .created(let ports) = mailbox.nativeGenerationPorts(for: starting)
    else { throw FilesystemContentRepairProjectorTestError.recoveryEvidence }
    let limits = try FSEventCaptureLimits(
        maximumInspectedNativeRecords: 1,
        maximumCopiedRecords: 1,
        maximumCopiedUTF8Bytes: 256,
        maximumSinglePathUTF8Bytes: 256
    )
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: starting,
        captureLimits: limits,
        callbackQueueLabel: "test.filesystem-content-repair-projector"
    )
    guard case .acquired(let lease) = controlBlock.acquireCallbackLease() else {
        throw FilesystemContentRepairProjectorTestError.recoveryEvidence
    }
    defer { _ = lease.release() }
    let observation = try FSEventObservation(
        registration: registration,
        capturedAt: ContinuousClock.now,
        totalRecordCount: .exact(0),
        inspectedNativeRecordCount: 0,
        records: [],
        unionedInspectedFlags: [],
        eventIDWatermark: .noInspectedRecords,
        completeness: .complete
    )
    let result = ports.callbackAdmissionPort.admit(
        using: lease,
        preflight: FilesystemObservationCallbackPreflight(captureLimits: limits)
    ) {
        .offer(.requiresRecovery(observation, evidence: .continuityLoss))
    }
    guard case .admitted(_, let admission) = result,
        case .admitted(let disposition, _) = admission,
        case .retainedWithRecovery(let evidence) = disposition
    else { throw FilesystemContentRepairProjectorTestError.recoveryEvidence }
    return evidence
}
