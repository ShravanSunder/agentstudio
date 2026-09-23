import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioCore

/// Guards the owner's rule that the terminated-stream join must not loosen:
/// one viewer, one session. A fresh `.initial` bootstrap while the first stream
/// is genuinely still live is refused immediately, with no waiting.
///
/// Nothing asserted `.sessionAlreadyOpen` anywhere before this suite, so the rule
/// was protected only by the code that implements it.
@MainActor
@Suite(
    "Bridge development product host bootstrap admission",
    .serialized,
    .timeLimit(.minutes(1))
)
struct BridgeDevelopmentHostBootstrapAdmissionTests {
    @Test("a live metadata stream refuses a fresh initial bootstrap")
    func liveMetadataStreamRefusesAFreshInitialBootstrap() async throws {
        // Arrange
        let repositoryURL = try await FilesystemTestGitRepo.create(
            named: "bridge-development-host-bootstrap-admission-live"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        let host = try await BridgeDevelopmentProductHost(
            source: makeDevelopmentProductSource(worktreeRoot: repositoryURL),
            contributionTargetCommit: developmentContributionTargetCommit(
                worktreeRoot: repositoryURL
            )
        )
        let bootstrapRequest = try developmentDisplayBootstrapRequest(
            reason: "initial",
            surface: "file"
        )
        let firstWorker = try DevelopmentDisplayWorkerClient(
            host: host,
            delivery: await host.issueBootstrap(for: bootstrapRequest)
        )
        try await firstWorker.openSession()
        var firstMetadataStream = try firstWorker.startMetadataStream()
        try await firstMetadataStream.requireOpeningFrameAndAcknowledge(using: firstWorker)

        // Act — the stream is NOT stopped, so its scheme task is still live.
        var refusedError: BridgeDevelopmentProductHostError?
        do {
            _ = try await host.issueBootstrap(for: bootstrapRequest)
        } catch let error as BridgeDevelopmentProductHostError {
            refusedError = error
        }

        // Assert — refused, and refused for the right reason.
        #expect(refusedError == .sessionAlreadyOpen)

        await firstMetadataStream.stop()
    }

    @Test("a terminated stream's pending retirement joins instead of refusing")
    func terminatedStreamPendingRetirementJoinsInsteadOfRefusing() async throws {
        // Arrange — the census observer holds the reply task's cancellation at
        // exactly the point where the stream is recorded terminated and its
        // retirement has not been written. Without the fix the bootstrap gate
        // sees "a lease with no retirement" and refuses.
        let repositoryURL = try await FilesystemTestGitRepo.create(
            named: "bridge-development-host-bootstrap-admission-join"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        let terminationHold = BridgeSchemeTaskTerminationHold()
        let host = try await BridgeDevelopmentProductHost(
            source: makeDevelopmentProductSource(worktreeRoot: repositoryURL),
            contributionTargetCommit: developmentContributionTargetCommit(
                worktreeRoot: repositoryURL
            ),
            makeReviewProvider: { repositoryPath, gitReadContext in
                BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repositoryPath,
                    gitReadContext: gitReadContext,
                    statusPhysicalGate: AgentStudioGitStatusPhysicalGate()
                )
            },
            schemeTaskCensus: BridgeProductSchemeTaskCensus { _ in
                await terminationHold.holdUntilReleased()
            }
        )
        let bootstrapRequest = try developmentDisplayBootstrapRequest(
            reason: "initial",
            surface: "file"
        )
        let firstDelivery = try await host.issueBootstrap(for: bootstrapRequest)
        let firstWorker = try DevelopmentDisplayWorkerClient(host: host, delivery: firstDelivery)
        try await firstWorker.openSession()
        var firstMetadataStream = try firstWorker.startMetadataStream()
        try await firstMetadataStream.requireOpeningFrameAndAcknowledge(using: firstWorker)

        // Act — stop the stream, then wait for the hold to be ENTERED. At that
        // instant the census says terminated and no retirement is recorded.
        await firstMetadataStream.stop()
        await terminationHold.waitUntilEntered()

        let bootstrap = Task { try await host.issueBootstrap(for: bootstrapRequest) }
        await terminationHold.release()

        // Assert — it joined the retirement rather than refusing it, and the
        // successor is a new worker on the same pane session.
        let bootstrapDelivery = try await bootstrap.value
        let secondWorker = try DevelopmentDisplayWorkerClient(
            host: host,
            delivery: bootstrapDelivery
        )
        #expect(secondWorker.paneSessionId == firstWorker.paneSessionId)
        #expect(secondWorker.workerInstanceId != firstWorker.workerInstanceId)
    }
}

/// Holds a scheme task's cancellation open so a test can observe the window
/// between "stream terminated" and "retirement recorded". Event-driven on both
/// sides: no sleeping, no polling.
private actor BridgeSchemeTaskTerminationHold {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func holdUntilReleased() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
