import Foundation

struct FilesystemContentRepairProjectorIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    private init(value: UUID) {
        self.value = value
    }

    static func generate() -> Self {
        Self(value: UUIDv7.generate())
    }

    func participant(generation: UInt64) -> FilesystemRepairParticipantToken {
        FilesystemRepairParticipantToken(
            kind: .contentRepairProjector,
            participantID: value,
            participantGeneration: generation
        )
    }
}

enum FilesystemContentRepairAdmissionAcceptance: Equatable, Sendable {
    case mailbox(FilesystemSourceGateRecoveryAcceptance)
    case continuity(FilesystemSourceGateContinuityRepairAcceptance)

    var repairGeneration: RepairGeneration {
        switch self {
        case .mailbox(let acceptance):
            acceptance.repairGeneration
        case .continuity(let acceptance):
            acceptance.repairGeneration
        }
    }

    var binding: FilesystemObservationSlotBinding {
        switch self {
        case .mailbox(let acceptance):
            acceptance.acceptedEvidence.revision.binding
        case .continuity(let acceptance):
            acceptance.authority.acceptingBinding
        }
    }
}

struct FilesystemContentRepairProjectionRequest: Equatable, Sendable {
    let acceptance: FilesystemContentRepairAdmissionAcceptance
    let activatedGeneration: ContentRepairActivatedGeneration
}

enum FilesystemContentRepairDeliveryRetryReason: Equatable, Sendable {
    case consumerUnavailable
    case consumerRequestedRetry
}

enum FilesystemContentRepairConsumerDeliveryResult: Equatable, Sendable {
    case disposition(ContentRepairConsumerDisposition)
    case retryRequested(FilesystemContentRepairDeliveryRetryReason)
    case rejected(FilesystemRepairAcknowledgementFailure)
}

struct FilesystemContentRepairConsumerDeliveryPort: Sendable {
    private let deliverImplementation:
        @Sendable (ContentRepairDeliveryRequest) async -> FilesystemContentRepairConsumerDeliveryResult

    init(
        deliver:
            @escaping @Sendable (ContentRepairDeliveryRequest) async ->
            FilesystemContentRepairConsumerDeliveryResult
    ) {
        deliverImplementation = deliver
    }

    func deliver(
        _ request: ContentRepairDeliveryRequest
    ) async -> FilesystemContentRepairConsumerDeliveryResult {
        await deliverImplementation(request)
    }
}

struct FilesystemContentRepairRegistryPort: Sendable {
    private let validateProjectionImplementation:
        @Sendable (ContentRepairActivatedGeneration) async -> ContentRepairProjectionEligibilityResult
    private let validateForwardingImplementation:
        @Sendable (ContentRepairAcceptedAcknowledgement) async -> ContentRepairForwardingEligibilityResult
    private let acknowledgeImplementation:
        @Sendable (
            RepairGenerationID,
            ContentRepairConsumerToken,
            ContentRepairConsumerDisposition
        ) async -> ContentRepairAcknowledgementResult
    private let confirmImplementation:
        @Sendable (FilesystemRepairAcknowledgementToken) async ->
            ContentRepairAcknowledgementConfirmationResult

    init(
        validateProjection:
            @escaping @Sendable (ContentRepairActivatedGeneration) async ->
            ContentRepairProjectionEligibilityResult,
        validateForwarding:
            @escaping @Sendable (ContentRepairAcceptedAcknowledgement) async ->
            ContentRepairForwardingEligibilityResult,
        acknowledge:
            @escaping @Sendable (
                RepairGenerationID,
                ContentRepairConsumerToken,
                ContentRepairConsumerDisposition
            ) async -> ContentRepairAcknowledgementResult,
        confirm:
            @escaping @Sendable (FilesystemRepairAcknowledgementToken) async ->
            ContentRepairAcknowledgementConfirmationResult
    ) {
        validateProjectionImplementation = validateProjection
        validateForwardingImplementation = validateForwarding
        acknowledgeImplementation = acknowledge
        confirmImplementation = confirm
    }

    init(registry: WorktreeContentRepairConsumerRegistry) {
        validateProjectionImplementation = { activatedGeneration in
            await registry.validateProjectionEligibility(activatedGeneration)
        }
        validateForwardingImplementation = { acknowledgement in
            await registry.validateAcknowledgementForwardingEligibility(acknowledgement)
        }
        acknowledgeImplementation = { repairGenerationID, consumer, disposition in
            await registry.acknowledge(
                repairGenerationID: repairGenerationID,
                consumer: consumer,
                disposition: disposition
            )
        }
        confirmImplementation = { token in
            await registry.confirmSourceGateAcknowledgement(token)
        }
    }

    func validateProjection(
        _ activatedGeneration: ContentRepairActivatedGeneration
    ) async -> ContentRepairProjectionEligibilityResult {
        await validateProjectionImplementation(activatedGeneration)
    }

    func validateForwarding(
        _ acknowledgement: ContentRepairAcceptedAcknowledgement
    ) async -> ContentRepairForwardingEligibilityResult {
        await validateForwardingImplementation(acknowledgement)
    }

    func acknowledge(
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken,
        disposition: ContentRepairConsumerDisposition
    ) async -> ContentRepairAcknowledgementResult {
        await acknowledgeImplementation(repairGenerationID, consumer, disposition)
    }

    func confirm(
        _ token: FilesystemRepairAcknowledgementToken
    ) async -> ContentRepairAcknowledgementConfirmationResult {
        await confirmImplementation(token)
    }
}

struct FilesystemContentRepairSourceGatePort: Sendable {
    private let acceptImplementation:
        @Sendable (FilesystemRepairAcknowledgementToken) async -> FilesystemSourceGateTransitionResult
    private let rejectImplementation:
        @Sendable (
            FilesystemRepairAcknowledgementToken,
            FilesystemRepairAcknowledgementFailure
        ) async -> FilesystemSourceGateTransitionResult

    init(
        accept:
            @escaping @Sendable (FilesystemRepairAcknowledgementToken) async ->
            FilesystemSourceGateTransitionResult,
        reject:
            @escaping @Sendable (
                FilesystemRepairAcknowledgementToken,
                FilesystemRepairAcknowledgementFailure
            ) async -> FilesystemSourceGateTransitionResult
    ) {
        acceptImplementation = accept
        rejectImplementation = reject
    }

    func accept(
        _ token: FilesystemRepairAcknowledgementToken
    ) async -> FilesystemSourceGateTransitionResult {
        await acceptImplementation(token)
    }

    func reject(
        _ token: FilesystemRepairAcknowledgementToken,
        failure: FilesystemRepairAcknowledgementFailure
    ) async -> FilesystemSourceGateTransitionResult {
        await rejectImplementation(token, failure)
    }
}

enum FilesystemContentRepairProjectionRejection: Equatable, Sendable {
    case sourceKindNotSupported(FilesystemSourceID)
    case acceptanceMismatch
    case projectorParticipantMismatch(
        expected: FilesystemRepairParticipantToken,
        actual: Set<FilesystemRepairParticipantToken>
    )
    case contentParticipantMismatch(
        expected: Set<FilesystemRepairParticipantToken>,
        actual: Set<FilesystemRepairParticipantToken>
    )
    case requestRepairGenerationMismatch(ContentRepairConsumerToken)
    case requestInvalidationGenerationMismatch(ContentRepairConsumerToken)
    case requestConsumerSourceMismatch(ContentRepairConsumerToken)
    case retryTokenMismatch(ContentRepairConsumerToken)
    case duplicateConsumerIdentity(ContentRepairConsumerToken)
    case duplicateRetryIdentity(ContentRepairRetryToken)
    case requestOrderMismatch
    case anotherGenerationActive(RepairGenerationID)
    case registryIneligible(ContentRepairProjectionIneligibility)
    case registryEligibilityMismatch(RepairGenerationID)
}

enum FilesystemContentRepairProjectionDebt: Equatable, Sendable {
    case consumerRetry(
        request: ContentRepairDeliveryRequest,
        reason: FilesystemContentRepairDeliveryRetryReason
    )
    case consumerRejected(
        request: ContentRepairDeliveryRequest,
        failure: FilesystemRepairAcknowledgementFailure,
        sourceGateResult: FilesystemSourceGateTransitionResult
    )
    case registryAcknowledgement(
        request: ContentRepairDeliveryRequest,
        result: ContentRepairAcknowledgementResult
    )
    case sourceGateAcknowledgement(
        ContentRepairAcceptedAcknowledgement,
        result: FilesystemSourceGateTransitionResult
    )
    case registryConfirmation(
        ContentRepairAcceptedAcknowledgement,
        result: ContentRepairAcknowledgementConfirmationResult
    )
    case projectorAcknowledgement(
        FilesystemRepairAcknowledgementToken,
        result: FilesystemSourceGateTransitionResult
    )
    case completionRetentionExhausted(FilesystemRepairAcknowledgementToken)
}

struct FilesystemContentRepairProjectionReceipt: Equatable, Sendable {
    let repairGenerationID: RepairGenerationID
    let invalidationGenerations: Set<ContentRepairInvalidationGeneration>
    let acknowledgedConsumers: Set<ContentRepairConsumerToken>
    let projectorAcknowledgement: FilesystemRepairAcknowledgementToken
}

enum FilesystemContentRepairProjectionResult: Equatable, Sendable {
    case completed(FilesystemContentRepairProjectionReceipt)
    case replayed(FilesystemContentRepairProjectionReceipt)
    case awaitingRetry(FilesystemContentRepairProjectionDebt)
    case alreadyProcessing(RepairGenerationID)
    case rejected(FilesystemContentRepairProjectionRejection)
    case shuttingDown
}

enum FilesystemRepairAcknowledgementForwardResult: Equatable, Sendable {
    case completed(ContentRepairAcceptedAcknowledgement)
    case replayed(ContentRepairAcceptedAcknowledgement)
    case awaitingSourceGate(
        ContentRepairAcceptedAcknowledgement,
        FilesystemSourceGateTransitionResult
    )
    case awaitingRegistryConfirmation(
        ContentRepairAcceptedAcknowledgement,
        ContentRepairAcknowledgementConfirmationResult
    )
    case completionRetentionExhausted(ContentRepairAcceptedAcknowledgement)
    case alreadyProcessing(FilesystemRepairAcknowledgementToken)
    case acknowledgementConflict(FilesystemRepairAcknowledgementToken)
    case registryIneligible(ContentRepairForwardingIneligibility)
    case registryEligibilityMismatch(FilesystemRepairAcknowledgementToken)
    case shuttingDown
}

struct FilesystemContentRepairSourceRetirementRequest: Equatable, Sendable {
    let registryReceipt: ContentRepairSourceRetirementReceipt
    let acceptance: FilesystemContentRepairAdmissionAcceptance
}

struct FilesystemContentRepairSourceRetirementDebt: Equatable, Sendable {
    let activeRepairGenerations: Set<RepairGenerationID>
    let outboundAcknowledgements: Set<FilesystemRepairAcknowledgementToken>

    var isEmpty: Bool {
        activeRepairGenerations.isEmpty && outboundAcknowledgements.isEmpty
    }
}

enum FilesystemContentRepairSourceRetirementRejection: Equatable, Sendable {
    case sourceMismatch(expected: FilesystemSourceID, actual: FilesystemSourceID)
    case acceptanceRegistrationMismatch(
        expected: FSEventRegistrationToken,
        actual: FSEventRegistrationToken
    )
    case acceptanceBindingMismatch(
        expected: FSEventRegistrationToken,
        actual: FSEventRegistrationToken
    )
    case currentRegistrationMismatch(
        expected: FSEventRegistrationToken,
        actual: FSEventRegistrationToken
    )
}

enum FilesystemContentRepairSourceRetirementResult: Equatable, Sendable {
    case retired(ContentRepairSourceRetirementReceipt)
    case alreadyRetired(FilesystemSourceID)
    case outstandingDebt(FilesystemContentRepairSourceRetirementDebt)
    case rejected(FilesystemContentRepairSourceRetirementRejection)
    case shuttingDown
}

enum FilesystemContentRepairProjectorLifecycle: Equatable, Sendable {
    case open
    case draining
    case shutdown
}

struct FilesystemContentRepairProjectorShutdownDebt: Equatable, Sendable {
    let activeRepairGenerations: Set<RepairGenerationID>
    let outboundAcknowledgements: Set<FilesystemRepairAcknowledgementToken>

    var isEmpty: Bool {
        activeRepairGenerations.isEmpty && outboundAcknowledgements.isEmpty
    }
}

enum FilesystemContentRepairProjectorShutdownResult: Equatable, Sendable {
    case awaitingDebt(FilesystemContentRepairProjectorShutdownDebt)
    case completed(FilesystemContentRepairProjectorShutdownDebt)
    case alreadyCompleted(FilesystemContentRepairProjectorShutdownDebt)
}
