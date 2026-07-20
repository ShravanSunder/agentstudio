import Foundation

enum RepoScannerResult: Sendable, Equatable {
    case completeAuthoritative(CompleteRepoScan)
    case partial(PartialRepoScan)
    case unavailable(UnavailableRepoScan)
    case cancelled(CancelledRepoScan)
    case failed(FailedRepoScan)
}

struct CompleteRepoScan: Sendable, Equatable {
    let verifiedEntries: [RepoScanner.ResolvedGitEntry]
    let counts: RepoScannerEvidenceCounts
    let serviceMetrics: RepoScannerServiceMetrics
}

struct PartialRepoScan: Sendable, Equatable {
    let verifiedEntries: [RepoScanner.ResolvedGitEntry]
    let failures: NonEmptyScanFailures
    let counts: RepoScannerEvidenceCounts
    let serviceMetrics: RepoScannerServiceMetrics
}

struct NonEmptyScanFailures: Sendable, Equatable {
    let first: ScanFailureReason
    let remaining: [ScanFailureReason]

    var all: [ScanFailureReason] {
        [first] + remaining
    }
}

struct UnavailableRepoScan: Sendable, Equatable {
    let reason: RepoScanUnavailableReason
    let counts: RepoScannerEvidenceCounts
    let serviceMetrics: RepoScannerServiceMetrics
}

struct CancelledRepoScan: Sendable, Equatable {
    let verifiedEntries: [RepoScanner.ResolvedGitEntry]
    let counts: RepoScannerEvidenceCounts
    let serviceMetrics: RepoScannerServiceMetrics
}

struct FailedRepoScan: Sendable, Equatable {
    let reason: ScanFailureReason
    let counts: RepoScannerEvidenceCounts
    let serviceMetrics: RepoScannerServiceMetrics
}

struct RepoScannerServiceMetrics: Sendable, Equatable {
    let traversalServiceDuration: Duration
    let validationServiceDuration: Duration

    static let zero = Self(
        traversalServiceDuration: .zero,
        validationServiceDuration: .zero
    )
}

struct RepoScannerEvidenceCounts: Sendable, Equatable {
    let directoryVisitCount: Int
    let directoryTraversalFailureCount: Int
    let entryMetadataFailureCount: Int
    let gitCandidateCount: Int
    let validationSuccessCount: Int
    let validationAuthoritativeNegativeCount: Int
    let validationTimeoutCount: Int
    let validationCancellationCount: Int
    let validationFailureCount: Int
    let scannerServiceInvocationCount: Int
}

enum RepoScanUnavailableReason: Sendable, Equatable {
    case rootDoesNotExist
    case rootIsNotDirectory
    case rootMetadataUnavailable(detail: String)
    case rootTraversalUnavailable(detail: String)
}

enum GitRepositoryAuthoritativeNegativeReason: Sendable, Equatable {
    case notAValidWorktree
    case exactCandidateIsNotRepository
    case invalidRepository
    case invalidWorktreeRegistration
    case bareRepository
    case canonicalPathMismatch
    case submoduleWorktree
    case mainWorktreeMismatch
}

enum GitRepositoryDiscoveryOutcome: Sendable, Equatable {
    case validated(RepoScanner.ResolvedGitEntry)
    case authoritativeNegative(GitRepositoryAuthoritativeNegativeReason)
    case timeout
    case cancelled
    case failure(GitRepositoryDiscoveryFailureReason)
}

enum GitRepositoryDiscoveryFailureReason: Sendable, Equatable {
    case validationFailed(detail: String)
    case repositoryIdentityFailed(detail: String)
    case serviceFailed(detail: String)
    case candidateAdmissionRejected(FilesystemDiscoveryCandidateRejection)
}

enum ScanFailureReason: Sendable, Equatable {
    case invalidMaximumDepth(Int)
    case directoryTraversalFailed(directoryPath: URL, detail: String)
    case entryMetadataReadFailed(entryPath: URL, detail: String)
    case gitMarkerInspectionFailed(candidatePath: URL, detail: String)
    case gitValidationTimedOut(candidatePath: URL)
    case gitRepositoryDiscoveryFailed(
        candidatePath: URL,
        reason: GitRepositoryDiscoveryFailureReason
    )
    case scannerServiceFailed(detail: String)
    case quantumPathByteLimitTooSmall(pathByteCount: Int, maximumPathBytes: Int)
    case sessionCapacityExceeded(RepoScannerSessionCapacityDimension)
}

enum RepoScannerSessionCapacityDimension: Sendable, Equatable {
    case enumeratedItemCount(maximum: Int)
    case enumeratedPathBytes(maximum: Int)
    case retainedVerifiedEntryCount(maximum: Int)
    case retainedVerifiedEntryBytes(maximum: Int)
    case retainedFailureCount(maximum: Int)
}

enum RepoScannerBudgetConfigurationError: Error, Sendable, Equatable {
    case nonPositiveMaximumEnumeratedItems(Int)
    case nonPositiveMaximumPathBytes(Int)
    case nonPositiveMaximumCandidateValidations(Int)
    case nonPositiveMaximumFailures(Int)
    case nonPositiveMaximumActiveServiceDuration(Duration)
    case nonPositiveMaximumSessionEnumeratedItems(Int)
    case nonPositiveMaximumSessionPathBytes(Int)
    case nonPositiveMaximumRetainedVerifiedEntries(Int)
    case nonPositiveMaximumRetainedVerifiedEntryBytes(Int)
    case nonPositiveMaximumRetainedFailures(Int)
}

struct RepoScannerQuantumBudget: Sendable, Equatable {
    let maximumEnumeratedItems: Int
    let maximumPathBytes: Int
    let maximumCandidateValidations: Int
    let maximumFailures: Int
    let maximumActiveServiceDuration: Duration

    static let productionDefault = Self(
        validatedMaximumEnumeratedItems: 256,
        maximumPathBytes: 1_048_576,
        maximumCandidateValidations: 8,
        maximumFailures: 64,
        maximumActiveServiceDuration: .milliseconds(8)
    )

    init(
        maximumEnumeratedItems: Int,
        maximumPathBytes: Int,
        maximumCandidateValidations: Int,
        maximumFailures: Int,
        maximumActiveServiceDuration: Duration
    ) throws {
        guard maximumEnumeratedItems > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumEnumeratedItems(
                maximumEnumeratedItems
            )
        }
        guard maximumPathBytes > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumPathBytes(maximumPathBytes)
        }
        guard maximumCandidateValidations > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumCandidateValidations(
                maximumCandidateValidations
            )
        }
        guard maximumFailures > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumFailures(maximumFailures)
        }
        guard maximumActiveServiceDuration > .zero else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumActiveServiceDuration(
                maximumActiveServiceDuration
            )
        }
        self.init(
            validatedMaximumEnumeratedItems: maximumEnumeratedItems,
            maximumPathBytes: maximumPathBytes,
            maximumCandidateValidations: maximumCandidateValidations,
            maximumFailures: maximumFailures,
            maximumActiveServiceDuration: maximumActiveServiceDuration
        )
    }

    private init(
        validatedMaximumEnumeratedItems: Int,
        maximumPathBytes: Int,
        maximumCandidateValidations: Int,
        maximumFailures: Int,
        maximumActiveServiceDuration: Duration
    ) {
        maximumEnumeratedItems = validatedMaximumEnumeratedItems
        self.maximumPathBytes = maximumPathBytes
        self.maximumCandidateValidations = maximumCandidateValidations
        self.maximumFailures = maximumFailures
        self.maximumActiveServiceDuration = maximumActiveServiceDuration
    }
}

struct RepoScannerSessionCapacity: Sendable, Equatable {
    let maximumEnumeratedItems: Int
    let maximumPathBytes: Int
    let maximumRetainedVerifiedEntries: Int
    let maximumRetainedVerifiedEntryBytes: Int
    let maximumRetainedFailures: Int

    static let productionDefault = Self(
        validatedMaximumEnumeratedItems: 1_000_000,
        maximumPathBytes: 1_073_741_824,
        maximumRetainedVerifiedEntries: 100_000,
        maximumRetainedVerifiedEntryBytes: 268_435_456,
        maximumRetainedFailures: 1024
    )

    init(
        maximumEnumeratedItems: Int,
        maximumPathBytes: Int,
        maximumRetainedVerifiedEntries: Int,
        maximumRetainedVerifiedEntryBytes: Int,
        maximumRetainedFailures: Int
    ) throws {
        guard maximumEnumeratedItems > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumSessionEnumeratedItems(
                maximumEnumeratedItems
            )
        }
        guard maximumPathBytes > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumSessionPathBytes(
                maximumPathBytes
            )
        }
        guard maximumRetainedVerifiedEntries > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumRetainedVerifiedEntries(
                maximumRetainedVerifiedEntries
            )
        }
        guard maximumRetainedVerifiedEntryBytes > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumRetainedVerifiedEntryBytes(
                maximumRetainedVerifiedEntryBytes
            )
        }
        guard maximumRetainedFailures > 0 else {
            throw RepoScannerBudgetConfigurationError.nonPositiveMaximumRetainedFailures(
                maximumRetainedFailures
            )
        }
        self.init(
            validatedMaximumEnumeratedItems: maximumEnumeratedItems,
            maximumPathBytes: maximumPathBytes,
            maximumRetainedVerifiedEntries: maximumRetainedVerifiedEntries,
            maximumRetainedVerifiedEntryBytes: maximumRetainedVerifiedEntryBytes,
            maximumRetainedFailures: maximumRetainedFailures
        )
    }

    private init(
        validatedMaximumEnumeratedItems: Int,
        maximumPathBytes: Int,
        maximumRetainedVerifiedEntries: Int,
        maximumRetainedVerifiedEntryBytes: Int,
        maximumRetainedFailures: Int
    ) {
        maximumEnumeratedItems = validatedMaximumEnumeratedItems
        self.maximumPathBytes = maximumPathBytes
        self.maximumRetainedVerifiedEntries = maximumRetainedVerifiedEntries
        self.maximumRetainedVerifiedEntryBytes = maximumRetainedVerifiedEntryBytes
        self.maximumRetainedFailures = maximumRetainedFailures
    }
}

struct RepoScannerQuantumUsage: Sendable, Equatable {
    let enumeratedItemCount: Int
    let enumeratedPathByteCount: Int
    let candidateValidationCount: Int
    let failureCount: Int
    let traversalServiceDuration: Duration
}

enum RepoScannerQuantumOutcome: Sendable, Equatable {
    case suspended(usage: RepoScannerQuantumUsage)
    case validationRequired(RepoScannerValidationRequest)
    case finished(RepoScannerResult)
}

struct RepoScannerSessionID: Hashable, Sendable {
    let rawValue: UUID
}

struct RepoScannerValidationRequestID: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
    var isUUIDv7: Bool { UUIDv7.isV7(rawValue) }
}

struct RepoScannerValidationRequest: Sendable, Equatable {
    let requestID: RepoScannerValidationRequestID
    let scannerSessionID: RepoScannerSessionID
    /// Correlation evidence only. This does not mint watched-root authority.
    let scanRootURL: URL
    let candidateURL: URL
}

struct RepoScannerValidationCompletion: Sendable, Equatable {
    let request: RepoScannerValidationRequest
    let outcome: GitRepositoryDiscoveryOutcome
    let validationServiceDuration: Duration
}

enum RepoScannerValidationCompletionRejection: Sendable, Equatable {
    case foreignSession(RepoScannerSessionID)
    case foreignRequest(RepoScannerValidationRequestID)
    case foreignRoot(URL)
    case foreignCandidate(URL)
    case staleRequest(RepoScannerValidationRequestID)
    case duplicateCompletion(RepoScannerValidationRequestID)
    case sessionFinished
}

enum RepoScannerValidationCompletionConsumptionResult: Sendable, Equatable {
    case consumed
    case rejected(RepoScannerValidationCompletionRejection)
}

enum RepoScannerSessionCancellationResult: Sendable, Equatable {
    case cancelled
    case cancellationRequested
    case cancelledAwaitingValidation(RepoScannerValidationRequest)
    case alreadyFinished
}
