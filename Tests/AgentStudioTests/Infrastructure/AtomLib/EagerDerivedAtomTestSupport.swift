import Dispatch
import Foundation
import Observation
import Synchronization
import Testing

@testable import AgentStudioInfrastructure

final class EagerDerivedAtomTestSignal: Sendable {
    private struct State {
        var isSignaled = false
        var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    }

    private let state = Mutex(State())

    func signal() {
        let waiters = state.withLock { state -> [CheckedContinuation<Bool, Never>] in
            guard !state.isSignaled else { return [] }
            state.isSignaled = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: true)
        }
    }

    func wait() async -> Bool {
        let waiterID = UUIDv7.generate()
        return await withCheckedContinuation { continuation in
            let shouldResumeImmediately = state.withLock { state in
                if state.isSignaled {
                    return true
                }
                state.waiters[waiterID] = continuation
                return false
            }
            if shouldResumeImmediately {
                continuation.resume(returning: true)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5)) { [weak self] in
                let timedOutContinuation = self?.state.withLock { state in
                    state.waiters.removeValue(forKey: waiterID)
                }
                timedOutContinuation?.resume(returning: false)
            }
        }
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

final class EagerDerivedAtomConcurrencyTracker: Sendable {
    private struct State {
        var activeProjectionCount = 0
        var maximumConcurrentProjectionCount = 0
    }

    private let state = Mutex(State())

    var maximumConcurrentProjectionCount: Int {
        state.withLock(\.maximumConcurrentProjectionCount)
    }

    func projectionDidStart() {
        state.withLock { state in
            state.activeProjectionCount += 1
            state.maximumConcurrentProjectionCount = max(
                state.maximumConcurrentProjectionCount,
                state.activeProjectionCount
            )
        }
    }

    func projectionDidFinish() {
        state.withLock { state in
            precondition(state.activeProjectionCount > 0)
            state.activeProjectionCount -= 1
        }
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
    let concurrencyTracker: EagerDerivedAtomConcurrencyTracker?
    let observesCancellation: Bool
    let cancellationSignal: EagerDerivedAtomTestSignal?
}

func projectEagerDerivedAtomTestRequest(
    _ request: EagerDerivedAtomTestRequest
) throws(CancellationError) -> EagerDerivedAtomTestValue {
    request.projectionCount.increment()
    request.concurrencyTracker?.projectionDidStart()
    defer { request.concurrencyTracker?.projectionDidFinish() }
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
    concurrencyTracker: EagerDerivedAtomConcurrencyTracker? = nil,
    observesCancellation: Bool = false,
    cancellationSignal: EagerDerivedAtomTestSignal? = nil
) -> EagerDerivedAtomTestRequest {
    EagerDerivedAtomTestRequest(
        identity: identity,
        outputContent: outputContent,
        gate: gate,
        projectionCount: projectionCount,
        concurrencyTracker: concurrencyTracker,
        observesCancellation: observesCancellation,
        cancellationSignal: cancellationSignal
    )
}

typealias EagerDerivedAtomTestNode = EagerDerivedAtom<
    EagerDerivedAtomTestRequest,
    Int,
    EagerDerivedAtomTestRequest,
    EagerDerivedAtomTestValue,
    EagerDerivedAtomTestValue
>

final class EagerDerivedAtomCompletionRecorder: Sendable {
    private struct State {
        var completions: [EagerDerivedAtomTestNode.ProjectionCompletion] = []
        var waiters:
            [(
                expected: EagerDerivedAtomTestNode.ProjectionCompletion,
                signal: EagerDerivedAtomTestSignal
            )] = []
    }

    private let state = Mutex(State())

    func record(_ completion: EagerDerivedAtomTestNode.ProjectionCompletion) {
        let readySignals = state.withLock { state -> [EagerDerivedAtomTestSignal] in
            state.completions.append(completion)
            var readySignals: [EagerDerivedAtomTestSignal] = []
            state.waiters.removeAll { waiter in
                guard waiter.expected == completion else { return false }
                readySignals.append(waiter.signal)
                return true
            }
            return readySignals
        }
        for signal in readySignals {
            signal.signal()
        }
    }

    func wait(for expectedCompletion: EagerDerivedAtomTestNode.ProjectionCompletion) async -> Bool {
        let signal = state.withLock { state -> EagerDerivedAtomTestSignal? in
            guard !state.completions.contains(expectedCompletion) else {
                return nil
            }
            let signal = EagerDerivedAtomTestSignal()
            state.waiters.append((expectedCompletion, signal))
            return signal
        }
        guard let signal else { return true }
        return await signal.wait()
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
    completionRecorder: EagerDerivedAtomCompletionRecorder? = nil,
    combinePendingRequests:
        @escaping @Sendable (
            EagerDerivedAtomTestRequest,
            EagerDerivedAtomTestRequest
        ) -> EagerDerivedAtomTestRequest = { _, latestRequest in latestRequest }
) -> EagerDerivedAtomTestNode {
    EagerDerivedAtom(
        intentIdentity: \EagerDerivedAtomTestRequest.identity,
        combinePendingIntents: combinePendingRequests,
        prepare: { request, _ in .prepared(request) },
        project: projectEagerDerivedAtomTestRequest,
        classify: { candidate, currentValue in
            currentValue?.content == candidate.content
                ? .equalCurrent(candidate)
                : .immediateAccepted(candidate)
        },
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
