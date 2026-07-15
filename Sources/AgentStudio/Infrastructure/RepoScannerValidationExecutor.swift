import Foundation

protocol RepoDiscoveryReadClient: Sendable {
    func validateDiscoveryCandidate(at candidateURL: URL) async -> GitRepositoryDiscoveryOutcome
}

struct RepoDiscoveryValidationRequestID: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
    var isUUIDv7: Bool { UUIDv7.isV7(rawValue) }
}

struct RepoDiscoveryValidationRequest: Equatable, Sendable {
    let requestID: RepoDiscoveryValidationRequestID
    let scannerSessionID: RepoScannerSessionID
    let authorizedRoot: RegisteredRootDescriptor
    let candidateURL: URL
}

enum RepoDiscoveryValidationBudgetError: Error, Equatable, Sendable {
    case nonPositiveLogicalDeadline(Duration)
    case nonPositiveMaximumPhysicalJobs(Int)
    case logicalCapacitySmallerThanPhysicalCapacity(logical: Int, physical: Int)
    case unsupportedMaximumQueuedRequestsPerRoot(Int)
}

struct RepoDiscoveryValidationBudget: Equatable, Sendable {
    let logicalDeadline: Duration
    let maximumPhysicalJobs: Int
    /// Maximum running, queued, or completed-but-undelivered logical requests.
    let maximumQueuedRequests: Int
    let maximumQueuedRequestsPerRoot: Int

    static let productionDefault = Self(
        validatedLogicalDeadline: AppPolicies.GitRefresh.defaultDiscoveryReadTimeout,
        maximumPhysicalJobs: 2,
        maximumQueuedRequests: 256,
        maximumQueuedRequestsPerRoot: 1
    )

    init(
        logicalDeadline: Duration,
        maximumPhysicalJobs: Int,
        maximumQueuedRequests: Int,
        maximumQueuedRequestsPerRoot: Int
    ) throws {
        guard logicalDeadline > .zero else {
            throw RepoDiscoveryValidationBudgetError.nonPositiveLogicalDeadline(logicalDeadline)
        }
        guard maximumPhysicalJobs > 0 else {
            throw RepoDiscoveryValidationBudgetError.nonPositiveMaximumPhysicalJobs(
                maximumPhysicalJobs
            )
        }
        guard maximumQueuedRequests >= maximumPhysicalJobs else {
            throw RepoDiscoveryValidationBudgetError.logicalCapacitySmallerThanPhysicalCapacity(
                logical: maximumQueuedRequests,
                physical: maximumPhysicalJobs
            )
        }
        guard maximumQueuedRequestsPerRoot == 1 else {
            throw RepoDiscoveryValidationBudgetError.unsupportedMaximumQueuedRequestsPerRoot(
                maximumQueuedRequestsPerRoot
            )
        }
        self.init(
            validatedLogicalDeadline: logicalDeadline,
            maximumPhysicalJobs: maximumPhysicalJobs,
            maximumQueuedRequests: maximumQueuedRequests,
            maximumQueuedRequestsPerRoot: maximumQueuedRequestsPerRoot
        )
    }

    private init(
        validatedLogicalDeadline: Duration,
        maximumPhysicalJobs: Int,
        maximumQueuedRequests: Int,
        maximumQueuedRequestsPerRoot: Int
    ) {
        logicalDeadline = validatedLogicalDeadline
        self.maximumPhysicalJobs = maximumPhysicalJobs
        self.maximumQueuedRequests = maximumQueuedRequests
        self.maximumQueuedRequestsPerRoot = maximumQueuedRequestsPerRoot
    }
}

enum RepoDiscoveryValidationAdmissionAcceptance: Equatable, Sendable {
    case started
    case queued
}

enum RepoDiscoveryValidationAdmissionRejection: Equatable, Sendable {
    case duplicateRequest(RepoDiscoveryValidationRequestID)
    case scannerSessionAlreadyOutstanding(RepoScannerSessionID)
    case sourceAlreadyOutstanding(FilesystemSourceID)
    case logicalCapacityReached(maximum: Int)
    case shutdown
}

enum RepoDiscoveryValidationAdmissionResult: Equatable, Sendable {
    case accepted(RepoDiscoveryValidationAdmissionAcceptance)
    case rejected(RepoDiscoveryValidationAdmissionRejection)
}

struct FinishedRepoDiscoveryValidation: Equatable, Sendable {
    let request: RepoDiscoveryValidationRequest
    let outcome: GitRepositoryDiscoveryOutcome
}

struct TimedOutRepoDiscoveryValidation: Equatable, Sendable {
    let request: RepoDiscoveryValidationRequest
}

enum RepoDiscoveryValidationCancellationCause: Equatable, Sendable {
    case explicitRequest
    case shutdown
}

struct CancelledRepoDiscoveryValidation: Equatable, Sendable {
    let request: RepoDiscoveryValidationRequest
    let cause: RepoDiscoveryValidationCancellationCause
}

enum RepoDiscoveryValidationCompletion: Equatable, Sendable {
    case finished(FinishedRepoDiscoveryValidation)
    case timedOut(TimedOutRepoDiscoveryValidation)
    case cancelled(CancelledRepoDiscoveryValidation)
}

enum RepoDiscoveryValidationCancellationDisposition: Equatable, Sendable {
    case queued
    case running
}

enum RepoDiscoveryValidationCancellationResult: Equatable, Sendable {
    case cancelled(RepoDiscoveryValidationCancellationDisposition)
    case alreadyCompleted
    case unknownRequest
}

enum RepoDiscoveryValidationShutdownResult: Equatable, Sendable {
    case started(cancelledLogicalRequestCount: Int, physicalDrainCount: Int)
    case alreadyStarted
}

enum RepoDiscoveryValidationShutdownState: Equatable, Sendable {
    case drainingPhysicalJobs(count: Int)
    case complete
}

enum RepoDiscoveryValidationCompletionWaitRejection: Equatable, Sendable {
    case anotherWaiterRegistered
}

enum RepoDiscoveryValidationCompletionWaitResult: Equatable, Sendable {
    case completed(RepoDiscoveryValidationCompletion)
    case cancelled
    case shutdown(RepoDiscoveryValidationShutdownState)
    case rejected(RepoDiscoveryValidationCompletionWaitRejection)
}

struct RepoDiscoveryValidationExecutorSnapshot: Equatable, Sendable {
    let physicalJobCount: Int
    let drainingPhysicalJobCount: Int
    let queuedRequestCount: Int
    let logicalRequestCount: Int
    let semanticCompletionCount: UInt64
    let lateNativeReturnCount: UInt64
    let staleNativeReturnCount: UInt64
}

protocol RepoDiscoveryDeadlineScheduler: Sendable {
    func scheduleDeadline(
        after duration: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> RepoDiscoveryScheduledDeadline
}

struct RepoDiscoveryScheduledDeadline: Sendable {
    private let cancelHandler: @Sendable () -> Void

    init(cancel: @escaping @Sendable () -> Void) { cancelHandler = cancel }
    func cancel() { cancelHandler() }
}

struct DispatchRepoDiscoveryDeadlineScheduler: RepoDiscoveryDeadlineScheduler {
    private static let queue = DispatchQueue(
        label: "com.agentstudio.repo-discovery-deadline",
        qos: .utility
    )

    func scheduleDeadline(
        after duration: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> RepoDiscoveryScheduledDeadline {
        let workItem = SendableRepoDiscoveryDeadlineWorkItem(handler: handler)
        Self.queue.asyncAfter(
            deadline: .now() + duration.timeIntervalForDispatch,
            execute: workItem.dispatchWorkItem
        )
        return RepoDiscoveryScheduledDeadline { workItem.cancel() }
    }
}

private final class SendableRepoDiscoveryDeadlineWorkItem: @unchecked Sendable {
    let dispatchWorkItem: DispatchWorkItem

    init(handler: @escaping @Sendable () -> Void) {
        dispatchWorkItem = DispatchWorkItem(block: handler)
    }

    func cancel() { dispatchWorkItem.cancel() }
}

actor RepoScannerValidationExecutor {
    private struct PhysicalJobID: Hashable, Sendable {
        let rawValue: UUID
        static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
    }

    private enum PhysicalJobPhase: Sendable {
        case running(RepoDiscoveryScheduledDeadline)
        case drainingAfterTimeout
        case drainingAfterCancellation
    }

    private struct PhysicalJob: Sendable {
        let jobID: PhysicalJobID
        let request: RepoDiscoveryValidationRequest
        var phase: PhysicalJobPhase
    }

    private enum LogicalRequestPhase: Sendable {
        case queued
        case running(PhysicalJobID)
        case semanticCompletionPendingDelivery
    }

    private struct LogicalRequest: Sendable {
        let request: RepoDiscoveryValidationRequest
        var phase: LogicalRequestPhase
    }

    private struct CompletionWaiter: Sendable {
        let identity: RepoDiscoveryValidationRequestID
        let continuation: CheckedContinuation<RepoDiscoveryValidationCompletionWaitResult, Never>
    }

    private let validationClient: any RepoDiscoveryReadClient
    private let deadlineScheduler: any RepoDiscoveryDeadlineScheduler
    private let budget: RepoDiscoveryValidationBudget
    private var acceptingAdmissions = true
    private var readySourceRing: [FilesystemSourceID] = []
    private var queuedRequestBySource: [FilesystemSourceID: RepoDiscoveryValidationRequest] = [:]
    private var logicalRequests: [RepoDiscoveryValidationRequestID: LogicalRequest] = [:]
    private var physicalJobs: [PhysicalJobID: PhysicalJob] = [:]
    private var requestToPhysicalJob: [RepoDiscoveryValidationRequestID: PhysicalJobID] = [:]
    private var outstandingSessions: Set<RepoScannerSessionID> = []
    private var outstandingSources: Set<FilesystemSourceID> = []
    private var recentRequestIDs: Set<RepoDiscoveryValidationRequestID> = []
    private var recentRequestIDOrder: [RepoDiscoveryValidationRequestID] = []
    private var completions: [RepoDiscoveryValidationCompletion] = []
    private var completionWaiter: CompletionWaiter?
    private var physicalDrainWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var semanticCompletionCount: UInt64 = 0
    private var lateNativeReturnCount: UInt64 = 0
    private var staleNativeReturnCount: UInt64 = 0

    init(
        validationClient: any RepoDiscoveryReadClient,
        deadlineScheduler: any RepoDiscoveryDeadlineScheduler = DispatchRepoDiscoveryDeadlineScheduler(),
        budget: RepoDiscoveryValidationBudget = .productionDefault
    ) throws {
        self.validationClient = validationClient
        self.deadlineScheduler = deadlineScheduler
        self.budget = budget
    }

    func submit(_ request: RepoDiscoveryValidationRequest) -> RepoDiscoveryValidationAdmissionResult {
        guard acceptingAdmissions else { return .rejected(.shutdown) }
        if logicalRequests[request.requestID] != nil || recentRequestIDs.contains(request.requestID) {
            return .rejected(.duplicateRequest(request.requestID))
        }
        if outstandingSessions.contains(request.scannerSessionID) {
            return .rejected(.scannerSessionAlreadyOutstanding(request.scannerSessionID))
        }
        let sourceID = request.authorizedRoot.sourceID
        if outstandingSources.contains(sourceID) {
            return .rejected(.sourceAlreadyOutstanding(sourceID))
        }
        guard logicalRequests.count < budget.maximumQueuedRequests else {
            return .rejected(.logicalCapacityReached(maximum: budget.maximumQueuedRequests))
        }

        outstandingSessions.insert(request.scannerSessionID)
        outstandingSources.insert(sourceID)
        if physicalJobs.count < budget.maximumPhysicalJobs {
            logicalRequests[request.requestID] = LogicalRequest(request: request, phase: .queued)
            startPhysicalJob(for: request)
            return .accepted(.started)
        }
        logicalRequests[request.requestID] = LogicalRequest(request: request, phase: .queued)
        readySourceRing.append(sourceID)
        queuedRequestBySource[sourceID] = request
        return .accepted(.queued)
    }

    func cancel(
        requestID: RepoDiscoveryValidationRequestID
    ) -> RepoDiscoveryValidationCancellationResult {
        cancelLogicalRequest(requestID: requestID, cause: .explicitRequest)
    }

    func beginShutdown() -> RepoDiscoveryValidationShutdownResult {
        guard acceptingAdmissions else { return .alreadyStarted }
        acceptingAdmissions = false
        let cancellableIDs = logicalRequests.compactMap { requestID, logical -> RepoDiscoveryValidationRequestID? in
            switch logical.phase {
            case .queued, .running:
                requestID
            case .semanticCompletionPendingDelivery:
                nil
            }
        }
        for requestID in cancellableIDs {
            _ = cancelLogicalRequest(requestID: requestID, cause: .shutdown)
        }
        resumeCompletionWaiterForShutdownIfPossible()
        return .started(
            cancelledLogicalRequestCount: cancellableIDs.count,
            physicalDrainCount: physicalJobs.count
        )
    }

    func nextCompletion() async -> RepoDiscoveryValidationCompletionWaitResult {
        let waiterIdentity = RepoDiscoveryValidationRequestID.make()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerCompletionWaiter(identity: waiterIdentity, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelCompletionWaiter(identity: waiterIdentity) }
        }
    }

    func waitUntilPhysicalJobCount(_ maximumCount: Int) async {
        guard physicalJobs.count > maximumCount else { return }
        await withCheckedContinuation { continuation in
            physicalDrainWaiters.append((maximumCount, continuation))
        }
    }

    func snapshot() -> RepoDiscoveryValidationExecutorSnapshot {
        RepoDiscoveryValidationExecutorSnapshot(
            physicalJobCount: physicalJobs.count,
            drainingPhysicalJobCount: physicalJobs.values.count { job in
                switch job.phase {
                case .running: false
                case .drainingAfterTimeout, .drainingAfterCancellation: true
                }
            },
            queuedRequestCount: readySourceRing.count,
            logicalRequestCount: logicalRequests.count,
            semanticCompletionCount: semanticCompletionCount,
            lateNativeReturnCount: lateNativeReturnCount,
            staleNativeReturnCount: staleNativeReturnCount
        )
    }
}

extension RepoScannerValidationExecutor {
    private func startPhysicalJob(for request: RepoDiscoveryValidationRequest) {
        let jobID = PhysicalJobID.make()
        let deadline = deadlineScheduler.scheduleDeadline(after: budget.logicalDeadline) {
            Task { await self.logicalDeadlineReached(jobID: jobID) }
        }
        physicalJobs[jobID] = PhysicalJob(jobID: jobID, request: request, phase: .running(deadline))
        requestToPhysicalJob[request.requestID] = jobID
        logicalRequests[request.requestID]?.phase = .running(jobID)
        let validationClient = validationClient
        // Detached by design: a synchronous native read must not inherit executor actor isolation.
        // swiftlint:disable:next no_task_detached
        Task.detached(priority: .utility) {
            let outcome = await validationClient.validateDiscoveryCandidate(at: request.candidateURL)
            await self.nativeValidationReturned(jobID: jobID, outcome: outcome)
        }
    }

    private func logicalDeadlineReached(jobID: PhysicalJobID) {
        guard var job = physicalJobs[jobID], case .running = job.phase else { return }
        guard logicalRequestCanComplete(job.request.requestID) else { return }
        job.phase = .drainingAfterTimeout
        physicalJobs[jobID] = job
        markLogicalCompletion(
            .timedOut(TimedOutRepoDiscoveryValidation(request: job.request))
        )
    }

    private func nativeValidationReturned(
        jobID: PhysicalJobID,
        outcome: GitRepositoryDiscoveryOutcome
    ) {
        guard let job = physicalJobs.removeValue(forKey: jobID) else {
            staleNativeReturnCount &+= 1
            return
        }
        requestToPhysicalJob.removeValue(forKey: job.request.requestID)
        switch job.phase {
        case .running(let deadline):
            deadline.cancel()
            if logicalRequestCanComplete(job.request.requestID) {
                markLogicalCompletion(
                    .finished(FinishedRepoDiscoveryValidation(request: job.request, outcome: outcome))
                )
            }
        case .drainingAfterTimeout, .drainingAfterCancellation:
            lateNativeReturnCount &+= 1
        }
        resumePhysicalDrainWaiters()
        startReadyJobsWithinCapacity()
        resumeCompletionWaiterForShutdownIfPossible()
    }

    private func cancelLogicalRequest(
        requestID: RepoDiscoveryValidationRequestID,
        cause: RepoDiscoveryValidationCancellationCause
    ) -> RepoDiscoveryValidationCancellationResult {
        guard let logical = logicalRequests[requestID] else {
            return recentRequestIDs.contains(requestID) ? .alreadyCompleted : .unknownRequest
        }
        switch logical.phase {
        case .semanticCompletionPendingDelivery:
            return .alreadyCompleted
        case .queued:
            let sourceID = logical.request.authorizedRoot.sourceID
            queuedRequestBySource.removeValue(forKey: sourceID)
            readySourceRing.removeAll { $0 == sourceID }
            markLogicalCompletion(
                .cancelled(CancelledRepoDiscoveryValidation(request: logical.request, cause: cause))
            )
            return .cancelled(.queued)
        case .running(let jobID):
            guard var job = physicalJobs[jobID], case .running(let deadline) = job.phase else {
                return .alreadyCompleted
            }
            deadline.cancel()
            job.phase = .drainingAfterCancellation
            physicalJobs[jobID] = job
            markLogicalCompletion(
                .cancelled(CancelledRepoDiscoveryValidation(request: logical.request, cause: cause))
            )
            return .cancelled(.running)
        }
    }

    private func logicalRequestCanComplete(_ requestID: RepoDiscoveryValidationRequestID) -> Bool {
        guard let logical = logicalRequests[requestID] else { return false }
        if case .semanticCompletionPendingDelivery = logical.phase { return false }
        return true
    }

    private func markLogicalCompletion(_ completion: RepoDiscoveryValidationCompletion) {
        let requestID = completion.request.requestID
        logicalRequests[requestID]?.phase = .semanticCompletionPendingDelivery
        semanticCompletionCount &+= 1
        if let waiter = completionWaiter {
            completionWaiter = nil
            retireLogicalRequest(requestID)
            waiter.continuation.resume(returning: .completed(completion))
        } else {
            completions.append(completion)
        }
    }

    private func retireLogicalRequest(_ requestID: RepoDiscoveryValidationRequestID) {
        guard let logical = logicalRequests.removeValue(forKey: requestID) else { return }
        outstandingSessions.remove(logical.request.scannerSessionID)
        outstandingSources.remove(logical.request.authorizedRoot.sourceID)
        recentRequestIDs.insert(requestID)
        recentRequestIDOrder.append(requestID)
        if recentRequestIDOrder.count > budget.maximumQueuedRequests {
            recentRequestIDs.remove(recentRequestIDOrder.removeFirst())
        }
    }

    private func startReadyJobsWithinCapacity() {
        guard acceptingAdmissions else { return }
        while physicalJobs.count < budget.maximumPhysicalJobs, !readySourceRing.isEmpty {
            let sourceID = readySourceRing.removeFirst()
            guard let request = queuedRequestBySource.removeValue(forKey: sourceID) else { continue }
            startPhysicalJob(for: request)
        }
    }
}

extension RepoScannerValidationExecutor {
    private func registerCompletionWaiter(
        identity: RepoDiscoveryValidationRequestID,
        continuation: CheckedContinuation<RepoDiscoveryValidationCompletionWaitResult, Never>
    ) {
        if Task.isCancelled {
            continuation.resume(returning: .cancelled)
        } else if !completions.isEmpty {
            let completion = completions.removeFirst()
            retireLogicalRequest(completion.request.requestID)
            continuation.resume(returning: .completed(completion))
        } else if !acceptingAdmissions {
            continuation.resume(returning: .shutdown(currentShutdownState))
        } else if completionWaiter != nil {
            continuation.resume(returning: .rejected(.anotherWaiterRegistered))
        } else {
            completionWaiter = CompletionWaiter(identity: identity, continuation: continuation)
        }
    }

    private func cancelCompletionWaiter(identity: RepoDiscoveryValidationRequestID) {
        guard completionWaiter?.identity == identity else { return }
        let waiter = completionWaiter
        completionWaiter = nil
        waiter?.continuation.resume(returning: .cancelled)
    }

    private var currentShutdownState: RepoDiscoveryValidationShutdownState {
        physicalJobs.isEmpty ? .complete : .drainingPhysicalJobs(count: physicalJobs.count)
    }

    private func resumeCompletionWaiterForShutdownIfPossible() {
        guard !acceptingAdmissions, completions.isEmpty, let waiter = completionWaiter else { return }
        completionWaiter = nil
        waiter.continuation.resume(returning: .shutdown(currentShutdownState))
    }

    private func resumePhysicalDrainWaiters() {
        let ready = physicalDrainWaiters.filter { $0.0 >= physicalJobs.count }
        physicalDrainWaiters.removeAll { $0.0 >= physicalJobs.count }
        for waiter in ready { waiter.1.resume() }
    }
}

extension RepoDiscoveryValidationCompletion {
    fileprivate var request: RepoDiscoveryValidationRequest {
        switch self {
        case .finished(let value): value.request
        case .timedOut(let value): value.request
        case .cancelled(let value): value.request
        }
    }
}

extension Duration {
    fileprivate var timeIntervalForDispatch: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
