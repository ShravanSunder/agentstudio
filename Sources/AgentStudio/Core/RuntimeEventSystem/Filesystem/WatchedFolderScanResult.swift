import Foundation

struct WatchedFolderScanRequest: Equatable, Sendable {
    let canonicalRoot: RegisteredRootDescriptor
    let cause: WatchedFolderScanCause

    var sourceID: FilesystemSourceID { canonicalRoot.sourceID }
}

enum WatchedFolderScanCause: Equatable, Sendable {
    case initialAdd
    case callback
    case manual
    case fallback
    case repair(WatchedFolderRepairObligation)
}

struct WatchedFolderRepairObligation: Equatable, Sendable {
    let generation: RepairGeneration
    let unresolved: NonEmptyWatchedFolderRepairObligations
}

struct NonEmptyWatchedFolderRepairObligations: Equatable, Sendable {
    let first: FilesystemRepairParticipantToken
    let remaining: Set<FilesystemRepairParticipantToken>

    var all: Set<FilesystemRepairParticipantToken> {
        remaining.union([first])
    }

    func union(_ other: Self) -> Self {
        let unioned = all.union(other.all)
        return Self(first: first, remaining: unioned.subtracting([first]))
    }
}

/// Narrow adapter around scanner-owned resumable state. The scheduler can advance or
/// cancel the opaque session, but it cannot inspect traversal state or inventory.
struct WatchedFolderScannerSessionPort: Sendable {
    let id: RepoScannerSessionID
    let advanceOneQuantum: @Sendable () async -> RepoScannerQuantumOutcome
    let cancel: @Sendable () -> RepoScannerSessionCancellationResult
    let consumeValidationCompletion:
        @Sendable (RepoScannerValidationCompletion) ->
            RepoScannerValidationCompletionConsumptionResult
}

struct ScheduledWatchedFolderScanResult: Equatable, Sendable {
    let resultID: WatchedFolderScanResultID
    let request: WatchedFolderScanRequest
    let scanRunGeneration: UInt64
    let scannerResult: RepoScannerResult
    let schedulingMetrics: WatchedFolderScanSchedulingMetrics
}

struct WatchedFolderScanSchedulingMetrics: Equatable, Sendable {
    let queueWaitDuration: Duration
    let quantumSelectionCount: UInt64
    let staleRegistrationDropCount: UInt64
    let staleScanRunDropCount: UInt64
    let followUpEvidence: WatchedFolderScanFollowUpEvidence
}

enum WatchedFolderScanFollowUpEvidence: Equatable, Sendable {
    case noFollowUp
    case dirtyFollowUpQueued
    case startedFromDirtyFollowUp
}

struct WatchedFolderScanResultID: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct WatchedFolderScanResultConsumerToken: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct WatchedFolderScanResultLeaseID: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct WatchedFolderScanResultLease: Equatable, Sendable {
    let leaseID: WatchedFolderScanResultLeaseID
    let result: ScheduledWatchedFolderScanResult
}

enum WatchedFolderScanResultConsumerBinding: Equatable, Sendable {
    case bound
    case alreadyBound
    case rejected(WatchedFolderScanResultConsumerBindingRejection)
}

enum WatchedFolderScanResultConsumerBindingRejection: Equatable, Sendable {
    case anotherConsumerBound
    case schedulerShutDown
}

enum WatchedFolderScanResultConsumerUnbindResult: Equatable, Sendable {
    case unbound
    case alreadyUnbound
    case rejected(WatchedFolderScanResultConsumerUnbindRejection)
}

enum WatchedFolderScanResultConsumerUnbindRejection: Equatable, Sendable {
    case consumerMismatch
    case leaseOutstanding(WatchedFolderScanResultLeaseID)
}

enum WatchedFolderScanResultLeaseWaitResult: Equatable, Sendable {
    case leased(WatchedFolderScanResultLease)
    case cancelled
    case consumerUnbound
    case schedulerShutDown
    case rejected(WatchedFolderScanResultLeaseWaitRejection)
}

enum WatchedFolderScanResultLeaseWaitRejection: Equatable, Sendable {
    case consumerMismatch
    case waiterAlreadyRegistered
    case leaseAlreadyOutstanding(WatchedFolderScanResultLeaseID)
    case leaseIdentityExhausted
}

enum WatchedFolderScanResultLeaseResolution: Equatable, Sendable {
    case transferred
    case retry
}

enum WatchedFolderScanResultLeaseResolutionResult: Equatable, Sendable {
    case transferred
    case queuedForRetry
    case staleResultDiscarded
    case rejected(WatchedFolderScanResultLeaseResolutionRejection)
}

enum WatchedFolderScanResultLeaseResolutionRejection: Equatable, Sendable {
    case consumerMismatch
    case noLeaseOutstanding
    case leaseMismatch(
        submitted: WatchedFolderScanResultLeaseID,
        current: WatchedFolderScanResultLeaseID
    )
}

enum WatchedFolderScanSubmissionAcceptance: Equatable, Sendable {
    case started
    case queued
    case replacedQueued
    case markedRunningDirty
    case markedResultDirty
}

enum WatchedFolderScanSubmissionRejection: Equatable, Sendable {
    case schedulerShutDown
    case staleRegistration(
        submitted: FSEventRegistrationToken,
        current: FSEventRegistrationToken
    )
    case registrationDescriptorMismatch(FSEventRegistrationToken)
    case scanRunGenerationExhausted(FilesystemSourceID)
}

enum WatchedFolderScanSubmissionResult: Equatable, Sendable {
    case accepted(WatchedFolderScanSubmissionAcceptance)
    case rejected(WatchedFolderScanSubmissionRejection)
}

enum WatchedFolderScanRetirementDisposition: Equatable, Sendable {
    case idle
    case queuedRemoved
    case runningInvalidated
    case runningInvalidatedAndDirtyDiscarded
    case awaitingValidationInvalidated
    case awaitingValidationInvalidatedAndDirtyDiscarded
    case pendingResultDiscarded
    case pendingResultAndDirtyDiscarded
    case leasedResultInvalidated
    case leasedResultInvalidatedAndDirtyDiscarded
    case alreadyRetired
}

enum WatchedFolderScanRetirementRejection: Equatable, Sendable {
    case schedulerShutDown
    case sourceNotRegistered(FilesystemSourceID)
    case registrationMismatch(
        submitted: FSEventRegistrationToken,
        current: FSEventRegistrationToken
    )
    case registrationDescriptorMismatch(FSEventRegistrationToken)
}

enum WatchedFolderScanRetirementResult: Equatable, Sendable {
    case retired(WatchedFolderScanRetirementDisposition)
    case rejected(WatchedFolderScanRetirementRejection)
}

enum WatchedFolderScanSchedulerConfigurationError: Error, Equatable, Sendable {
    case invalidMaximumConcurrentScans(Int)
}

enum WatchedFolderScanSchedulerStateSnapshot: Equatable, Sendable {
    case active(WatchedFolderScanSchedulerActiveState)
    case shuttingDown(WatchedFolderScanSchedulerCustodyState)
    case shutDown
}

struct WatchedFolderScanSchedulerActiveState: Equatable, Sendable {
    let ready: Int
    let activeQuanta: Int
    let awaitingValidations: Int
    let pendingResults: Int
    let leasedResults: Int
    let runningAndDirty: Int
    let resultCustodyHighWater: Int
}

struct WatchedFolderScanSchedulerCustodyState: Equatable, Sendable {
    let activeQuanta: Int
    let awaitingValidations: Int
    let pendingResults: Int
    let leasedResults: Int
}
