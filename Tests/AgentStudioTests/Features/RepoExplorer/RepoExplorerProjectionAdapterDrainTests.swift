import Dispatch
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoExplorerProjectionDrainGate: Sendable {
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    init() {
        (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func hold() throws(CancellationError) {
        startedContinuation.yield()
        releaseSemaphore.wait()
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    func waitUntilStarted() async {
        for await _ in started {
            return
        }
    }

    func release() {
        releaseSemaphore.signal()
        startedContinuation.finish()
    }
}

@MainActor
@Suite("Repo Explorer projection adapter drain", .serialized)
struct RepoExplorerProjectionAdapterDrainTests {
    @Test("stop and drain awaits the detached projection and rejects late publication")
    func stopAndDrainAwaitsDetachedProjectionAndRejectsLatePublication() async {
        let gate = RepoExplorerProjectionDrainGate()
        let adapter = RepoExplorerProjectionAdapter(
            project: { _ throws(CancellationError) in
                try gate.hold()
                throw CancellationError()
            }
        )
        let host = registerProjectionTestMaterializationHost(adapter: adapter)
        defer { host.detach() }
        adapter.admit(makeProjectionIntentRequest(generation: 1))
        await gate.waitUntilStarted()

        adapter.stop()
        async let drain: Void = adapter.stopAndDrain()
        gate.release()
        await drain

        #expect(adapter.publishedResult == nil)
        #expect(adapter.materializedProjection == nil)
    }
}
