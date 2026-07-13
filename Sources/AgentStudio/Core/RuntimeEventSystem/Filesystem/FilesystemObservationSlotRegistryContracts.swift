import Foundation

enum FilesystemObservationSlotConfigurationError: Error, Equatable {
    case nonPositiveMaximumSimultaneousSourceCount(Int)
    case negativeReplacementReserveSlotCount(Int)
    case physicalSlotCountOverflow
}

struct FilesystemObservationFleetMailboxIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationPhysicalSlotID: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSlotBindingIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationControlBlockIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSlotBinding: Hashable, Sendable {
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let physicalSlotID: FilesystemObservationPhysicalSlotID
    let identity: FilesystemObservationSlotBindingIdentity
    let registration: FSEventRegistrationToken
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity
}

struct FilesystemObservationDesiredIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSlotReservationIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationNativeGenerationIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemCanonicalResolvedRootIdentity: Hashable, Sendable {
    let path: String
}

struct FilesystemAuthorizationScopeIdentity: Hashable, Sendable {
    let value: UUID
}

enum FilesystemObservationEventCoverage: Hashable, Sendable {
    case recursiveFileEvents
}

struct FilesystemObservationSourceConfiguration: Hashable, Sendable {
    let registration: FSEventRegistrationToken
    let canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity
    let authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity
    let eventCoverage: FilesystemObservationEventCoverage

    var sourceID: FilesystemSourceID { registration.sourceID }
    var sourceKind: FilesystemSourceKind { registration.sourceID.kind }
}

struct FilesystemObservationDesiredRegistration: Hashable, Sendable {
    let identity: FilesystemObservationDesiredIdentity
    let registration: FSEventRegistrationToken

    var sourceID: FilesystemSourceID { registration.sourceID }

    init(
        identity: FilesystemObservationDesiredIdentity,
        registration: FSEventRegistrationToken
    ) {
        self.identity = identity
        self.registration = registration
    }
}

struct FilesystemObservationSlotReservation: Hashable, Sendable {
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let physicalSlotID: FilesystemObservationPhysicalSlotID
    let desiredIdentity: FilesystemObservationDesiredIdentity
    let identity: FilesystemObservationSlotReservationIdentity
}

struct FilesystemObservationDesiredSelection: Hashable, Sendable {
    let desiredRegistration: FilesystemObservationDesiredRegistration
    let reservation: FilesystemObservationSlotReservation
}

struct FilesystemObservationStartingNativeLifetime: Hashable, Sendable {
    let desiredRegistration: FilesystemObservationDesiredRegistration
    let consumedReservation: FilesystemObservationSlotReservation
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
}

// swiftlint:disable:next type_name
enum FilesystemObservationUnpublishedGenerationRetirementCause: Hashable, Sendable {
    case desiredWithdrawn
    case nativeCreateOrStartFailed(FilesystemObservationDesiredRegistration)
}

// swiftlint:disable:next type_name
struct FilesystemObservationRetiringUnpublishedNativeLifetime: Hashable, Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let cause: FilesystemObservationUnpublishedGenerationRetirementCause
}

// swiftlint:disable:next type_name
enum FilesystemObservationRetiringUnpublishedGenerationChain: Equatable, Sendable {
    // Fixed cardinality is intentional; Optional cannot encode the two-generation case.
    // swiftlint:disable:next discouraged_none_name
    case none
    case oldest(FilesystemObservationRetiringUnpublishedNativeLifetime)
    case oldestAndSuccessor(
        oldest: FilesystemObservationRetiringUnpublishedNativeLifetime,
        successor: FilesystemObservationRetiringUnpublishedNativeLifetime
    )
}

enum FilesystemObservationDesiredUpdateResult: Equatable, Sendable {
    case enqueued(FilesystemObservationDesiredRegistration)
    case replacedDeferred(
        FilesystemObservationDesiredRegistration,
        FilesystemObservationDesiredRegistration
    )
    case deferredToConfigurationCurrentness(FilesystemObservationDesiredRegistration)
}

enum FilesystemObservationDesiredSelectionResult: Equatable, Sendable {
    case selected(FilesystemObservationDesiredSelection)
    case noDeferredDesiredSource
    case deferredBehindActiveSourceCapacity
    case deferredBehindSlotCapacity
    case deferredBehindRetiringGenerationLimit(
        oldest: FilesystemObservationRetiringUnpublishedNativeLifetime,
        successor: FilesystemObservationRetiringUnpublishedNativeLifetime
    )
}

enum FilesystemObservationDesiredSlotState: Equatable, Sendable {
    case absent
    case deferred(FilesystemObservationDesiredRegistration)
    case selected(FilesystemObservationDesiredSelection)
    case starting(FilesystemObservationStartingNativeLifetime)
    case retiringUnpublishedGenerations(
        FilesystemObservationRetiringUnpublishedGenerationChain
    )
}

enum FilesystemObservationPendingConfigurationState: Equatable, Sendable {
    case absent
    case retained(FilesystemObservationDesiredRegistration)
}

enum FilesystemObservationDesiredWithdrawalResult: Equatable, Sendable {
    case withdrewDeferred(FilesystemObservationDesiredRegistration)
    case withdrewPendingConfiguration(FilesystemObservationDesiredRegistration)
    case releasedSelectedReservation(FilesystemObservationDesiredSelection)
    case retiringUnpublishedGeneration(FilesystemObservationRetiringUnpublishedNativeLifetime)
    case alreadyAbsent
    case staleDesiredIdentity(FilesystemObservationDesiredIdentity)
}

enum FilesystemObservationReservationReleaseResult: Equatable, Sendable {
    case releasedAndRotatedToDeferredTail(FilesystemObservationDesiredRegistration)
    case foreignFleet
    case reservationNoLongerCurrent
    case staleReservation(FilesystemObservationSlotReservation)
    case nativeLifetimeAlreadyCommitted(FilesystemObservationStartingNativeLifetime)
}

enum FilesystemObservationNativeLifetimeCommitResult: Equatable, Sendable {
    case committed(FilesystemObservationStartingNativeLifetime)
    case foreignFleet
    case undeclaredPhysicalSlot
    case reservationNoLongerCurrent
    case staleReservation(FilesystemObservationSlotReservation)
    case deferredToConfigurationCurrentness(FilesystemObservationDesiredRegistration)
    case alreadyCommitted(FilesystemObservationStartingNativeLifetime)
}

enum FilesystemObservationNativeLifetimeFailureResult: Equatable, Sendable {
    case retirementRequired(FilesystemObservationRetiringUnpublishedNativeLifetime)
    case alreadyRetirementRequired(FilesystemObservationRetiringUnpublishedNativeLifetime)
    case foreignFleet
    case undeclaredPhysicalSlot
    case nativeLifetimeNoLongerCurrent
    case staleStartingNativeLifetime(FilesystemObservationStartingNativeLifetime)
}

enum FilesystemObservationPhysicalSlotState: Equatable, Sendable {
    case undeclaredPhysicalSlot
    case vacant
    case selected(FilesystemObservationDesiredSelection)
    case starting(FilesystemObservationStartingNativeLifetime)
    case retiringUnpublishedGeneration(FilesystemObservationRetiringUnpublishedNativeLifetime)
}

enum FilesystemObservationStoredBindingCurrentness: Equatable, Sendable {
    case foreignFleet
    case undeclaredPhysicalSlot
    case vacant
    case reservedWithoutBinding
    case storedCurrent
    case storedSuperseded
}

enum FilesystemSourceConfigurationDeferralReason: Equatable, Sendable {
    case predecessorRetirement
    case replacementSlotCapacity
}

enum FilesystemSourceConfigurationFailureStage: Equatable, Sendable {
    case activeSourceCapacity
    case reserve
    case create
    case start
}

enum FilesystemSourceConfigurationDeferredDisposition: Equatable, Sendable {
    case retainingCurrent(
        existingConfiguration: FilesystemObservationSourceConfiguration,
        desiredConfiguration: FilesystemObservationSourceConfiguration,
        reason: FilesystemSourceConfigurationDeferralReason
    )
    case nonCurrent(
        desiredConfiguration: FilesystemObservationSourceConfiguration,
        reason: FilesystemSourceConfigurationDeferralReason
    )

    fileprivate var representedSourceIDs: Set<FilesystemSourceID> {
        switch self {
        case .retainingCurrent(let existingConfiguration, let desiredConfiguration, _):
            [existingConfiguration.sourceID, desiredConfiguration.sourceID]
        case .nonCurrent(let desiredConfiguration, _):
            [desiredConfiguration.sourceID]
        }
    }
}

enum FilesystemSourceConfigurationFailureDisposition: Equatable, Sendable {
    case retainingCurrent(
        existingConfiguration: FilesystemObservationSourceConfiguration,
        desiredConfiguration: FilesystemObservationSourceConfiguration,
        stage: FilesystemSourceConfigurationFailureStage
    )
    case nonCurrent(
        desiredConfiguration: FilesystemObservationSourceConfiguration,
        stage: FilesystemSourceConfigurationFailureStage
    )

    fileprivate var representedSourceIDs: Set<FilesystemSourceID> {
        switch self {
        case .retainingCurrent(let existingConfiguration, let desiredConfiguration, _):
            [existingConfiguration.sourceID, desiredConfiguration.sourceID]
        case .nonCurrent(let desiredConfiguration, _):
            [desiredConfiguration.sourceID]
        }
    }
}

enum FilesystemSourceConfigurationDisposition: Equatable, Sendable {
    case installed(FilesystemObservationSourceConfiguration)
    case unchanged(FilesystemObservationSourceConfiguration)
    case removalComplete
    case deferred(FilesystemSourceConfigurationDeferredDisposition)
    case failed(FilesystemSourceConfigurationFailureDisposition)

    fileprivate var representedSourceIDs: Set<FilesystemSourceID> {
        switch self {
        case .installed(let configuration), .unchanged(let configuration):
            [configuration.sourceID]
        case .removalComplete:
            []
        case .deferred(let disposition):
            disposition.representedSourceIDs
        case .failed(let disposition):
            disposition.representedSourceIDs
        }
    }

    fileprivate var requiresRetryWhileNonCurrent: Bool {
        switch self {
        case .deferred(.nonCurrent), .failed(.nonCurrent):
            true
        case .installed, .unchanged, .removalComplete,
            .deferred(.retainingCurrent), .failed(.retainingCurrent):
            false
        }
    }
}

enum FilesystemSourceConfigurationCurrentness: Equatable, Sendable {
    case current
    case nonCurrent(retrySources: Set<FilesystemSourceID>)
}

struct FilesystemConfigurationSourceMismatch: Equatable, Hashable, Sendable {
    let receiptSourceID: FilesystemSourceID
    let dispositionSourceID: FilesystemSourceID
}

enum FilesystemConfigurationReceiptError: Error, Equatable, Sendable {
    case dispositionCoverageMismatch(
        missing: Set<FilesystemSourceID>,
        unexpected: Set<FilesystemSourceID>
    )
    case dispositionSourceMismatches(
        Set<FilesystemConfigurationSourceMismatch>
    )
}

struct FilesystemSourceConfigurationReceipt: Equatable, Sendable {
    let acceptedTopologyRevision: UInt64
    let dispositions: [FilesystemSourceID: FilesystemSourceConfigurationDisposition]

    var currentness: FilesystemSourceConfigurationCurrentness {
        var retrySources: Set<FilesystemSourceID> = []
        for (sourceID, disposition) in dispositions
        where disposition.requiresRetryWhileNonCurrent {
            retrySources.insert(sourceID)
        }
        return retrySources.isEmpty ? .current : .nonCurrent(retrySources: retrySources)
    }

    init(
        acceptedTopologyRevision: UInt64,
        requestedSourceIDs: Set<FilesystemSourceID>,
        dispositions: [FilesystemSourceID: FilesystemSourceConfigurationDisposition]
    ) throws {
        let dispositionSourceIDs = Set(dispositions.keys)
        let missingSourceIDs = requestedSourceIDs.subtracting(dispositionSourceIDs)
        let unexpectedSourceIDs = dispositionSourceIDs.subtracting(requestedSourceIDs)
        guard missingSourceIDs.isEmpty, unexpectedSourceIDs.isEmpty else {
            throw FilesystemConfigurationReceiptError.dispositionCoverageMismatch(
                missing: missingSourceIDs,
                unexpected: unexpectedSourceIDs
            )
        }

        var sourceMismatches: Set<FilesystemConfigurationSourceMismatch> = []
        for (receiptSourceID, disposition) in dispositions {
            for dispositionSourceID in disposition.representedSourceIDs
            where dispositionSourceID != receiptSourceID {
                sourceMismatches.insert(
                    FilesystemConfigurationSourceMismatch(
                        receiptSourceID: receiptSourceID,
                        dispositionSourceID: dispositionSourceID
                    )
                )
            }
        }
        guard sourceMismatches.isEmpty else {
            throw FilesystemConfigurationReceiptError.dispositionSourceMismatches(
                sourceMismatches
            )
        }

        self.acceptedTopologyRevision = acceptedTopologyRevision
        self.dispositions = dispositions
    }
}
