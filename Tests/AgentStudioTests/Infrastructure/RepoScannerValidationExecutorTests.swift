import Foundation
import Testing

@testable import AgentStudio

@Suite("Repo scanner discovery validation executor")
struct RepoScannerValidationExecutorTests {
    @Test("timeout completion retires logical custody but retains native slot")
    func timeoutRetiresLogicalCustodyButRetainsNativeSlot() async throws {
        // Arrange
        let roots = try AuthorizedValidationRoots()
        defer { roots.remove() }
        let client = ControlledRepoDiscoveryReadClient()
        let deadlines = ManualRepoDiscoveryDeadlineScheduler()
        let executor = try makeExecutor(client: client, deadlines: deadlines, physical: 2, logical: 8)
        let first = try roots.request(name: "one", candidate: "one-repo")
        let second = try roots.request(name: "two", candidate: "two-repo")

        // Act
        #expect(await executor.submit(first) == .accepted(.started))
        #expect(await executor.submit(second) == .accepted(.started))
        await client.waitUntilStarted(candidateURL: first.candidateURL)
        await client.waitUntilStarted(candidateURL: second.candidateURL)
        await deadlines.waitUntilScheduledCount(2)
        deadlines.fireDeadline(at: 0)
        #expect(await executor.nextCompletion() == .completed(.timedOut(.init(request: first))))

        let followUp = roots.followUpRequest(for: first, candidate: "one-follow-up")
        #expect(await executor.submit(followUp) == .accepted(.queued))
        deadlines.fireDeadline(at: 0)
        #expect(await client.startedCandidates() == [first.candidateURL, second.candidateURL])

        await client.release(candidateURL: first.candidateURL, outcome: authoritativeNegative)
        await client.waitUntilStarted(candidateURL: followUp.candidateURL)

        // Assert
        #expect(
            await client.startedCandidates()
                == [first.candidateURL, second.candidateURL, followUp.candidateURL]
        )
        await client.release(candidateURL: second.candidateURL, outcome: authoritativeNegative)
        #expect(await executor.nextCompletion() == .completed(.timedOut(.init(request: second))))
        await client.release(candidateURL: followUp.candidateURL, outcome: authoritativeNegative)
        #expect(
            await executor.nextCompletion()
                == .completed(.finished(.init(request: followUp, outcome: authoritativeNegative)))
        )
        #expect(await executor.snapshot().lateNativeReturnCount == 2)
    }

    @Test("queued cancellation emits once and never starts native work")
    func queuedCancellationNeverStarts() async throws {
        // Arrange
        let roots = try AuthorizedValidationRoots()
        defer { roots.remove() }
        let client = ControlledRepoDiscoveryReadClient()
        let executor = try makeExecutor(client: client, physical: 1, logical: 8)
        let running = try roots.request(name: "running", candidate: "running-repo")
        let queued = try roots.request(name: "queued", candidate: "queued-repo")
        _ = await executor.submit(running)
        #expect(await executor.submit(queued) == .accepted(.queued))

        // Act
        let cancellation = await executor.cancel(requestID: queued.requestID)

        // Assert
        #expect(cancellation == .cancelled(.queued))
        #expect(
            await executor.nextCompletion()
                == .completed(.cancelled(.init(request: queued, cause: .explicitRequest)))
        )
        #expect(await executor.cancel(requestID: queued.requestID) == .alreadyCompleted)
        await client.waitUntilStarted(candidateURL: running.candidateURL)
        await client.release(candidateURL: running.candidateURL, outcome: authoritativeNegative)
        _ = await executor.nextCompletion()
        #expect(await client.startedCandidates() == [running.candidateURL])
    }

    @Test("two cancellation drains hold both native slots until actual return")
    func cancellationDrainsHoldPhysicalSlots() async throws {
        // Arrange
        let roots = try AuthorizedValidationRoots()
        defer { roots.remove() }
        let client = ControlledRepoDiscoveryReadClient()
        let executor = try makeExecutor(client: client, physical: 2, logical: 8)
        let first = try roots.request(name: "one", candidate: "one-repo")
        let second = try roots.request(name: "two", candidate: "two-repo")
        let third = try roots.request(name: "three", candidate: "three-repo")
        _ = await executor.submit(first)
        _ = await executor.submit(second)
        #expect(await executor.submit(third) == .accepted(.queued))
        await client.waitUntilStarted(candidateURL: first.candidateURL)
        await client.waitUntilStarted(candidateURL: second.candidateURL)

        // Act
        #expect(await executor.cancel(requestID: first.requestID) == .cancelled(.running))
        #expect(await executor.cancel(requestID: second.requestID) == .cancelled(.running))
        _ = await executor.nextCompletion()
        _ = await executor.nextCompletion()

        // Assert
        #expect(await client.startedCandidates() == [first.candidateURL, second.candidateURL])
        await client.release(candidateURL: first.candidateURL, outcome: authoritativeNegative)
        await client.waitUntilStarted(candidateURL: third.candidateURL)
        await client.release(candidateURL: second.candidateURL, outcome: authoritativeNegative)
        await client.release(candidateURL: third.candidateURL, outcome: authoritativeNegative)
        #expect(
            await executor.nextCompletion()
                == .completed(.finished(.init(request: third, outcome: authoritativeNegative)))
        )
        #expect(await executor.snapshot().lateNativeReturnCount == 2)
        #expect(await executor.snapshot().semanticCompletionCount == 3)
    }

    @Test("shutdown seals admission cancels logical work and reports native debt")
    func shutdownSealsAndReportsDrainDebt() async throws {
        // Arrange
        let roots = try AuthorizedValidationRoots()
        defer { roots.remove() }
        let client = ControlledRepoDiscoveryReadClient()
        let executor = try makeExecutor(client: client, physical: 2, logical: 8)
        let first = try roots.request(name: "one", candidate: "one-repo")
        let second = try roots.request(name: "two", candidate: "two-repo")
        let queued = try roots.request(name: "queued", candidate: "queued-repo")
        let rejected = try roots.request(name: "rejected", candidate: "rejected-repo")
        _ = await executor.submit(first)
        _ = await executor.submit(second)
        _ = await executor.submit(queued)
        await client.waitUntilStarted(candidateURL: first.candidateURL)
        await client.waitUntilStarted(candidateURL: second.candidateURL)

        // Act
        let shutdown = await executor.beginShutdown()

        // Assert
        #expect(shutdown == .started(cancelledLogicalRequestCount: 3, physicalDrainCount: 2))
        #expect(await executor.beginShutdown() == .alreadyStarted)
        #expect(await executor.submit(rejected) == .rejected(.shutdown))
        for _ in 0..<3 {
            guard case .completed(.cancelled(let cancellation)) = await executor.nextCompletion() else {
                Issue.record("expected shutdown cancellation")
                continue
            }
            #expect(cancellation.cause == .shutdown)
        }
        #expect(
            await executor.nextCompletion()
                == .shutdown(.drainingPhysicalJobs(count: 2))
        )
        #expect(await client.startedCandidates() == [first.candidateURL, second.candidateURL])
        await client.release(candidateURL: first.candidateURL, outcome: authoritativeNegative)
        await client.release(candidateURL: second.candidateURL, outcome: authoritativeNegative)
        await client.waitUntilReturnedCount(2)
        await executor.waitUntilPhysicalJobCount(0)
        #expect(await executor.nextCompletion() == .shutdown(.complete))
    }

    @Test("actor FIFO and logical capacity use source-authorized roots")
    func actorFIFOAndLogicalCapacity() async throws {
        // Arrange
        let roots = try AuthorizedValidationRoots()
        defer { roots.remove() }
        let client = ControlledRepoDiscoveryReadClient()
        let executor = try makeExecutor(client: client, physical: 1, logical: 3)
        let first = try roots.request(name: "one", candidate: "one-repo")
        let second = try roots.request(name: "two", candidate: "two-repo")
        let third = try roots.request(name: "three", candidate: "three-repo")
        let fourth = try roots.request(name: "four", candidate: "four-repo")

        // Act / Assert
        #expect(await executor.submit(first) == .accepted(.started))
        #expect(await executor.submit(second) == .accepted(.queued))
        #expect(await executor.submit(third) == .accepted(.queued))
        #expect(await executor.submit(fourth) == .rejected(.logicalCapacityReached(maximum: 3)))
        await finish(first, client: client, executor: executor)
        await client.waitUntilStarted(candidateURL: second.candidateURL)
        await finish(second, client: client, executor: executor)
        await client.waitUntilStarted(candidateURL: third.candidateURL)
        await finish(third, client: client, executor: executor)
        #expect(
            await client.startedCandidates()
                == [first.candidateURL, second.candidateURL, third.candidateURL]
        )
    }

    @Test("duplicate request session and source identities are rejected")
    func duplicateCurrentnessIsRejected() async throws {
        // Arrange
        let roots = try AuthorizedValidationRoots()
        defer { roots.remove() }
        let client = ControlledRepoDiscoveryReadClient()
        let executor = try makeExecutor(client: client, physical: 1, logical: 8)
        let first = try roots.request(name: "one", candidate: "one-repo")
        let otherRoot = try roots.request(name: "two", candidate: "two-repo")
        let duplicateRequest = RepoDiscoveryValidationRequest(
            requestID: first.requestID,
            scannerSessionID: otherRoot.scannerSessionID,
            authorizedRoot: otherRoot.authorizedRoot,
            candidateURL: otherRoot.candidateURL
        )
        let duplicateSession = RepoDiscoveryValidationRequest(
            requestID: .make(),
            scannerSessionID: first.scannerSessionID,
            authorizedRoot: otherRoot.authorizedRoot,
            candidateURL: otherRoot.candidateURL
        )
        let duplicateSource = RepoDiscoveryValidationRequest(
            requestID: .make(),
            scannerSessionID: otherRoot.scannerSessionID,
            authorizedRoot: first.authorizedRoot,
            candidateURL: otherRoot.candidateURL
        )

        // Act / Assert
        _ = await executor.submit(first)
        #expect(await executor.submit(duplicateRequest) == .rejected(.duplicateRequest(first.requestID)))
        #expect(
            await executor.submit(duplicateSession)
                == .rejected(.scannerSessionAlreadyOutstanding(first.scannerSessionID))
        )
        #expect(
            await executor.submit(duplicateSource)
                == .rejected(.sourceAlreadyOutstanding(first.authorizedRoot.sourceID))
        )
        #expect(first.requestID.isUUIDv7)
        await finish(first, client: client, executor: executor)
    }
}

private let authoritativeNegative = GitRepositoryDiscoveryOutcome.authoritativeNegative(
    .notAValidWorktree
)

private func makeExecutor(
    client: ControlledRepoDiscoveryReadClient,
    deadlines: ManualRepoDiscoveryDeadlineScheduler = ManualRepoDiscoveryDeadlineScheduler(),
    physical: Int,
    logical: Int
) throws -> RepoScannerValidationExecutor {
    try RepoScannerValidationExecutor(
        validationClient: client,
        deadlineScheduler: deadlines,
        budget: RepoDiscoveryValidationBudget(
            logicalDeadline: .seconds(2),
            maximumPhysicalJobs: physical,
            maximumQueuedRequests: logical,
            maximumQueuedRequestsPerRoot: 1
        )
    )
}

private func finish(
    _ request: RepoDiscoveryValidationRequest,
    client: ControlledRepoDiscoveryReadClient,
    executor: RepoScannerValidationExecutor
) async {
    await client.waitUntilStarted(candidateURL: request.candidateURL)
    await client.release(candidateURL: request.candidateURL, outcome: authoritativeNegative)
    _ = await executor.nextCompletion()
}

private final class AuthorizedValidationRoots {
    private let baseURL: URL

    init() throws {
        baseURL = FileManager.default.temporaryDirectory.appending(
            path: "repo-validation-(UUIDv7.generate())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func request(name: String, candidate: String) throws -> RepoDiscoveryValidationRequest {
        let rootURL = baseURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceID = FilesystemSourceID(
            kind: .watchedParentMembership,
            rootID: UUIDv7.generate()
        )
        let descriptor = try FilesystemSourceConfiguration.registerRoot(
            from: .hostAuthorized(
                FilesystemHostAuthorizedRootInput(
                    registration: FSEventRegistrationToken(
                        sourceID: sourceID,
                        registrationGeneration: 1,
                        rootGeneration: 1
                    ),
                    authorizedBoundary: rootURL,
                    registeredRoot: rootURL
                )
            )
        )
        return RepoDiscoveryValidationRequest(
            requestID: .make(),
            scannerSessionID: RepoScannerSessionID(rawValue: UUIDv7.generate()),
            authorizedRoot: descriptor,
            candidateURL: URL(fileURLWithPath: "/tmp/\(candidate)")
        )
    }

    func followUpRequest(
        for request: RepoDiscoveryValidationRequest,
        candidate: String
    ) -> RepoDiscoveryValidationRequest {
        RepoDiscoveryValidationRequest(
            requestID: .make(),
            scannerSessionID: request.scannerSessionID,
            authorizedRoot: request.authorizedRoot,
            candidateURL: URL(fileURLWithPath: "/tmp/\(candidate)")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: baseURL)
    }
}

private actor ControlledRepoDiscoveryReadClient: RepoDiscoveryReadClient {
    private var started: [URL] = []
    private var returnedCount = 0
    private var pending: [URL: CheckedContinuation<GitRepositoryDiscoveryOutcome, Never>] = [:]
    private var startWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]
    private var returnWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func validateDiscoveryCandidate(at candidateURL: URL) async -> GitRepositoryDiscoveryOutcome {
        let outcome = await withCheckedContinuation { continuation in
            pending[candidateURL] = continuation
            started.append(candidateURL)
            let waiters = startWaiters.removeValue(forKey: candidateURL) ?? []
            for waiter in waiters { waiter.resume() }
        }
        returnedCount += 1
        let ready = returnWaiters.filter { $0.0 <= returnedCount }
        returnWaiters.removeAll { $0.0 <= returnedCount }
        for waiter in ready { waiter.1.resume() }
        return outcome
    }

    func waitUntilStarted(candidateURL: URL) async {
        guard !started.contains(candidateURL) else { return }
        await withCheckedContinuation { startWaiters[candidateURL, default: []].append($0) }
    }

    func release(candidateURL: URL, outcome: GitRepositoryDiscoveryOutcome) {
        pending.removeValue(forKey: candidateURL)?.resume(returning: outcome)
    }

    func startedCandidates() -> [URL] { started }

    func waitUntilReturnedCount(_ count: Int) async {
        guard returnedCount < count else { return }
        await withCheckedContinuation { returnWaiters.append((count, $0)) }
    }
}

private final class ManualRepoDiscoveryDeadlineScheduler: RepoDiscoveryDeadlineScheduler,
    @unchecked Sendable
{
    private struct Deadline {
        let id: Int
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var nextID = 0
    private var deadlines: [Deadline] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func scheduleDeadline(
        after _: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> RepoDiscoveryScheduledDeadline {
        let id: Int
        let ready: [CheckedContinuation<Void, Never>]
        lock.lock()
        id = nextID
        nextID += 1
        deadlines.append(Deadline(id: id, handler: handler))
        ready = waiters.filter { $0.0 <= deadlines.count }.map(\.1)
        waiters.removeAll { $0.0 <= deadlines.count }
        lock.unlock()
        for waiter in ready { waiter.resume() }
        return RepoDiscoveryScheduledDeadline { [weak self] in self?.cancel(id: id) }
    }

    func waitUntilScheduledCount(_ count: Int) async {
        guard !hasCount(count) else { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if deadlines.count >= count {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((count, continuation))
                lock.unlock()
            }
        }
    }

    func fireDeadline(at index: Int) {
        lock.lock()
        let deadline = deadlines.indices.contains(index) ? deadlines.remove(at: index) : nil
        lock.unlock()
        deadline?.handler()
    }

    private func hasCount(_ count: Int) -> Bool {
        lock.lock()
        let result = deadlines.count >= count
        lock.unlock()
        return result
    }

    private func cancel(id: Int) {
        lock.lock()
        deadlines.removeAll { $0.id == id }
        lock.unlock()
    }
}
