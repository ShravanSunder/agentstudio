import Foundation

package enum RepoScannerResult: Sendable, Equatable {
    case completeAuthoritative(CompleteRepoScan)
    case partial(PartialRepoScan)
    case unavailable(UnavailableRepoScan)
    case cancelled(CancelledRepoScan)
    case failed(FailedRepoScan)
}

package struct CompleteRepoScan: Sendable, Equatable {
    package let verifiedEntries: [RepoScanner.ResolvedGitEntry]
    package let counts: RepoScannerEvidenceCounts
    package let serviceMetrics: RepoScannerServiceMetrics
}

package struct PartialRepoScan: Sendable, Equatable {
    package let verifiedEntries: [RepoScanner.ResolvedGitEntry]
    package let failures: NonEmptyScanFailures
    package let counts: RepoScannerEvidenceCounts
    package let serviceMetrics: RepoScannerServiceMetrics
}

package struct NonEmptyScanFailures: Sendable, Equatable {
    package let first: ScanFailureReason
    package let remaining: [ScanFailureReason]

    package var all: [ScanFailureReason] {
        [first] + remaining
    }
}

package struct UnavailableRepoScan: Sendable, Equatable {
    package let reason: RepoScanUnavailableReason
    package let counts: RepoScannerEvidenceCounts
    package let serviceMetrics: RepoScannerServiceMetrics
}

package struct CancelledRepoScan: Sendable, Equatable {
    package let verifiedEntries: [RepoScanner.ResolvedGitEntry]
    package let counts: RepoScannerEvidenceCounts
    package let serviceMetrics: RepoScannerServiceMetrics
}

package struct FailedRepoScan: Sendable, Equatable {
    package let reason: ScanFailureReason
    package let counts: RepoScannerEvidenceCounts
    package let serviceMetrics: RepoScannerServiceMetrics
}

package struct RepoScannerServiceMetrics: Sendable, Equatable {
    package let traversalServiceDuration: Duration
    package let validationServiceDuration: Duration

    package static let zero = Self(
        traversalServiceDuration: .zero,
        validationServiceDuration: .zero
    )
}

package struct RepoScannerEvidenceCounts: Sendable, Equatable {
    package let directoryVisitCount: Int
    package let directoryTraversalFailureCount: Int
    package let entryMetadataFailureCount: Int
    package let gitCandidateCount: Int
    package let validationSuccessCount: Int
    package let validationAuthoritativeNegativeCount: Int
    package let validationTimeoutCount: Int
    package let validationCancellationCount: Int
    package let validationFailureCount: Int
    package let scannerServiceInvocationCount: Int
}

package enum RepoScanUnavailableReason: Sendable, Equatable {
    case rootDoesNotExist
    case rootIsNotDirectory
    case rootMetadataUnavailable(detail: String)
    case rootTraversalUnavailable(detail: String)
}

package enum GitRepositoryAuthoritativeNegativeReason: Sendable, Equatable {
    case notAValidWorktree
    case exactCandidateIsNotRepository
    case invalidRepository
    case invalidWorktreeRegistration
    case bareRepository
    case canonicalPathMismatch
    case submoduleWorktree
    case mainWorktreeMismatch
}

package enum GitRepositoryDiscoveryOutcome: Sendable, Equatable {
    case validated(RepoScanner.ResolvedGitEntry)
    case authoritativeNegative(GitRepositoryAuthoritativeNegativeReason)
    case timeout
    case cancelled
    case failure(GitRepositoryDiscoveryFailureReason)
}

package enum GitRepositoryDiscoveryFailureReason: Sendable, Equatable {
    case validationFailed(detail: String)
    case repositoryIdentityFailed(detail: String)
    case serviceFailed(detail: String)
    case candidateAdmissionRejected(FilesystemDiscoveryCandidateRejection)
}

package enum ScanFailureReason: Sendable, Equatable {
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

package enum RepoScannerSessionCapacityDimension: Sendable, Equatable {
    case enumeratedItemCount(maximum: Int)
    case enumeratedPathBytes(maximum: Int)
    case retainedVerifiedEntryCount(maximum: Int)
    case retainedVerifiedEntryBytes(maximum: Int)
    case retainedFailureCount(maximum: Int)
}

package enum RepoScannerBudgetConfigurationError: Error, Sendable, Equatable {
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

package struct RepoScannerQuantumBudget: Sendable, Equatable {
    package let maximumEnumeratedItems: Int
    package let maximumPathBytes: Int
    package let maximumCandidateValidations: Int
    package let maximumFailures: Int
    package let maximumActiveServiceDuration: Duration

    package static let productionDefault = Self(
        validatedMaximumEnumeratedItems: 256,
        maximumPathBytes: 1_048_576,
        maximumCandidateValidations: 8,
        maximumFailures: 64,
        maximumActiveServiceDuration: .milliseconds(8)
    )

    package init(
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

package struct RepoScannerSessionCapacity: Sendable, Equatable {
    package let maximumEnumeratedItems: Int
    package let maximumPathBytes: Int
    package let maximumRetainedVerifiedEntries: Int
    package let maximumRetainedVerifiedEntryBytes: Int
    package let maximumRetainedFailures: Int

    package static let productionDefault = Self(
        validatedMaximumEnumeratedItems: 1_000_000,
        maximumPathBytes: 1_073_741_824,
        maximumRetainedVerifiedEntries: 100_000,
        maximumRetainedVerifiedEntryBytes: 268_435_456,
        maximumRetainedFailures: 1024
    )

    package init(
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

package struct RepoScannerQuantumUsage: Sendable, Equatable {
    package let enumeratedItemCount: Int
    package let enumeratedPathByteCount: Int
    package let candidateValidationCount: Int
    package let failureCount: Int
    package let traversalServiceDuration: Duration
}

package enum RepoScannerQuantumOutcome: Sendable, Equatable {
    case suspended(usage: RepoScannerQuantumUsage)
    case validationRequired(RepoScannerValidationRequest)
    case finished(RepoScannerResult)
}

package struct RepoScannerSessionID: Hashable, Sendable {
    package let rawValue: UUID
}

package struct RepoScannerValidationRequestID: Hashable, Sendable {
    package let rawValue: UUID

    package static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
    package var isUUIDv7: Bool { UUIDv7.isV7(rawValue) }
}

package struct RepoScannerValidationRequest: Sendable, Equatable {
    package let requestID: RepoScannerValidationRequestID
    package let scannerSessionID: RepoScannerSessionID
    /// Correlation evidence only. This does not mint watched-root authority.
    package let scanRootURL: URL
    package let candidateURL: URL

    package init(
        requestID: RepoScannerValidationRequestID,
        scannerSessionID: RepoScannerSessionID,
        scanRootURL: URL,
        candidateURL: URL
    ) {
        self.requestID = requestID
        self.scannerSessionID = scannerSessionID
        self.scanRootURL = scanRootURL
        self.candidateURL = candidateURL
    }
}

package struct RepoScannerValidationCompletion: Sendable, Equatable {
    package let request: RepoScannerValidationRequest
    package let outcome: GitRepositoryDiscoveryOutcome
    package let validationServiceDuration: Duration

    package init(
        request: RepoScannerValidationRequest,
        outcome: GitRepositoryDiscoveryOutcome,
        validationServiceDuration: Duration
    ) {
        self.request = request
        self.outcome = outcome
        self.validationServiceDuration = validationServiceDuration
    }
}

package enum RepoScannerValidationCompletionRejection: Sendable, Equatable {
    case foreignSession(RepoScannerSessionID)
    case foreignRequest(RepoScannerValidationRequestID)
    case foreignRoot(URL)
    case foreignCandidate(URL)
    case staleRequest(RepoScannerValidationRequestID)
    case duplicateCompletion(RepoScannerValidationRequestID)
    case sessionFinished
}

package enum RepoScannerValidationCompletionConsumptionResult: Sendable, Equatable {
    case consumed
    case rejected(RepoScannerValidationCompletionRejection)
}

package enum RepoScannerSessionCancellationResult: Sendable, Equatable {
    case cancelled
    case cancellationRequested
    case cancelledAwaitingValidation(RepoScannerValidationRequest)
    case alreadyFinished
}
