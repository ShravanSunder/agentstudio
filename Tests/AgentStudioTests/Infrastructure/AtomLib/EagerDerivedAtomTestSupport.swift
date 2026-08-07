import Dispatch
import Observation
import Synchronization
import Testing

@testable import AgentStudioInfrastructure

final class EagerDerivedAtomTestSignal: Sendable {
    private static let maximumYieldCount = 10_000
    private let isSignaled = Mutex(false)

    func signal() {
        isSignaled.withLock { isSignaled in
            isSignaled = true
        }
    }

    func wait() async -> Bool {
        for _ in 0..<Self.maximumYieldCount {
            if isSignaled.withLock({ $0 }) {
                return true
            }
            await Task.yield()
        }
        return isSignaled.withLock { $0 }
    }
}

final class EagerDerivedAtomProjectionGate: Sendable {
    private let startedSignal = EagerDerivedAtomTestSignal()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let hasReleased = Mutex(false)

    func holdProjection() throws(CancellationError) {
        startedSignal.signal()
        guard releaseSemaphore.wait(timeout: .now() + .seconds(5)) == .success else {
            throw CancellationError()
        }
    }

    func waitUntilStarted() async -> Bool {
        await startedSignal.wait()
    }

    func release() {
        let shouldSignal = hasReleased.withLock { hasReleased in
            guard !hasReleased else { return false }
            hasReleased = true
            return true
        }
        if shouldSignal {
            releaseSemaphore.signal()
        }
    }
}

final class EagerDerivedAtomTestCounter: Sendable {
    private let countState = Mutex(0)

    var count: Int {
        countState.withLock { $0 }
    }

    var isEmpty: Bool {
        countState.withLock { $0 == 0 }
    }

    func increment() {
        countState.withLock { $0 += 1 }
    }
}

final class EagerDerivedAtomTestValue: Sendable {
    let content: Int

    init(content: Int) {
        self.content = content
    }
}

struct EagerDerivedAtomTestRequest: Sendable {
    let identity: Int
    let outputContent: Int
    let gate: EagerDerivedAtomProjectionGate?
    let projectionCount: EagerDerivedAtomTestCounter
    let observesCancellation: Bool
    let cancellationSignal: EagerDerivedAtomTestSignal?
}

func projectEagerDerivedAtomTestRequest(
    _ request: EagerDerivedAtomTestRequest
) throws(CancellationError) -> EagerDerivedAtomTestValue {
    request.projectionCount.increment()
    try request.gate?.holdProjection()
    if request.observesCancellation, Task.isCancelled {
        request.cancellationSignal?.signal()
        throw CancellationError()
    }
    return EagerDerivedAtomTestValue(content: request.outputContent)
}

func makeEagerDerivedAtomTestRequest(
    identity: Int,
    outputContent: Int,
    gate: EagerDerivedAtomProjectionGate? = nil,
    projectionCount: EagerDerivedAtomTestCounter,
    observesCancellation: Bool = false,
    cancellationSignal: EagerDerivedAtomTestSignal? = nil
) -> EagerDerivedAtomTestRequest {
    EagerDerivedAtomTestRequest(
        identity: identity,
        outputContent: outputContent,
        gate: gate,
        projectionCount: projectionCount,
        observesCancellation: observesCancellation,
        cancellationSignal: cancellationSignal
    )
}

typealias EagerDerivedAtomTestNode = EagerDerivedAtom<
    EagerDerivedAtomTestRequest,
    Int,
    EagerDerivedAtomTestValue
>

final class EagerDerivedAtomCompletionRecorder: Sendable {
    private let completions = Mutex<[EagerDerivedAtomTestNode.ProjectionCompletion]>([])

    func record(_ completion: EagerDerivedAtomTestNode.ProjectionCompletion) {
        completions.withLock { $0.append(completion) }
    }

    func wait(for expectedCompletion: EagerDerivedAtomTestNode.ProjectionCompletion) async -> Bool {
        for _ in 0..<10_000 {
            if completions.withLock({ $0.contains(expectedCompletion) }) {
                return true
            }
            await Task.yield()
        }
        return completions.withLock { $0.contains(expectedCompletion) }
    }
}

@MainActor
func requireEagerDerivedAtomTestEvent(
    _ description: String,
    wait: () async -> Bool
) async -> Bool {
    let didObserveEvent = await wait()
    if !didObserveEvent {
        Issue.record("Timed out waiting for \(description)")
    }
    return didObserveEvent
}

@MainActor
func makeEagerDerivedAtomTestNode(
    completionRecorder: EagerDerivedAtomCompletionRecorder? = nil
) -> EagerDerivedAtomTestNode {
    EagerDerivedAtom(
        requestIdentity: \EagerDerivedAtomTestRequest.identity,
        isValueEqual: { lhs, rhs in lhs.content == rhs.content },
        project: projectEagerDerivedAtomTestRequest,
        onProjectionCompletion: { completion in
            completionRecorder?.record(completion)
        }
    )
}

@MainActor
func observeEagerDerivedAtomValue(
    _ atom: EagerDerivedAtomTestNode,
    onChange: @escaping @Sendable () -> Void
) {
    withObservationTracking {
        _ = atom.value
    } onChange: {
        onChange()
    }
}

@MainActor
func observeEagerDerivedAtomFreshness(
    _ atom: EagerDerivedAtomTestNode,
    onChange: @escaping @Sendable () -> Void
) {
    withObservationTracking {
        _ = atom.freshness
    } onChange: {
        onChange()
    }
}
