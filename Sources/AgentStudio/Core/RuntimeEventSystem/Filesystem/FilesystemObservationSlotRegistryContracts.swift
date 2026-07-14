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

struct FilesystemContinuityRepairHandoffIdentity: Hashable, Sendable {
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

indirect enum FilesystemObservationDesiredAdmission: Hashable, Sendable {
    case installation
    case replacementRetainingPredecessor(FilesystemObservationAcceptingNativeLifetime)
    case replacementAfterPredecessorClose(FilesystemObservationSlotBinding)
}

struct FilesystemObservationDesiredRegistration: Hashable, Sendable {
    let identity: FilesystemObservationDesiredIdentity
    let acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision
    let configuration: FilesystemObservationSourceConfiguration
    let admission: FilesystemObservationDesiredAdmission

    var registration: FSEventRegistrationToken { configuration.registration }
    var sourceID: FilesystemSourceID { configuration.sourceID }

    init(
        identity: FilesystemObservationDesiredIdentity,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision,
        configuration: FilesystemObservationSourceConfiguration,
        admission: FilesystemObservationDesiredAdmission
    ) {
        self.identity = identity
        self.acceptedTopologyRevision = acceptedTopologyRevision
        self.configuration = configuration
        self.admission = admission
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

enum FilesystemObservationReplacementAdmissionRejection: Equatable, Sendable {
    case sourceMismatch(
        exactPriorSourceID: FilesystemSourceID,
        desiredSourceID: FilesystemSourceID
    )
    case priorBindingNotCurrent(FilesystemObservationStoredBindingCurrentness)
    case priorBindingNotAccepting(FilesystemObservationPhysicalSlotState)
    case canonicalResolvedRootMismatch
    case authorizationScopeMismatch
    case eventCoverageMismatch
    case priorContinuityDiscontinuous(FixedFilesystemRecoveryEvidenceSnapshot)
    case authorityBindingMismatch
    case priorContinuityForeignFleet
    case priorContinuityUndeclaredPhysicalSlot
    case priorContinuityUnboundPhysicalSlot
    case priorContinuityCurrentBindingMismatch(FilesystemObservationSlotBinding)
}

enum FilesystemObservationReplacementAdmissionResult: Equatable, Sendable {
    case admitted(FilesystemObservationDesiredUpdateResult)
    case rejected(FilesystemObservationReplacementAdmissionRejection)
}

struct FilesystemObservationStartingNativeLifetime: Hashable, Sendable {
    let desiredRegistration: FilesystemObservationDesiredRegistration
    let consumedReservation: FilesystemObservationSlotReservation
    let binding: FilesystemObservationSlotBinding
    let nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity
}

struct FilesystemObservationCallbackAdmissionPortIdentity: Equatable, Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationAcceptingNativeLifetime: Hashable, Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity

    var binding: FilesystemObservationSlotBinding {
        startingNativeLifetime.binding
    }
}

// swiftlint:disable:next type_name
struct FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime: Equatable, Sendable {
    let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime

    var binding: FilesystemObservationSlotBinding {
        acceptingNativeLifetime.binding
    }

    func matches(_ receipt: DarwinFSEventRegistrationLeaseDrainReceipt) -> Bool {
        let startingNativeLifetime = acceptingNativeLifetime.startingNativeLifetime
        return receipt.binding == startingNativeLifetime.binding
            && receipt.nativeGenerationIdentity == startingNativeLifetime.nativeGenerationIdentity
            && receipt.controlBlockIdentity == startingNativeLifetime.binding.controlBlockIdentity
    }
}

struct FilesystemObservationRetirementFenceIdentity: Equatable, Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSlotRetirementFence: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let identity: FilesystemObservationRetirementFenceIdentity
}

struct FilesystemClosingAwaitingPredecessorLifetime: Equatable, Sendable {
    let closingNativeLifetime: FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime
    let leaseDrainReceipt: DarwinFSEventRegistrationLeaseDrainReceipt

    var binding: FilesystemObservationSlotBinding { closingNativeLifetime.binding }
    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
    }
}

struct FilesystemRetirementFencePendingLifetime: Equatable, Sendable {
    let closingNativeLifetime: FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime
    let leaseDrainReceipt: DarwinFSEventRegistrationLeaseDrainReceipt
    let fence: FilesystemObservationSlotRetirementFence

    var binding: FilesystemObservationSlotBinding { closingNativeLifetime.binding }
    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
    }
}

struct FilesystemRetirementFenceInstalledLifetime: Equatable, Sendable {
    let pendingLifetime: FilesystemRetirementFencePendingLifetime
    let contributionIdentity: FilesystemObservationContributionIdentity

    var binding: FilesystemObservationSlotBinding { pendingLifetime.binding }
    var fence: FilesystemObservationSlotRetirementFence { pendingLifetime.fence }
    var identity: FilesystemObservationRetirementFenceIdentity { fence.identity }
    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        pendingLifetime.startingNativeLifetime
    }
}

struct FilesystemRetirementFenceTransferredLifetime: Equatable, Sendable {
    let installedLifetime: FilesystemRetirementFenceInstalledLifetime
    let retirementAuthority: FilesystemObservationSlotRetirementAuthority

    var binding: FilesystemObservationSlotBinding { installedLifetime.binding }
    var fence: FilesystemObservationSlotRetirementFence { installedLifetime.fence }
    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        installedLifetime.startingNativeLifetime
    }
}

enum FilesystemObservationSlotRetirementDisposition: Equatable, Sendable {
    case quiescentWithoutRecovery
    case quiescentAfterRecovery(FixedFilesystemRecoveryEvidenceRevision)
}

struct FilesystemObservationSlotRetirementReceipt: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let fenceIdentity: FilesystemObservationRetirementFenceIdentity
    let disposition: FilesystemObservationSlotRetirementDisposition
    let retirementAuthority: FilesystemObservationSlotRetirementAuthority
}

struct FilesystemFenceBackedRetiredContextReleaseLifetime: Equatable, Sendable {
    let transferredLifetime: FilesystemRetirementFenceTransferredLifetime
    let receipt: FilesystemObservationSlotRetirementReceipt

    var binding: FilesystemObservationSlotBinding { transferredLifetime.binding }
    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        transferredLifetime.startingNativeLifetime
    }
}

struct FilesystemUnpublishedRetiredContextReleaseLifetime: Equatable, Sendable {
    let receipt: FilesystemObservationUnpublishedFinalReceipt

    var binding: FilesystemObservationSlotBinding { receipt.binding }
    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        receipt.startingNativeLifetime
    }
}

enum FilesystemRetiredContextReleaseLifetime: Equatable, Sendable {
    case fenceBacked(FilesystemFenceBackedRetiredContextReleaseLifetime)
    case unpublished(FilesystemUnpublishedRetiredContextReleaseLifetime)

    var binding: FilesystemObservationSlotBinding {
        switch self {
        case .fenceBacked(let lifetime): lifetime.binding
        case .unpublished(let lifetime): lifetime.binding
        }
    }

    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        switch self {
        case .fenceBacked(let lifetime): lifetime.startingNativeLifetime
        case .unpublished(let lifetime): lifetime.startingNativeLifetime
        }
    }

    var permit: FilesystemObservationNativeRetirementPermit {
        switch self {
        case .fenceBacked(let lifetime): .fenceBacked(lifetime.receipt)
        case .unpublished(let lifetime): .unpublished(lifetime.receipt)
        }
    }

}

enum FilesystemObservationRetirementFenceTransferResult: Equatable, Sendable {
    case transferred(FilesystemRetirementFenceTransferredLifetime)
    case alreadyTransferred(FilesystemRetirementFenceTransferredLifetime)
    case alreadyRetired(FilesystemRetiredContextReleaseLifetime)
    case authorityMismatch
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

enum FilesystemObservationRetirementCompletionResult: Equatable, Sendable {
    case retired(FilesystemObservationSlotRetirementReceipt)
    case alreadyRetired(FilesystemObservationSlotRetirementReceipt)
    case authorityMismatch
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

enum FilesystemRetirementFencePreparationResult: Equatable, Sendable {
    case awaitingPredecessor(FilesystemClosingAwaitingPredecessorLifetime)
    case pending(FilesystemRetirementFencePendingLifetime)
    case alreadyAwaitingPredecessor(FilesystemClosingAwaitingPredecessorLifetime)
    case alreadyPending(FilesystemRetirementFencePendingLifetime)
    case alreadyInstalled(FilesystemRetirementFenceInstalledLifetime)
    case alreadyRetired(FilesystemObservationSlotRetirementReceipt)
    case foreignFleet
    case undeclaredPhysicalSlot
    case receiptMismatch
    case retiringGenerationLimitReached
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

enum FilesystemRetirementFenceInstallationResult: Equatable, Sendable {
    case installed(FilesystemRetirementFenceInstalledLifetime)
    case alreadyInstalled(FilesystemRetirementFenceInstalledLifetime)
    case stalePendingLifetime
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
}

enum FilesystemObservationPendingRetirementFenceLookup: Equatable, Sendable {
    case pending(FilesystemRetirementFencePendingLifetime)
    case notPending(FilesystemObservationPhysicalSlotState)
}

enum FilesystemObservationRetirementFenceRequestResult: Equatable, Sendable {
    case awaitingPredecessor(FilesystemClosingAwaitingPredecessorLifetime)
    case pending(FilesystemRetirementFencePendingLifetime)
    case pendingAwaitingCleanup(FilesystemRetirementFencePendingLifetime)
    case pendingAfterContraction(
        FilesystemRetirementFencePendingLifetime,
        FixedFilesystemRecoveryEvidenceSnapshot
    )
    case installed(FilesystemRetirementFenceInstalledLifetime)
    case alreadyAwaitingPredecessor(FilesystemClosingAwaitingPredecessorLifetime)
    case alreadyPending(FilesystemRetirementFencePendingLifetime)
    case alreadyInstalled(FilesystemRetirementFenceInstalledLifetime)
    case retired(FilesystemObservationSlotRetirementReceipt)
    case foreignFleet
    case undeclaredPhysicalSlot
    case receiptMismatch
    case retiringGenerationLimitReached
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
    case closed
}

enum FilesystemObservationPostStartDisposition: Equatable, Sendable {
    case current
    case closePredecessor(FilesystemObservationAcceptingNativeLifetime)
    case closePublished(FilesystemObservationAcceptingNativeLifetime)
    case closePredecessorAndPublished(
        predecessor: FilesystemObservationAcceptingNativeLifetime,
        published: FilesystemObservationAcceptingNativeLifetime
    )
}

struct FilesystemObservationPostStartPublication: Equatable, Sendable {
    let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
    let disposition: FilesystemObservationPostStartDisposition
}

struct FilesystemAwaitingAcceptingPublicationLifetime: Equatable, Sendable {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
}

enum FilesystemObservationAcceptingPublicationResult: Equatable, Sendable {
    case published(FilesystemObservationPostStartPublication)
    case alreadyPublished(FilesystemObservationPostStartPublication)
    case foreignFleet
    case undeclaredPhysicalSlot
    case startingNativeLifetimeMismatch(FilesystemObservationStartingNativeLifetime)
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
    case mailboxReleased
}

// swiftlint:disable:next type_name
enum FilesystemObservationCallbackLeaseDrainClosingResult: Equatable, Sendable {
    case transitioned(FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime)
    case alreadyTransitioned(FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime)
    case foreignFleet
    case undeclaredPhysicalSlot
    case acceptingNativeLifetimeMismatch(FilesystemObservationAcceptingNativeLifetime)
    case invalidSlotState(FilesystemObservationPhysicalSlotState)
    case mailboxReleased
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

enum FilesystemObservationRetiringNativeLifetime: Equatable, Sendable {
    case unpublished(FilesystemObservationRetiringUnpublishedNativeLifetime)
    case closingAwaitingPredecessor(FilesystemClosingAwaitingPredecessorLifetime)
    case retirementFencePending(FilesystemRetirementFencePendingLifetime)
    case retirementFenceInstalled(FilesystemRetirementFenceInstalledLifetime)
    case retirementFenceTransferredAwaitingCleanup(FilesystemRetirementFenceTransferredLifetime)
    case retiredAwaitingContextRelease(
        FilesystemRetiredContextReleaseLifetime
    )

    var sourceID: FilesystemSourceID {
        switch self {
        case .unpublished(let lifetime):
            lifetime.startingNativeLifetime.desiredRegistration.sourceID
        case .closingAwaitingPredecessor(let lifetime):
            lifetime.binding.registration.sourceID
        case .retirementFencePending(let lifetime):
            lifetime.binding.registration.sourceID
        case .retirementFenceInstalled(let lifetime):
            lifetime.binding.registration.sourceID
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            lifetime.binding.registration.sourceID
        case .retiredAwaitingContextRelease(let lifetime):
            lifetime.binding.registration.sourceID
        }
    }

    var startingNativeLifetime: FilesystemObservationStartingNativeLifetime {
        switch self {
        case .unpublished(let lifetime):
            lifetime.startingNativeLifetime
        case .closingAwaitingPredecessor(let lifetime):
            lifetime.closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
        case .retirementFencePending(let lifetime):
            lifetime.closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
        case .retirementFenceInstalled(let lifetime):
            lifetime.pendingLifetime.closingNativeLifetime.acceptingNativeLifetime
                .startingNativeLifetime
        case .retirementFenceTransferredAwaitingCleanup(let lifetime):
            lifetime.startingNativeLifetime
        case .retiredAwaitingContextRelease(let lifetime):
            lifetime.startingNativeLifetime
        }
    }
}

enum FilesystemObservationRetiringGenerationChain: Equatable, Sendable {
    // Fixed cardinality is intentional; Optional cannot encode the two-generation case.
    // swiftlint:disable:next discouraged_none_name
    case none
    case oldest(FilesystemObservationRetiringNativeLifetime)
    case oldestAndSuccessor(
        oldest: FilesystemObservationRetiringNativeLifetime,
        successor: FilesystemObservationRetiringNativeLifetime
    )

    func replacing(
        _ currentLifetime: FilesystemObservationRetiringNativeLifetime,
        with replacementLifetime: FilesystemObservationRetiringNativeLifetime
    ) -> FilesystemRetiringChainReplacement {
        switch self {
        case .none:
            return .currentLifetimeMismatch
        case .oldest(let oldest):
            guard oldest == currentLifetime else {
                return .currentLifetimeMismatch
            }
            return .replaced(.oldest(replacementLifetime))
        case .oldestAndSuccessor(let oldest, let successor):
            if oldest == currentLifetime {
                return .replaced(
                    .oldestAndSuccessor(
                        oldest: replacementLifetime,
                        successor: successor
                    )
                )
            }
            guard successor == currentLifetime else {
                return .currentLifetimeMismatch
            }
            return .replaced(
                .oldestAndSuccessor(
                    oldest: oldest,
                    successor: replacementLifetime
                )
            )
        }
    }
}

enum FilesystemRetiringChainReplacement: Equatable, Sendable {
    case replaced(FilesystemObservationRetiringGenerationChain)
    case currentLifetimeMismatch
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
        oldest: FilesystemObservationRetiringNativeLifetime,
        successor: FilesystemObservationRetiringNativeLifetime
    )
}

enum FilesystemObservationDesiredSlotState: Equatable, Sendable {
    case absent
    case deferred(FilesystemObservationDesiredRegistration)
    case selected(FilesystemObservationDesiredSelection)
    case starting(FilesystemObservationStartingNativeLifetime)
    case accepting(FilesystemObservationAcceptingNativeLifetime)
    case closingAwaitingCallbackLeaseDrain(
        FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime
    )
    case retiringGenerations(
        FilesystemObservationRetiringGenerationChain
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
    case awaitingAcceptingPublication(
        FilesystemAwaitingAcceptingPublicationLifetime
    )
    case closeAccepting(FilesystemObservationAcceptingNativeLifetime)
    case retiringGeneration(FilesystemObservationRetiringNativeLifetime)
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
    case accepting(FilesystemObservationAcceptingNativeLifetime)
    case closingAwaitingCallbackLeaseDrain(
        FilesystemObservationClosingAwaitingCallbackLeaseDrainLifetime
    )
    case closingAwaitingPredecessor(
        FilesystemClosingAwaitingPredecessorLifetime
    )
    case retirementFencePending(FilesystemRetirementFencePendingLifetime)
    case retirementFenceInstalled(FilesystemRetirementFenceInstalledLifetime)
    case retirementFenceTransferredAwaitingCleanup(FilesystemRetirementFenceTransferredLifetime)
    case retiredAwaitingContextRelease(
        FilesystemRetiredContextReleaseLifetime
    )
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
    case installedAwaitingContinuityRepair(
        desiredConfiguration: FilesystemObservationSourceConfiguration,
        handoffAuthority: FilesystemContinuityRepairHandoffAuthority
    )
    case unchanged(FilesystemObservationSourceConfiguration)
    case removalComplete
    case deferred(FilesystemSourceConfigurationDeferredDisposition)
    case failed(FilesystemSourceConfigurationFailureDisposition)

    fileprivate var representedSourceIDs: Set<FilesystemSourceID> {
        switch self {
        case .installed(let configuration), .unchanged(let configuration),
            .installedAwaitingContinuityRepair(let configuration, _):
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
        case .installedAwaitingContinuityRepair, .deferred(.nonCurrent),
            .failed(.nonCurrent):
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
