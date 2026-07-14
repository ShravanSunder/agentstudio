import Foundation

struct ContentRepairConsumerIdentity: Hashable, Sendable {
    private let value: UUID
    var isUUIDv7: Bool { UUIDv7.isV7(value) }
    var participantID: UUID { value }

    private init(value: UUID) { self.value = value }

    static func generate() -> Self {
        Self(value: UUIDv7.generate())
    }
}

struct ContentRepairCaptureIdentity: Hashable, Sendable {
    private let value: UUID
    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    private init(value: UUID) { self.value = value }

    static func generate() -> Self {
        Self(value: UUIDv7.generate())
    }
}

struct ContentRepairRetryIdentity: Hashable, Sendable {
    private let value: UUID
    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    private init(value: UUID) { self.value = value }

    static func generate() -> Self {
        Self(value: UUIDv7.generate())
    }
}

struct ContentRepairConsumerToken: Hashable, Sendable {
    let sourceID: FilesystemSourceID
    let identity: ContentRepairConsumerIdentity
    let generation: UInt64
    let registrationOrdinal: UInt64

    private init(
        sourceID: FilesystemSourceID,
        identity: ContentRepairConsumerIdentity,
        generation: UInt64,
        registrationOrdinal: UInt64
    ) {
        self.sourceID = sourceID
        self.identity = identity
        self.generation = generation
        self.registrationOrdinal = registrationOrdinal
    }

    static func registered(
        sourceID: FilesystemSourceID,
        registrationOrdinal: UInt64,
        generation: UInt64 = 0
    ) -> Self {
        Self(
            sourceID: sourceID,
            identity: .generate(),
            generation: generation,
            registrationOrdinal: registrationOrdinal
        )
    }

    func replacement() -> Self? {
        guard let replacementGeneration = ContentRepairGenerationArithmetic.successor(of: generation) else {
            return nil
        }
        return Self(
            sourceID: sourceID,
            identity: identity,
            generation: replacementGeneration,
            registrationOrdinal: registrationOrdinal
        )
    }

    var sourceGateParticipant: FilesystemRepairParticipantToken {
        FilesystemRepairParticipantToken(
            kind: .contentConsumer,
            participantID: identity.participantID,
            participantGeneration: generation
        )
    }
}

struct ContentRepairInvalidationGeneration: Hashable, Sendable {
    let value: UInt64
}

struct ContentRepairRetryToken: Hashable, Sendable {
    let identity: ContentRepairRetryIdentity
    let repairGenerationID: RepairGenerationID
    let consumer: ContentRepairConsumerToken

    private init(
        identity: ContentRepairRetryIdentity,
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken
    ) {
        self.identity = identity
        self.repairGenerationID = repairGenerationID
        self.consumer = consumer
    }

    static func generate(
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken
    ) -> Self {
        Self(
            identity: .generate(),
            repairGenerationID: repairGenerationID,
            consumer: consumer
        )
    }
}

enum ContentRepairCaptureEligibility: Equatable, Sendable {
    case eligible
    case ineligibleNoRetainedContent
}

enum ContentRepairCurrentRevision: Equatable, Sendable {
    case baseline(FSEventRegistrationToken)
    case rebuilt(repairGenerationID: RepairGenerationID, consumerRevision: UInt64)
}

enum ContentRepairNonCurrentRevision: Equatable, Sendable {
    case capturePending(
        identity: ContentRepairCaptureIdentity,
        invalidationGeneration: ContentRepairInvalidationGeneration
    )
    case repairPending(ContentRepairRetryToken)
    case retryRetained(ContentRepairRetryToken)
    case noRetainedContent(ContentRepairInvalidationGeneration)
}

enum ContentRepairConsumerCurrentness: Equatable, Sendable {
    case current(ContentRepairCurrentRevision)
    case nonCurrent(ContentRepairNonCurrentRevision)
}

struct ContentRepairConsumerRegistration: Equatable, Sendable {
    let token: ContentRepairConsumerToken
    let eligibility: ContentRepairCaptureEligibility
    let currentness: ContentRepairConsumerCurrentness
}

enum ContentRepairConsumerRegistrationResult: Equatable, Sendable {
    case registered(ContentRepairConsumerRegistration)
    case sourceKindNotSupported(FilesystemSourceID)
    case registrationConflict(expected: FSEventRegistrationToken, requested: FSEventRegistrationToken)
    case generationExhausted
    case shuttingDown
}

enum ContentRepairEligibilityUpdateResult: Equatable, Sendable {
    case applied(ContentRepairConsumerRegistration)
    case alreadyApplied(ContentRepairConsumerRegistration)
    case staleToken
    case foreignSource
    case shuttingDown
}

struct ContentRepairPreparedCapture: Equatable, Sendable {
    let identity: ContentRepairCaptureIdentity
    let invalidationGeneration: ContentRepairInvalidationGeneration
    let registration: FSEventRegistrationToken
    let consumers: Set<ContentRepairConsumerToken>

    var sourceGateParticipants: Set<FilesystemRepairParticipantToken> {
        Set(consumers.map(\.sourceGateParticipant))
    }
}

enum ContentRepairCapturePreparationResult: Equatable, Sendable {
    case prepared(ContentRepairPreparedCapture)
    case replayed(ContentRepairPreparedCapture)
    case sourceKindNotSupported(FilesystemSourceID)
    case registrationConflict(expected: FSEventRegistrationToken, requested: FSEventRegistrationToken)
    case captureIdentityConflict(ContentRepairCaptureIdentity)
    case generationExhausted
    case shuttingDown
}

enum ContentRepairCaptureAbortResult: Equatable, Sendable {
    case aborted(ContentRepairPreparedCapture)
    case alreadyAborted(ContentRepairCaptureIdentity)
    case staleCapture
    case foreignSource
    case alreadyBound(RepairGenerationID)
}

struct ContentRepairDeliveryRequest: Equatable, Sendable {
    let repairGeneration: RepairGeneration
    let invalidationGeneration: ContentRepairInvalidationGeneration
    let consumer: ContentRepairConsumerToken
    let retryToken: ContentRepairRetryToken
}

struct ContentRepairBoundGeneration: Equatable, Sendable {
    let repairGeneration: RepairGeneration
    let deliveryRequests: [ContentRepairDeliveryRequest]
}

enum ContentRepairCaptureBindingResult: Equatable, Sendable {
    case boundActive(ContentRepairActivatedGeneration)
    case boundPending(ContentRepairBoundGeneration)
    case replayedActive(ContentRepairActivatedGeneration)
    case replayedPending(ContentRepairBoundGeneration)
    case replayedCompleted(ContentRepairBoundGeneration)
    case staleCapture
    case foreignSource
    case registrationMismatch(expected: FSEventRegistrationToken, actual: FSEventRegistrationToken)
    case participantMismatch(
        expected: Set<FilesystemRepairParticipantToken>,
        actual: Set<FilesystemRepairParticipantToken>
    )
    case captureAborted
    case captureSuperseded
    case shuttingDown
}

enum ContentRepairBoundGenerationActivationResult: Equatable, Sendable {
    case activated(ContentRepairActivatedGeneration)
    case alreadyActive(ContentRepairActivatedGeneration)
    case staleGeneration
    case foreignSource
    case shuttingDown
}

enum ContentRepairProjectionEligibility: Equatable, Sendable {
    case currentActive(ContentRepairActivatedGeneration)
    case retainedCompleted(ContentRepairActivatedGeneration)
}

enum ContentRepairProjectionIneligibility: Equatable, Sendable {
    case pendingGeneration(RepairGenerationID)
    case supersededGeneration(RepairGenerationID)
    case staleGeneration(RepairGenerationID)
    case activationMismatch(RepairGenerationID)
    case foreignSource(FilesystemSourceID)
    case sourceKindNotSupported(FilesystemSourceID)
}

enum ContentRepairProjectionEligibilityResult: Equatable, Sendable {
    case eligible(ContentRepairProjectionEligibility)
    case ineligible(ContentRepairProjectionIneligibility)
    case shuttingDown
}

enum ContentRepairConsumerDisposition: Equatable, Sendable {
    case rebuiltCurrent(consumerRevision: UInt64)
    case markedNonCurrent(retry: ContentRepairRetryToken)
    case notApplicableNoRetainedState
}

enum ContentRepairRecordedDisposition: Equatable, Sendable {
    case rebuiltCurrent(consumerRevision: UInt64)
    case markedNonCurrent(retry: ContentRepairRetryToken)
    case notApplicableNoRetainedState
    case withdrawnNoRetainedState
    case transferredToReplacement(ContentRepairConsumerToken)
}

struct ContentRepairAcceptedAcknowledgement: Equatable, Sendable {
    let sourceGateAcknowledgement: FilesystemRepairAcknowledgementToken
    let disposition: ContentRepairRecordedDisposition
}

enum ContentRepairAcknowledgementDebt: Equatable, Sendable {
    case staleRepairGeneration
    case staleConsumerToken
    case foreignSource
    case retryTokenMismatch
    case repairNotBound
}

enum ContentRepairAcknowledgementResult: Equatable, Sendable {
    case accepted(ContentRepairAcceptedAcknowledgement)
    case replayed(ContentRepairAcceptedAcknowledgement)
    case debtRetained(ContentRepairAcknowledgementDebt)
    case shuttingDown
}

enum ContentRepairAcknowledgementConfirmationResult: Equatable, Sendable {
    case confirmed(ContentRepairAcceptedAcknowledgement)
    case replayed(ContentRepairAcceptedAcknowledgement)
    case staleAcknowledgement
    case retentionExhausted
    case shuttingDown
}

enum ContentRepairAcknowledgementForwardingEligibility: Equatable, Sendable {
    case pendingExact(ContentRepairAcceptedAcknowledgement)
    case confirmedExact(ContentRepairAcceptedAcknowledgement)
}

enum ContentRepairForwardingIneligibility: Equatable, Sendable {
    case acknowledgementMismatch(FilesystemRepairAcknowledgementToken)
    case staleAcknowledgement(FilesystemRepairAcknowledgementToken)
    case foreignOrRetiredSource(FilesystemSourceID)
    case sourceKindNotSupported(FilesystemSourceID)
}

enum ContentRepairForwardingEligibilityResult: Equatable, Sendable {
    case eligible(ContentRepairAcknowledgementForwardingEligibility)
    case ineligible(ContentRepairForwardingIneligibility)
    case shuttingDown
}

enum ContentRepairWithdrawalDisposition: Equatable, Sendable {
    case noRetainedState
}

enum ContentRepairWithdrawalResult: Equatable, Sendable {
    case withdrawn
    case withdrawnAndAcknowledged(ContentRepairAcceptedAcknowledgement)
    case staleToken
    case foreignSource
    case captureInProgress(ContentRepairCaptureIdentity)
    case retainedRetryRequiresTransfer(ContentRepairRetryToken)
    case shuttingDown
}

enum ContentRepairReplacementRepairDisposition: Equatable, Sendable {
    case notCaptured
    case transferred(ContentRepairAcceptedAcknowledgement)
}

struct ContentRepairConsumerReplacement: Equatable, Sendable {
    let registration: ContentRepairConsumerRegistration
    let repairDisposition: ContentRepairReplacementRepairDisposition
}

enum ContentRepairConsumerReplacementResult: Equatable, Sendable {
    case replaced(ContentRepairConsumerReplacement)
    case staleToken
    case foreignSource
    case captureInProgress(ContentRepairCaptureIdentity)
    case generationExhausted
    case shuttingDown
}

enum ContentRepairRetryCompletionResult: Equatable, Sendable {
    case completed(ContentRepairConsumerRegistration)
    case replayed(ContentRepairConsumerRegistration)
    case staleRetry
    case staleConsumerToken
    case foreignSource
    case shuttingDown
}

enum ContentRepairConsumerLookupResult: Equatable, Sendable {
    case registered(ContentRepairConsumerRegistration)
    case staleToken
    case foreignSource
}

enum ContentRepairGenerationArithmetic {
    static func successor(of generation: UInt64) -> UInt64? {
        let (successor, overflow) = generation.addingReportingOverflow(1)
        return overflow ? nil : successor
    }
}

enum WorktreeContentRepairConsumerRegistryLifecycle: Equatable, Sendable {
    case open
    case draining
    case shutdown
}

struct WorktreeContentRepairConsumerRegistryShutdownDebt: Equatable, Sendable {
    let preparedCaptures: Set<ContentRepairCaptureIdentity>
    let activeRepairGenerations: Set<RepairGenerationID>
    let pendingRepairGenerations: Set<RepairGenerationID>
    let retainedRetries: Set<ContentRepairRetryToken>
    let outboundAcknowledgements: Set<FilesystemRepairAcknowledgementToken>

    var isEmpty: Bool {
        preparedCaptures.isEmpty && activeRepairGenerations.isEmpty
            && pendingRepairGenerations.isEmpty && retainedRetries.isEmpty
            && outboundAcknowledgements.isEmpty
    }
}

struct ContentRepairSourceRetirementDebt: Equatable, Sendable {
    let preparedCaptures: Set<ContentRepairCaptureIdentity>
    let activeRepairGenerations: Set<RepairGenerationID>
    let pendingRepairGenerations: Set<RepairGenerationID>
    let retainedRetries: Set<ContentRepairRetryToken>
    let outboundAcknowledgements: Set<FilesystemRepairAcknowledgementToken>

    var isEmpty: Bool {
        preparedCaptures.isEmpty && activeRepairGenerations.isEmpty
            && pendingRepairGenerations.isEmpty && retainedRetries.isEmpty
            && outboundAcknowledgements.isEmpty
    }
}

enum ContentRepairSourceRetirementResult: Equatable, Sendable {
    case retired(ContentRepairSourceRetirementReceipt)
    case alreadyRetired(FilesystemSourceID)
    case outstandingDebt(ContentRepairSourceRetirementDebt)
    case sourceKindNotSupported(FilesystemSourceID)
    case shuttingDown
}

enum ContentRepairConsumerRegistryShutdownResult: Equatable, Sendable {
    case awaitingDebt(WorktreeContentRepairConsumerRegistryShutdownDebt)
    case completed(WorktreeContentRepairConsumerRegistryShutdownDebt)
    case alreadyCompleted(WorktreeContentRepairConsumerRegistryShutdownDebt)
}
