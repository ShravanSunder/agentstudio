import Foundation

@testable import AgentStudio

enum RegisteredWorktreeRepairIntegrationError: Error {
    case consumerRegistrationFailed
    case capturePreparationFailed
    case sourceGateAdmissionFailed
    case sourceGateReconciliationFailed
    case captureBindingFailed
    case projectionFailed
    case consumerLookupFailed
}

actor RegisteredWorktreeSourceGateHarness {
    private var sourceGate: FilesystemSourceGate
    private(set) var acceptedAcknowledgements: [FilesystemRepairAcknowledgementToken] = []
    private(set) var rejectedAcknowledgements: [FilesystemRepairAcknowledgementToken] = []

    init(binding: FilesystemObservationSlotBinding) {
        sourceGate = FilesystemSourceGate(binding: binding)
    }

    func admitContinuityRepair(
        authority: FilesystemContinuityRepairHandoffAuthority,
        participants: Set<FilesystemRepairParticipantToken>
    ) throws -> FilesystemSourceGateContinuityRepairAcceptance {
        guard
            case .admitted(let acceptance) = sourceGate.acceptContinuityRepairHandoff(
                authority,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: participants
            )
        else {
            throw RegisteredWorktreeRepairIntegrationError.sourceGateAdmissionFailed
        }
        return acceptance
    }

    func beginAndCompleteReconciliation(
        _ repairGenerationID: RepairGenerationID
    ) throws {
        guard sourceGate.beginReconciliation(repairGenerationID) == .applied,
            sourceGate.completeReconciliation(repairGenerationID) == .applied
        else {
            throw RegisteredWorktreeRepairIntegrationError.sourceGateReconciliationFailed
        }
    }

    func acknowledge(
        _ acknowledgement: FilesystemRepairAcknowledgementToken
    ) -> FilesystemSourceGateTransitionResult {
        acceptedAcknowledgements.append(acknowledgement)
        return sourceGate.acknowledge(acknowledgement)
    }

    func reject(
        _ acknowledgement: FilesystemRepairAcknowledgementToken,
        failure: FilesystemRepairAcknowledgementFailure
    ) -> FilesystemSourceGateTransitionResult {
        rejectedAcknowledgements.append(acknowledgement)
        return sourceGate.rejectAcknowledgement(acknowledgement, failure: failure)
    }

    func stateSnapshot() -> FilesystemSourceGateState {
        sourceGate.state
    }

    var projectorPort: FilesystemContentRepairSourceGatePort {
        FilesystemContentRepairSourceGatePort(
            accept: { acknowledgement in
                await self.acknowledge(acknowledgement)
            },
            reject: { acknowledgement, failure in
                await self.reject(acknowledgement, failure: failure)
            }
        )
    }
}

actor RegisteredWorktreeRepairDeliveryLedger {
    private let resultsByConsumer: [ContentRepairConsumerToken: FilesystemContentRepairConsumerDeliveryResult]
    private(set) var deliveredRequests: [ContentRepairDeliveryRequest] = []
    private var activeDeliveryCount = 0
    private(set) var maximumActiveDeliveryCount = 0

    init(
        resultsByConsumer:
            [ContentRepairConsumerToken: FilesystemContentRepairConsumerDeliveryResult]
    ) {
        self.resultsByConsumer = resultsByConsumer
    }

    func deliver(
        _ request: ContentRepairDeliveryRequest
    ) -> FilesystemContentRepairConsumerDeliveryResult {
        activeDeliveryCount += 1
        maximumActiveDeliveryCount = max(maximumActiveDeliveryCount, activeDeliveryCount)
        deliveredRequests.append(request)
        defer { activeDeliveryCount -= 1 }
        guard let result = resultsByConsumer[request.consumer] else {
            preconditionFailure("Every independently captured consumer needs one disposition")
        }
        return result
    }
}

struct RegisteredWorktreeHealthyRepairFixture {
    let registration: FSEventRegistrationToken
    let registry: WorktreeContentRepairConsumerRegistry
    let consumers: [ContentRepairConsumerRegistration]
    let capturedContentParticipants: Set<FilesystemRepairParticipantToken>
    let expectedContentParticipants: Set<FilesystemRepairParticipantToken>
    let expectedParticipants: Set<FilesystemRepairParticipantToken>
    let projectorParticipant: FilesystemRepairParticipantToken
    let gitParticipant: FilesystemRepairParticipantToken
    let paneProjectionParticipant: FilesystemRepairParticipantToken
    let sourceGate: RegisteredWorktreeSourceGateHarness
    let acceptance: FilesystemSourceGateContinuityRepairAcceptance
    let deliveryRequests: [ContentRepairDeliveryRequest]
    let deliveryLedger: RegisteredWorktreeRepairDeliveryLedger
    let projector: FilesystemContentRepairProjector
    let projectionRequest: FilesystemContentRepairProjectionRequest
}

func makeRegisteredWorktreeHealthyRepairFixture() async throws
    -> RegisteredWorktreeHealthyRepairFixture
{
    let registration = registeredWorktreeRepairRegistration()
    let registry = WorktreeContentRepairConsumerRegistry()
    var consumers: [ContentRepairConsumerRegistration] = []
    for _ in 0..<3 {
        consumers.append(
            try await requireRegisteredWorktreeConsumer(
                registry.register(registration: registration, eligibility: .eligible)
            )
        )
    }
    let capture = try await requireRegisteredWorktreeCapture(
        registry.prepareCapture(identity: .generate(), registration: registration)
    )
    let projectorIdentity = FilesystemContentRepairProjectorIdentity.generate()
    let projectorParticipant = projectorIdentity.participant(generation: 23)
    let gitParticipant = registeredWorktreeRepairParticipant(
        .gitWorkingDirectoryProjector,
        generation: 29
    )
    let paneProjectionParticipant = registeredWorktreeRepairParticipant(
        .paneFilesystemProjection,
        generation: 31
    )
    let expectedContentParticipants = Set(consumers.map { $0.token.sourceGateParticipant })
    let expectedParticipants = expectedContentParticipants.union([
        projectorParticipant,
        gitParticipant,
        paneProjectionParticipant,
    ])
    let binding = contentRepairTestBinding(registration: registration)
    let sourceGate = RegisteredWorktreeSourceGateHarness(binding: binding)
    let acceptance = try await sourceGate.admitContinuityRepair(
        authority: registeredWorktreeContinuityAuthority(binding: binding, topologyRevision: 37),
        participants: expectedParticipants
    )
    try await sourceGate.beginAndCompleteReconciliation(acceptance.repairGeneration.id)
    let activation = try await requireRegisteredWorktreeActivation(
        registry.bind(capture, to: acceptance.repairGeneration)
    )
    let deliveryRequests = activation.boundGeneration.deliveryRequests
    let deliveryLedger = RegisteredWorktreeRepairDeliveryLedger(
        resultsByConsumer: [
            deliveryRequests[0].consumer: .disposition(
                .rebuiltCurrent(consumerRevision: 41)
            ),
            deliveryRequests[1].consumer: .disposition(
                .markedNonCurrent(retry: deliveryRequests[1].retryToken)
            ),
            deliveryRequests[2].consumer: .disposition(.notApplicableNoRetainedState),
        ]
    )
    let projector = FilesystemContentRepairProjector(
        identity: projectorIdentity,
        participantGeneration: 23,
        consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
            await deliveryLedger.deliver(request)
        },
        registryPort: FilesystemContentRepairRegistryPort(registry: registry),
        sourceGatePort: await sourceGate.projectorPort
    )
    return RegisteredWorktreeHealthyRepairFixture(
        registration: registration,
        registry: registry,
        consumers: consumers,
        capturedContentParticipants: capture.sourceGateParticipants,
        expectedContentParticipants: expectedContentParticipants,
        expectedParticipants: expectedParticipants,
        projectorParticipant: projectorParticipant,
        gitParticipant: gitParticipant,
        paneProjectionParticipant: paneProjectionParticipant,
        sourceGate: sourceGate,
        acceptance: acceptance,
        deliveryRequests: deliveryRequests,
        deliveryLedger: deliveryLedger,
        projector: projector,
        projectionRequest: FilesystemContentRepairProjectionRequest(
            acceptance: .continuity(acceptance),
            activatedGeneration: activation
        )
    )
}

func registeredWorktreeRepairRegistration() -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUIDv7.generate()
        ),
        registrationGeneration: 11,
        rootGeneration: 17
    )
}

func registeredWorktreeRepairParticipant(
    _ kind: FilesystemRepairParticipantKind,
    generation: UInt64
) -> FilesystemRepairParticipantToken {
    FilesystemRepairParticipantToken(
        kind: kind,
        participantID: UUIDv7.generate(),
        participantGeneration: generation
    )
}

func registeredWorktreeContinuityAuthority(
    binding: FilesystemObservationSlotBinding,
    topologyRevision: UInt64
) -> FilesystemContinuityRepairHandoffAuthority {
    FilesystemContinuityRepairHandoffAuthority(
        acceptingBinding: binding,
        handoffIdentity: FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate()),
        desiredIdentity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
            value: topologyRevision
        )
    )
}

func requireRegisteredWorktreeConsumer(
    _ result: ContentRepairConsumerRegistrationResult
) throws -> ContentRepairConsumerRegistration {
    guard case .registered(let registration) = result else {
        throw RegisteredWorktreeRepairIntegrationError.consumerRegistrationFailed
    }
    return registration
}

func requireRegisteredWorktreeCapture(
    _ result: ContentRepairCapturePreparationResult
) throws -> ContentRepairPreparedCapture {
    guard case .prepared(let capture) = result else {
        throw RegisteredWorktreeRepairIntegrationError.capturePreparationFailed
    }
    return capture
}

func requireRegisteredWorktreeActivation(
    _ result: ContentRepairCaptureBindingResult
) throws -> ContentRepairActivatedGeneration {
    guard case .boundActive(let activation) = result else {
        throw RegisteredWorktreeRepairIntegrationError.captureBindingFailed
    }
    return activation
}

func requireRegisteredWorktreeProjectionReceipt(
    _ result: FilesystemContentRepairProjectionResult
) throws -> FilesystemContentRepairProjectionReceipt {
    guard case .completed(let receipt) = result else {
        throw RegisteredWorktreeRepairIntegrationError.projectionFailed
    }
    return receipt
}

func requireRegisteredWorktreeConsumerLookup(
    _ result: ContentRepairConsumerLookupResult
) throws -> ContentRepairConsumerRegistration {
    guard case .registered(let registration) = result else {
        throw RegisteredWorktreeRepairIntegrationError.consumerLookupFailed
    }
    return registration
}
