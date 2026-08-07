import Testing

@testable import AgentStudioInfrastructure

@MainActor
struct EagerDerivedAtomTests {
    @Test
    func initialPublicationStoresValueAndKeepsRevisionZero() async {
        let gate = EagerDerivedAtomProjectionGate()
        defer { gate.release() }
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
        guard
            await requireEagerDerivedAtomTestEvent(
                "initial projection start",
                wait: { await gate.waitUntilStarted() }
            )
        else { return }
        #expect(atom.freshness == .running(1))
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }

        gate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "initial value publication",
                wait: { await valueChanged.wait() }
            )
        else { return }

        #expect(atom.value?.content == 10)
        #expect(atom.freshness == .current(1))
        #expect(atom.revision == 0)
        #expect(projectionCount.count == 1)
    }

    @Test
    func equalCurrentRequestIsANoOp() async {
        let gate = EagerDerivedAtomProjectionGate()
        defer { gate.release() }
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()
        let request = makeEagerDerivedAtomTestRequest(
            identity: 1,
            outputContent: 10,
            gate: gate,
            projectionCount: projectionCount
        )

        atom.admit(request)
        guard
            await requireEagerDerivedAtomTestEvent(
                "equal request projection start",
                wait: { await gate.waitUntilStarted() }
            )
        else { return }
        atom.admit(request)

        #expect(atom.freshness == .running(1))
        #expect(projectionCount.count == 1)

        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        gate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "equal request initial publication",
                wait: { await valueChanged.wait() }
            )
        else { return }

        atom.admit(request)
        #expect(atom.freshness == .current(1))
        #expect(projectionCount.count == 1)
    }

    @Test
    func successorCancelsRetainedPredecessor() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
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
        guard
            await requireEagerDerivedAtomTestEvent(
                "predecessor projection start",
                wait: { await firstGate.waitUntilStarted() }
            )
        else { return }

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: secondGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "successor projection start",
                wait: { await secondGate.waitUntilStarted() }
            )
        else { return }
        firstGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "predecessor cancellation",
                wait: { await cancellationSignal.wait() }
            )
        else { return }

        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        secondGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "successor publication",
                wait: { await valueChanged.wait() }
            )
        else { return }

        #expect(atom.value?.content == 20)
        #expect(atom.freshness == .current(2))
        #expect(projectionCount.count == 2)
    }

    @Test
    func staleCompletionThatIgnoresCancellationCannotPublish() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
        let completionRecorder = EagerDerivedAtomCompletionRecorder()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode(completionRecorder: completionRecorder)

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "stale projection start",
                wait: { await firstGate.waitUntilStarted() }
            )
        else { return }
        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: secondGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "replacement projection start",
                wait: { await secondGate.waitUntilStarted() }
            )
        else { return }

        firstGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "stale completion admission decision",
                wait: { await completionRecorder.wait(for: .superseded(1)) }
            )
        else { return }

        #expect(atom.value == nil)
        #expect(atom.freshness == .running(2))
        #expect(atom.revision == 0)

        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        secondGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "replacement publication",
                wait: { await valueChanged.wait() }
            )
        else { return }

        #expect(atom.value?.content == 20)
        #expect(atom.freshness == .current(2))
    }

    @Test
    func equalCurrentCompletionPreservesValueRevisionAndOutputObservation() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "first equal-output projection start",
                wait: { await firstGate.waitUntilStarted() }
            )
        else { return }
        let firstValueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            firstValueChanged.signal()
        }
        firstGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "first equal-output publication",
                wait: { await firstValueChanged.wait() }
            )
        else { return }
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
        guard
            await requireEagerDerivedAtomTestEvent(
                "second equal-output projection start",
                wait: { await secondGate.waitUntilStarted() }
            )
        else { return }
        #expect(outputObservationCount.isEmpty)

        let freshnessChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomFreshness(atom) {
            freshnessChanged.signal()
        }
        secondGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "equal-output freshness publication",
                wait: { await freshnessChanged.wait() }
            )
        else { return }

        #expect(atom.value === firstValue)
        #expect(atom.freshness == .current(2))
        #expect(atom.revision == 0)
        #expect(outputObservationCount.isEmpty)
    }

    @Test
    func sourceInvalidationSynchronouslyRevokesWorkBeforeSuccessorAdmission() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        defer {
            firstGate.release()
            successorGate.release()
        }
        let completionRecorder = EagerDerivedAtomCompletionRecorder()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode(completionRecorder: completionRecorder)

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "invalidated projection start",
                wait: { await firstGate.waitUntilStarted() }
            )
        else { return }

        atom.sourceDidInvalidate()
        firstGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "invalidated completion admission decision",
                wait: { await completionRecorder.wait(for: .superseded(1)) }
            )
        else { return }

        #expect(atom.value == nil)
        #expect(atom.freshness != .current(1))

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 11,
                gate: successorGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "post-invalidation successor start",
                wait: { await successorGate.waitUntilStarted() }
            )
        else { return }
        let valueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            valueChanged.signal()
        }
        successorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "post-invalidation successor publication",
                wait: { await valueChanged.wait() }
            )
        else { return }

        #expect(atom.value?.content == 11)
        #expect(atom.freshness == .current(1))
        #expect(projectionCount.count == 2)
    }

    @Test
    func repeatedInvalidationKeepsOnlyTheStillStaleAdmissionInvalidated() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        defer {
            firstGate.release()
            successorGate.release()
        }
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode()

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: firstGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "repeated-invalidation initial projection start",
                wait: { await firstGate.waitUntilStarted() }
            )
        else { return }
        let firstValueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            firstValueChanged.signal()
        }
        firstGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "repeated-invalidation initial publication",
                wait: { await firstValueChanged.wait() }
            )
        else { return }

        let invalidated = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomFreshness(atom) {
            invalidated.signal()
        }
        atom.sourceDidInvalidate()
        atom.sourceDidInvalidate()
        guard
            await requireEagerDerivedAtomTestEvent(
                "repeated invalidation freshness",
                wait: { await invalidated.wait() }
            )
        else { return }
        #expect(atom.freshness == .invalidated(1))

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 11,
                gate: successorGate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "repeated-invalidation successor start",
                wait: { await successorGate.waitUntilStarted() }
            )
        else { return }
        #expect(atom.freshness == .running(1))

        let successorValueChanged = EagerDerivedAtomTestSignal()
        observeEagerDerivedAtomValue(atom) {
            successorValueChanged.signal()
        }
        successorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "repeated-invalidation successor publication",
                wait: { await successorValueChanged.wait() }
            )
        else { return }

        #expect(atom.value?.content == 11)
        #expect(atom.freshness == .current(1))
        #expect(atom.revision == 1)
    }

    @Test
    func stopBeforeCompletionPreventsPublication() async {
        let gate = EagerDerivedAtomProjectionGate()
        defer { gate.release() }
        let completionRecorder = EagerDerivedAtomCompletionRecorder()
        let projectionCount = EagerDerivedAtomTestCounter()
        let atom = makeEagerDerivedAtomTestNode(completionRecorder: completionRecorder)

        atom.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: gate,
                projectionCount: projectionCount
            ))
        guard
            await requireEagerDerivedAtomTestEvent(
                "stopped projection start",
                wait: { await gate.waitUntilStarted() }
            )
        else { return }

        atom.stop()
        #expect(atom.freshness == .stopped)
        gate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "stopped completion admission decision",
                wait: { await completionRecorder.wait(for: .cancelled(1)) }
            )
        else { return }

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
