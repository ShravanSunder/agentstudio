import Foundation
import Synchronization

extension RepoScannerTraversalSession {
    /// Guards Foundation's non-Sendable enumerator with the strict single-quantum lifecycle lease.
    final class TraversalLease: @unchecked Sendable {
        var state: TraversalState

        init(state: TraversalState) {
            self.state = state
        }

    }

    enum AdvanceCustody: Sendable {
        case traversal(TraversalLease)
        case validation(RepoScannerValidationRequest)
        case finished(RepoScannerResult)
    }

    struct ReadyCustody: Sendable {
        let traversalLease: TraversalLease
        let completionHistory: ValidationCompletionHistory
    }

    struct PendingValidationCustody: @unchecked Sendable {
        let request: RepoScannerValidationRequest
        let continuation: PostValidationContinuation
        let traversalLease: TraversalLease
        let completionHistory: ValidationCompletionHistory
    }

    /// Retains recent completion identities for diagnostic rejection classification only.
    /// The exact pending request remains the sole authority for advancing the session. Once an
    /// old identity is evicted, it is safely classified as foreign/unrecognized; this history
    /// neither grants completion authority nor establishes ordering.
    struct ValidationCompletionHistory: Sendable {
        static let maximumRetainedRequestCount = 256
        static let empty = Self(recentRequestIDs: [], nextEvictionIndex: 0)

        private var recentRequestIDs: [RepoScannerValidationRequestID]
        private var nextEvictionIndex: Int

        func contains(_ requestID: RepoScannerValidationRequestID) -> Bool {
            recentRequestIDs.contains(requestID)
        }

        func recording(_ requestID: RepoScannerValidationRequestID) -> Self {
            var updatedHistory = self
            if updatedHistory.recentRequestIDs.count < Self.maximumRetainedRequestCount {
                updatedHistory.recentRequestIDs.append(requestID)
            } else {
                updatedHistory.recentRequestIDs[updatedHistory.nextEvictionIndex] = requestID
                updatedHistory.nextEvictionIndex =
                    (updatedHistory.nextEvictionIndex + 1) % Self.maximumRetainedRequestCount
            }
            return updatedHistory
        }

    }

    enum Lifecycle: Sendable {
        case ready(ReadyCustody)
        case leased(
            cancellationRequested: Bool,
            completionHistory: ValidationCompletionHistory
        )
        case awaitingValidation(PendingValidationCustody)
        case finished(
            RepoScannerResult,
            completionHistory: ValidationCompletionHistory
        )
    }

    enum QuantumDisposition {
        case suspended
        case validationRequired(
            RepoScannerValidationRequest,
            continuation: PostValidationContinuation
        )
        case exhausted
        case unavailable(RepoScanUnavailableReason)
        case failed(ScanFailureReason)
        case cancelled

        var isCancelled: Bool {
            guard case .cancelled = self else { return false }
            return true
        }
    }

    enum ValidationApplicationDisposition {
        case resumeTraversal
        case exhausted
        case cancelled
    }

    enum TraversalPosition {
        case inspectRoot
        case enumerating(EnumerationCursor)
        case pendingEntry(PendingEnumerationEntry, cursor: EnumerationCursor)
        case pendingValidation(URL, continuation: PostValidationContinuation)
        case exhausted
    }

    enum PostValidationContinuation {
        case enumerating(EnumerationCursor)
        case exhausted

        var position: TraversalPosition {
            switch self {
            case .enumerating(let cursor):
                return .enumerating(cursor)
            case .exhausted:
                return .exhausted
            }
        }
    }

    struct PendingEnumerationEntry {
        let url: URL
        let depth: Int
    }

    struct EnumerationCursor {
        let enumerator: FileManager.DirectoryEnumerator
        let errorBuffer: DirectoryEnumerationErrorBuffer
    }

    enum EnumerationCursorAvailability {
        case available(EnumerationCursor)
        case unavailable(String)
    }

    enum GitMarkerInspection {
        case candidate
        case notCandidate
        case failed(String)
    }

    struct TraversalState {
        let rootURL: URL
        let maxDepth: Int
        var position: TraversalPosition
        var verifiedEntries: [ResolvedGitEntry] = []
        var failures: [ScanFailureReason] = []
        var directoryVisitCount = 0
        var directoryTraversalFailureCount = 0
        var entryMetadataFailureCount = 0
        var gitCandidateCount = 0
        var validationSuccessCount = 0
        var validationAuthoritativeNegativeCount = 0
        var validationTimeoutCount = 0
        var validationCancellationCount = 0
        var validationFailureCount = 0
        var scannerServiceInvocationCount = 0
        var traversalServiceDuration = Duration.zero
        var validationServiceDuration = Duration.zero
        var enumeratedItemCount = 0
        var enumeratedPathByteCount = 0
        var retainedVerifiedEntryByteCount = 0

        init(rootURL: URL, maxDepth: Int, position: TraversalPosition) {
            self.rootURL = rootURL
            self.maxDepth = maxDepth
            self.position = position
        }

        var counts: RepoScannerEvidenceCounts {
            RepoScannerEvidenceCounts(
                directoryVisitCount: directoryVisitCount,
                directoryTraversalFailureCount: directoryTraversalFailureCount,
                entryMetadataFailureCount: entryMetadataFailureCount,
                gitCandidateCount: gitCandidateCount,
                validationSuccessCount: validationSuccessCount,
                validationAuthoritativeNegativeCount: validationAuthoritativeNegativeCount,
                validationTimeoutCount: validationTimeoutCount,
                validationCancellationCount: validationCancellationCount,
                validationFailureCount: validationFailureCount,
                scannerServiceInvocationCount: scannerServiceInvocationCount
            )
        }

        var serviceMetrics: RepoScannerServiceMetrics {
            RepoScannerServiceMetrics(
                traversalServiceDuration: traversalServiceDuration,
                validationServiceDuration: validationServiceDuration
            )
        }

        var sortedEntries: [ResolvedGitEntry] {
            verifiedEntries.sorted {
                $0.path.lastPathComponent.localizedCaseInsensitiveCompare(
                    $1.path.lastPathComponent
                ) == .orderedAscending
            }
        }

        func exhaustedResult() -> RepoScannerResult {
            guard let firstFailure = failures.first else {
                return .completeAuthoritative(
                    CompleteRepoScan(
                        verifiedEntries: sortedEntries,
                        counts: counts,
                        serviceMetrics: serviceMetrics
                    )
                )
            }
            return .partial(
                PartialRepoScan(
                    verifiedEntries: sortedEntries,
                    failures: NonEmptyScanFailures(
                        first: firstFailure,
                        remaining: Array(failures.dropFirst())
                    ),
                    counts: counts,
                    serviceMetrics: serviceMetrics
                )
            )
        }

        func unavailableResult(reason: RepoScanUnavailableReason) -> RepoScannerResult {
            .unavailable(
                UnavailableRepoScan(
                    reason: reason,
                    counts: counts,
                    serviceMetrics: serviceMetrics
                )
            )
        }

        func failedResult(reason: ScanFailureReason) -> RepoScannerResult {
            .failed(
                FailedRepoScan(
                    reason: reason,
                    counts: counts,
                    serviceMetrics: serviceMetrics
                )
            )
        }

        func cancelledResult() -> RepoScannerResult {
            .cancelled(
                CancelledRepoScan(
                    verifiedEntries: sortedEntries,
                    counts: counts,
                    serviceMetrics: serviceMetrics
                )
            )
        }
    }

    struct MutableQuantumUsage {
        var enumeratedItemCount = 0
        var enumeratedPathByteCount = 0
        var candidateValidationCount = 0
        var failureCount = 0
        var traversalServiceDuration = Duration.zero

        var hasMadeProgress: Bool {
            enumeratedItemCount > 0 || candidateValidationCount > 0 || failureCount > 0
        }

        var snapshot: RepoScannerQuantumUsage {
            RepoScannerQuantumUsage(
                enumeratedItemCount: enumeratedItemCount,
                enumeratedPathByteCount: enumeratedPathByteCount,
                candidateValidationCount: candidateValidationCount,
                failureCount: failureCount,
                traversalServiceDuration: traversalServiceDuration
            )
        }
    }

    struct DirectoryEnumerationErrorRecord {
        let url: URL
        let detail: String
    }

    struct DirectoryEnumerationErrorDrain {
        let records: [DirectoryEnumerationErrorRecord]
        let stoppedForLimit: Bool
    }

    final class DirectoryEnumerationErrorBuffer: Sendable {
        private struct State {
            var maximumAdditionalErrors: Int
            var records: [DirectoryEnumerationErrorRecord] = []
            var stoppedForLimit = false
        }

        private let state: Mutex<State>

        init(maximumBufferedErrors: Int) {
            state = Mutex(State(maximumAdditionalErrors: maximumBufferedErrors))
        }

        func prepare(maximumAdditionalErrors: Int) {
            state.withLock { state in
                state.maximumAdditionalErrors = maximumAdditionalErrors
                state.records.removeAll(keepingCapacity: true)
                state.stoppedForLimit = false
            }
        }

        func record(url: URL, error: Error) -> Bool {
            state.withLock { state in
                guard state.records.count < state.maximumAdditionalErrors else {
                    state.stoppedForLimit = true
                    return false
                }
                state.records.append(
                    DirectoryEnumerationErrorRecord(
                        url: url,
                        detail: String(describing: error)
                    )
                )
                return true
            }
        }

        func drain() -> DirectoryEnumerationErrorDrain {
            state.withLock { state in
                let drain = DirectoryEnumerationErrorDrain(
                    records: state.records,
                    stoppedForLimit: state.stoppedForLimit
                )
                state.records.removeAll(keepingCapacity: true)
                state.stoppedForLimit = false
                return drain
            }
        }
    }
}
