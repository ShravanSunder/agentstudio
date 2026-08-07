import Dispatch
import Observation
import Synchronization
import Testing

@testable import AgentStudioInfrastructure

private final class EagerDerivedAtomTestSignal: Sendable {
    private struct State: Sendable {
        var isSignaled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func signal() {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
            guard !state.isSignaled else { return [] }
            state.isSignaled = true
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                guard !state.isSignaled else { return true }
                state.waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }
}

private final class EagerDerivedAtomProjectionGate: Sendable {
    private let startedSignal = EagerDerivedAtomTestSignal()
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func holdProjection() {
        startedSignal.signal()
        releaseSemaphore.wait()
    }

    func waitUntilStarted() async {
        await startedSignal.wait()
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private final class EagerDerivedAtomTestCounter: Sendable {
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

private final class EagerDerivedAtomTestValue: Sendable {
    let content: Int
    private let droppedSignal: EagerDerivedAtomTestSignal?

    init(content: Int, droppedSignal: EagerDerivedAtomTestSignal? = nil) {
        self.content = content
        self.droppedSignal = droppedSignal
    }

    deinit {
        droppedSignal?.signal()
    }
}

private struct EagerDerivedAtomTestRequest: Sendable {
    let identity: Int
    let outputContent: Int
    let gate: EagerDerivedAtomProjectionGate?
    let projectionCount: EagerDerivedAtomTestCounter
    let observesCancellation: Bool
    let cancellationSignal: EagerDerivedAtomTestSignal?
    let droppedValueSignal: EagerDerivedAtomTestSignal?
}

private func projectEagerDerivedAtomTestRequest(
    _ request: EagerDerivedAtomTestRequest
) throws(CancellationError) -> EagerDerivedAtomTestValue {
    request.projectionCount.increment()
    request.gate?.holdProjection()
    if request.observesCancellation, Task.isCancelled {
        request.cancellationSignal?.signal()
        throw CancellationError()
    }
    return EagerDerivedAtomTestValue(
        content: request.outputContent,
        droppedSignal: request.droppedValueSignal
    )
}

private func makeEagerDerivedAtomTestRequest(
    identity: Int,
    outputContent: Int,
    gate: EagerDerivedAtomProjectionGate? = nil,
    projectionCount: EagerDerivedAtomTestCounter,
    observesCancellation: Bool = false,
    cancellationSignal: EagerDerivedAtomTestSignal? = nil,
    droppedValueSignal: EagerDerivedAtomTestSignal? = nil
) -> EagerDerivedAtomTestRequest {
    EagerDerivedAtomTestRequest(
        identity: identity,
        outputContent: outputContent,
        gate: gate,
        projectionCount: projectionCount,
        observesCancellation: observesCancellation,
        cancellationSignal: cancellationSignal,
        droppedValueSignal: droppedValueSignal
    )
}

@MainActor
private func makeEagerDerivedAtomTestNode() -> EagerDerivedAtom<
    EagerDerivedAtomTestRequest,
    Int,
    EagerDerivedAtomTestValue
> {
    EagerDerivedAtom(
        requestIdentity: \EagerDerivedAtomTestRequest.identity,
        isValueEqual: { lhs, rhs in lhs.content == rhs.content },
        project: projectEagerDerivedAtomTestRequest
    )
}

@MainActor
private func observeEagerDerivedAtomValue(
    _ atom: EagerDerivedAtom<EagerDerivedAtomTestRequest, Int, EagerDerivedAtomTestValue>,
    onChange: @escaping @Sendable () -> Void
) {
    withObservationTracking {
        _ = atom.value
    } onChange: {
        onChange()
    }
}

@MainActor
private func observeEagerDerivedAtomFreshness(
    _ atom: EagerDerivedAtom<EagerDerivedAtomTestRequest, Int, EagerDerivedAtomTestValue>,
    onChange: @escaping @Sendable () -> Void
) {
    withObservationTracking {
        _ = atom.freshness
    } onChange: {
        onChange()
    }
}

@MainActor
struct EagerDerivedAtomTests {
    @Test
    func initialPublicationStoresValueAndKeepsRevisionZero() async {
        let gate = EagerDerivedAtomProjectionGate()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()
        let valueChanged = EagerDerivedAtomTestSignal()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: gate,
                projectionCount: projectionCount
            ))
        await gate.waitUntilStarted()
        #expect(atom.freshness == .running(1))
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }

        gate.release()
        await valueChanged.wait()

        #expect(atom.value?.content == 10)
        #expect(atom.freshness == .current(1))
        #expect(atom.revision == 0)
        #expect(projectionCount.count == 1)
    }

    @Test
    func equalCurrentRequestIsANoOp() async {
        let gate = EagerDerivedAtomProjectionGate()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()
        let request = makeEagerDerivedAtomTestRequest(
            identity: 1,
            outputContent: 10,
            gate: gate,
            projectionCount: projectionCount
        )

        atom.admit(request)
        await gate.waitUntilStarted()
        atom.admit(request)

        #expect(atom.freshness == .running(1))
        #expect(projectionCount.count == 1)

        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        gate.release()
        await valueChanged.wait()

        atom.admit(request)
        #expect(atom.freshness == .current(1))
        #expect(projectionCount.count == 1)
    }

    @Test
    func successorCancelsRetainedPredecessor() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        let cancellationSignal = EagerDerivedAtomTestSignal()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount,
                observesCancellation: true,
                cancellationSignal: cancellationSignal
            ))
        await firstGate.waitUntilStarted()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: secondGate,
                projectionCount: projectionCount
            ))
        await secondGate.waitUntilStarted()
        firstGate.release()
        await cancellationSignal.wait()

        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        secondGate.release()
        await valueChanged.wait()

        #expect(atom.value?.content == 20)
        #expect(atom.freshness == .current(2))
        #expect(projectionCount.count == 2)
    }

    @Test
    func staleCompletionThatIgnoresCancellationCannotPublish() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        let staleValueDropped = EagerDerivedAtomTestSignal()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount,
                droppedValueSignal: staleValueDropped
            ))
        await firstGate.waitUntilStarted()
        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: secondGate,
                projectionCount: projectionCount
            ))
        await secondGate.waitUntilStarted()

        firstGate.release()
        await staleValueDropped.wait()

        #expect(atom.value == nil)
        #expect(atom.freshness == .running(2))
        #expect(atom.revision == 0)

        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        secondGate.release()
        await valueChanged.wait()

        #expect(atom.value?.content == 20)
        #expect(atom.freshness == .current(2))
    }

    @Test
    func equalCurrentCompletionPreservesValueRevisionAndOutputObservation() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount
            ))
        await firstGate.waitUntilStarted()
        let firstValueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            firstValueChanged.signal()
        }
        firstGate.release()
        await firstValueChanged.wait()
        let firstValue = atom.value

        let outputObservationCount = EagerDerivedAtomTestCounter()
        observeEagerDerivedAtomValue(atom) {
            outputObservationCount.increment()
        }
        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 10,
                gate: secondGate,
                projectionCount: projectionCount
            ))
        await secondGate.waitUntilStarted()
        #expect(outputObservationCount.isEmpty)

        let freshnessChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomFreshness(atom) {
            freshnessChanged.signal()
        }
        secondGate.release()
        await freshnessChanged.wait()

        #expect(atom.value === firstValue)
        #expect(atom.freshness == .current(2))
        #expect(atom.revision == 0)
        #expect(outputObservationCount.isEmpty)
    }

    @Test
    func sourceInvalidationSynchronouslyRevokesWorkBeforeSuccessorAdmission() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        let staleValueDropped = EagerDerivedAtomTestSignal()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount,
                droppedValueSignal: staleValueDropped
            ))
        await firstGate.waitUntilStarted()

        atom.sourceDidInvalidate()
        firstGate.release()
        await staleValueDropped.wait()

        #expect(atom.value == nil)
        #expect(atom.freshness != .current(1))

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 11,
                gate: successorGate,
                projectionCount: projectionCount
            ))
        await successorGate.waitUntilStarted()
        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        successorGate.release()
        await valueChanged.wait()

        #expect(atom.value?.content == 11)
        #expect(atom.freshness == .current(1))
        #expect(projectionCount.count == 2)
    }

    @Test
    func repeatedInvalidationKeepsOnlyTheStillStaleAdmissionInvalidated() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount
            ))
        await firstGate.waitUntilStarted()
        let firstValueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            firstValueChanged.signal()
        }
        firstGate.release()
        await firstValueChanged.wait()

        let invalidated = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomFreshness(atom) {
            invalidated.signal()
        }
        atom.sourceDidInvalidate()
        atom.sourceDidInvalidate()
        await invalidated.wait()
        #expect(atom.freshness == .invalidated(1))

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 11,
                gate: successorGate,
                projectionCount: projectionCount
            ))
        await successorGate.waitUntilStarted()
        #expect(atom.freshness == .running(1))

        let successorValueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            successorValueChanged.signal()
        }
        successorGate.release()
        await successorValueChanged.wait()

        #expect(atom.value?.content == 11)
        #expect(atom.freshness == .current(1))
        #expect(atom.revision == 1)
    }

    @Test
    func stopBeforeCompletionPreventsPublication() async {
        let gate = EagerDerivedAtomProjectionGate()
        let droppedValueSignal = EagerDerivedAtomTestSignal()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: gate,
                projectionCount: projectionCount,
                droppedValueSignal: droppedValueSignal
            ))
        await gate.waitUntilStarted()

        atom.stop()
        #expect(atom.freshness == .stopped)
        gate.release()
        await droppedValueSignal.wait()

        #expect(atom.value == nil)
        #expect(atom.freshness == .stopped)
        #expect(atom.revision == 0)
    }

    @Test
    func repeatedStopIsIdempotent() {
        let atom = makeEagerDerivedAtomTestNode()

        atom.stop()
        atom.stop()

        #expect(atom.value == nil)
        #expect(atom.freshness == .stopped)
        #expect(atom.revision == 0)
    }

    @Test
    func admissionAfterStopIsRejected() {
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()
        atom.stop()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                projectionCount: projectionCount
            ))

        #expect(projectionCount.isEmpty)
        #expect(atom.value == nil)
        #expect(atom.freshness == .stopped)
        #expect(atom.revision == 0)
    }
}
