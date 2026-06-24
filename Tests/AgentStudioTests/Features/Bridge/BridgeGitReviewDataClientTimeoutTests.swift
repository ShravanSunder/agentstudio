import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio

struct BridgeGitReviewDataClientTimeoutTests {
    @Test("AgentStudioGit adapter times out non-cooperative diff reads")
    func agentStudioGitAdapterTimesOutNonCooperativeDiffReads() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-adapter-timeout-test")
        let readGate = BridgeGitDataPlaneReadGate()
        let timeoutScheduler = ManualBridgeGitDataPlaneTimeoutScheduler()
        let gitClient = NonCooperativeDiffAgentStudioGitClient(readGate: readGate)
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient,
            gitDataPlaneReadTimeout: .seconds(999),
            timeoutScheduler: timeoutScheduler
        )
        let provider = BridgeGitReviewSourceProvider(client: adapter)
        let baseEndpoint = makeBridgeEndpoint(endpointId: "abc123", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working", kind: .workingTree)

        let comparisonTask = Task {
            try await provider.compareEndpoints(
                BridgeEndpointComparisonRequest(
                    query: makeBridgeReviewQuery(
                        baseEndpointId: baseEndpoint.endpointId,
                        headEndpointId: headEndpoint.endpointId
                    ),
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    reviewGeneration: 1
                )
            )
        }
        await readGate.waitUntilStarted()
        await timeoutScheduler.waitUntilScheduled()
        timeoutScheduler.fireScheduledTimeout()

        do {
            _ = try await comparisonTask.value
            Issue.record("Expected BridgeProviderFailure.providerFailed timeout")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .providerFailed(message: "Bridge Git data-plane read timed out"))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }

        await readGate.release()
    }
}

private actor NonCooperativeDiffAgentStudioGitClient: AgentStudioGitLocalClient {
    private let readGate: BridgeGitDataPlaneReadGate

    init(readGate: BridgeGitDataPlaneReadGate) {
        self.readGate = readGate
    }

    func repositoryIdentity(for worktreePath: URL) async throws(GitDataPlaneError) -> GitRepositoryIdentity {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func worktrees(for repositoryPath: URL) async throws(GitDataPlaneError) -> [GitWorktreeSnapshot] {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func validateWorktree(_ request: GitValidateWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeValidation
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func pruneStaleWorktree(_ request: GitPruneStaleWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreePruneResult
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func removeWorktree(_ request: GitRemoveWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeRemovalResult
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func lockWorktree(_ request: GitLockWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func unlockWorktree(_ request: GitUnlockWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func status(for worktreePath: URL, options: GitStatusOptions) async throws(GitDataPlaneError)
        -> GitStatusSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func branches(for repositoryPath: URL) async throws(GitDataPlaneError) -> [GitBranchSnapshot] {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func resolveRevision(_ request: GitRevisionResolutionRequest) async throws(GitDataPlaneError)
        -> GitResolvedRevision
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func readTree(_ request: GitTreeReadRequest) async throws(GitDataPlaneError) -> GitTreeSnapshot {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func diff(_ request: GitDiffRequest) async throws(GitDataPlaneError) -> GitDiffSnapshot {
        await readGate.recordStarted()
        await readGate.waitUntilReleased()
        return GitDiffSnapshot(files: [])
    }

    func content(_ request: GitContentRequest) async throws(GitDataPlaneError) -> GitContentPayload {
        throw GitDataPlaneError.unsupported(message: "not used")
    }
}

private final class ManualBridgeGitDataPlaneTimeoutScheduler: BridgeGitDataPlaneTimeoutScheduler,
    @unchecked Sendable
{
    private struct ScheduledTimeout {
        let id: Int
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var nextId = 0
    private var scheduledTimeouts: [ScheduledTimeout] = []
    private var scheduleWaiters: [CheckedContinuation<Void, Never>] = []

    func scheduleTimeout(
        after _: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> BridgeGitDataPlaneScheduledTimeout {
        let id: Int
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        id = nextId
        nextId += 1
        scheduledTimeouts.append(ScheduledTimeout(id: id, handler: handler))
        waiters = scheduleWaiters
        scheduleWaiters.removeAll(keepingCapacity: false)
        lock.unlock()

        for waiter in waiters {
            waiter.resume()
        }

        return BridgeGitDataPlaneScheduledTimeout { [weak self] in
            self?.cancelScheduledTimeout(id: id)
        }
    }

    func waitUntilScheduled() async {
        guard !hasScheduledTimeouts() else { return }

        await withCheckedContinuation { continuation in
            if !appendScheduleWaiterIfNeeded(continuation) {
                continuation.resume()
            }
        }
    }

    func fireScheduledTimeout() {
        let scheduledTimeout: ScheduledTimeout?
        lock.lock()
        scheduledTimeout = scheduledTimeouts.isEmpty ? nil : scheduledTimeouts.removeFirst()
        lock.unlock()

        scheduledTimeout?.handler()
    }

    private func cancelScheduledTimeout(id: Int) {
        lock.lock()
        scheduledTimeouts.removeAll { $0.id == id }
        lock.unlock()
    }

    private func hasScheduledTimeouts() -> Bool {
        lock.lock()
        let result = !scheduledTimeouts.isEmpty
        lock.unlock()
        return result
    }

    private func appendScheduleWaiterIfNeeded(_ waiter: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        guard scheduledTimeouts.isEmpty else {
            lock.unlock()
            return false
        }
        scheduleWaiters.append(waiter)
        lock.unlock()
        return true
    }
}

private actor BridgeGitDataPlaneReadGate {
    private var didStart = false
    private var didRelease = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStarted() {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilReleased() async {
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        didRelease = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }
}
