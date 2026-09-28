import AgentStudioTestHarness
import Testing

private enum SpikeFact: Sendable, Equatable {
    case actorEmitted
    case mainActorEmitted
    case otherClose
}

private actor SpikeActorProducer {
    private let sink: @Sendable (String, SpikeFact) -> Void

    init(sink: @escaping @Sendable (String, SpikeFact) -> Void) {
        self.sink = sink
    }

    func emit() {
        sink("spike", .actorEmitted)
    }
}

@MainActor
private final class SpikeMainActorCallback {
    private let sink: @Sendable (String, SpikeFact) -> Void

    init(sink: @escaping @Sendable (String, SpikeFact) -> Void) {
        self.sink = sink
    }

    func emit() {
        sink("spike", .mainActorEmitted)
    }
}

private struct LossReportingHandle: FactSourceHandle {
    let reportLoss: @Sendable () -> Void

    func stop() async {
        reportLoss()
    }

    func settleEnqueued() async {}
}

private struct HeldSettlementHandle: FactSourceHandle {
    let step: HeldStep<Void>

    func stop() async {}

    func settleEnqueued() async {
        try? await step.arrive(())
    }
}

@Suite("FactRecorder")
struct FactRecorderTests {
    @Test("a second attachment fails with a typed misuse error")
    func secondAttachFails() throws {
        let source = makeSource()
        _ = try source.attach()

        #expect(throws: FactSourceAlreadyAttached.self) {
            _ = try source.attach()
        }
    }

    @Test("mark waits for accepted source work before capturing its opening position")
    func markWaitsForSourceSettlement() async throws {
        let recorder = FactRecorder(
            vocabulary: FactVocabulary<String, SpikeFact>(
                describeScope: { $0 },
                describeFact: { String(describing: $0) },
                isClosing: { _, fact in fact == .mainActorEmitted }
            )
        )
        let step = HeldStep<Void>("mark source settlement")
        recorder.installSourceHandle(HeldSettlementHandle(step: step))
        let marking = Task { await recorder.mark("scope") }
        _ = try await step.firstArrival()
        recorder.append(scope: "scope", fact: .actorEmitted)
        step.release()
        let opening = await marking.value
        recorder.append(scope: "scope", fact: .mainActorEmitted)

        try await recorder.expectNone(
            of: { $0 == .actorEmitted }, "actor fact", from: opening,
            closedBy: { $0 == .mainActorEmitted }
        )
        try await recorder.finish()
    }
    private func makeSource() -> LocalFactSource<String, SpikeFact> {
        LocalFactSource(
            vocabulary: FactVocabulary(
                describeScope: { $0 },
                describeFact: { String(describing: $0) },
                isClosing: { _, fact in fact == .mainActorEmitted || fact == .otherClose }
            )
        )
    }

    @Test("actor and MainActor producers synchronously feed one sink in emission order")
    @MainActor
    func actorAndMainActorSinkSpike() async throws {
        let source = LocalFactSource(
            vocabulary: FactVocabulary<String, SpikeFact>(
                describeScope: { $0 },
                describeFact: { String(describing: $0) },
                isClosing: { _, _ in false }
            )
        )
        let recorder = try source.attach()
        let actorProducer = SpikeActorProducer(sink: source.sink)
        let mainActorCallback = SpikeMainActorCallback(sink: source.sink)

        await actorProducer.emit()
        mainActorCallback.emit()

        try await recorder.expectNext(in: "spike", .actorEmitted)
        try await recorder.expectNext(in: "spike", .mainActorEmitted)
        try await recorder.finish()
    }

    @Test("facts emitted before expectations stay ordered and scopes remain independent")
    func bufferedFactsAndScopes() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.sink("first", .actorEmitted)
        source.sink("second", .actorEmitted)
        source.sink("first", .mainActorEmitted)

        try await recorder.expectNext(in: "second", .actorEmitted)
        try await recorder.expectNext(in: "first", .actorEmitted)
        try await recorder.expectNext(in: "first", .mainActorEmitted)
        try await recorder.finish()
    }

    @Test("an unexpected next fact fails without searching for a later match")
    func unexpectedFactIsNotRescued() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.sink("scope", .actorEmitted)
        source.sink("scope", .mainActorEmitted)

        await #expect(throws: UnexpectedFact.self) {
            try await recorder.expectNext(in: "scope", .mainActorEmitted)
        }
        try await recorder.finish()
    }

    @Test("normal end retains buffered facts and fails an outstanding expectation")
    func endAfterBufferedFacts() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.sink("scope", .actorEmitted)
        source.end()

        try await recorder.expectNext(in: "scope", .actorEmitted)
        await #expect(throws: SourceEnded.self) {
            try await recorder.expectNext(in: "scope", .mainActorEmitted)
        }
        try await recorder.finish()
    }

    @Test("normal end settles an already registered expectation")
    func endSettlesOutstandingExpectation() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        await withTaskGroup(of: Result<Void, any Error>.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        try await recorder.expectNext(in: "scope", .actorEmitted)
                        return .success(())
                    } catch { return .failure(error) }
                }
            }
            guard let misuse = await group.next() else {
                Issue.record("no expectation registered")
                return
            }
            if case .failure(let error) = misuse {
                #expect(error is ConcurrentExpectation)
            } else {
                Issue.record("an expectation completed without a fact")
            }
            source.end()
            guard let ended = await group.next() else {
                Issue.record("outstanding expectation did not settle")
                return
            }
            if case .failure(let error) = ended {
                #expect(error is SourceEnded)
            } else {
                Issue.record("ended expectation completed successfully")
            }
        }
        try await recorder.finish()
    }

    @Test("loss before a matching close stays sticky")
    func lossBeforeClose() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.lose("dropped")
        source.sink("scope", .mainActorEmitted)

        await #expect(throws: FactsLost.self) {
            try await recorder.expectNext(in: "scope", .mainActorEmitted)
        }
        await #expect(throws: FactsLost.self) { try await recorder.finish() }
    }

    @Test("finish checks loss reported while the source is stopping")
    func lossDuringStop() async throws {
        let recorder = FactRecorder(
            vocabulary: FactVocabulary<String, SpikeFact>(
                describeScope: { $0 },
                describeFact: { String(describing: $0) },
                isClosing: { _, fact in fact == .mainActorEmitted }
            )
        )
        recorder.installSourceHandle(
            LossReportingHandle(reportLoss: { recorder.receive(.lost(description: "drop at stop")) }))

        await #expect(throws: FactsLost.self) { try await recorder.finish() }
    }

    @Test("a forbidden fact already in the marked interval fails")
    func forbiddenBeforeNegativeExpectation() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        let opening = await recorder.mark("scope")
        source.sink("scope", .actorEmitted)
        source.sink("scope", .mainActorEmitted)

        await #expect(throws: UnexpectedFact.self) {
            try await recorder.expectNone(
                of: { $0 == .actorEmitted }, "actor fact", from: opening,
                closedBy: { $0 == .mainActorEmitted }
            )
        }
        try await recorder.finish()
    }

    @Test("the expected closing fact ends a negative interval")
    func negativeIntervalCloses() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        let opening = await recorder.mark("scope")
        source.sink("scope", .actorEmitted)
        source.sink("scope", .mainActorEmitted)

        try await recorder.expectNone(
            of: { $0 == .otherClose }, "other close", from: opening,
            closedBy: { $0 == .mainActorEmitted }
        )
        try await recorder.finish()
    }

    @Test("a different closing disposition cannot close the negative interval")
    func wrongCloseFails() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        let opening = await recorder.mark("scope")
        source.sink("scope", .otherClose)

        await #expect(throws: UnexpectedFact.self) {
            try await recorder.expectNone(
                of: { $0 == .actorEmitted }, "actor fact", from: opening,
                closedBy: { $0 == .mainActorEmitted }
            )
        }
        try await recorder.finish()
    }

    @Test("a close in another scope cannot finish the selected interval")
    func otherScopeCloseDoesNotCount() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        let opening = await recorder.mark("generation-1")
        source.sink("generation-2", .mainActorEmitted)
        source.end()

        await #expect(throws: SourceEnded.self) {
            try await recorder.expectNone(
                of: { $0 == .actorEmitted }, "actor fact", from: opening,
                closedBy: { $0 == .mainActorEmitted }
            )
        }
        try await recorder.finish()
    }

    @Test("mark linearizes before a held concurrent producer appends")
    func markBeforeHeldAppend() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        let step = HeldStep<Void>("before sink append")
        let producer = Task {
            try await step.arrive(())
            source.sink("scope", .actorEmitted)
            source.sink("scope", .mainActorEmitted)
        }
        _ = try await step.firstArrival()
        let opening = await recorder.mark("scope")
        step.release()
        try await producer.value

        await #expect(throws: UnexpectedFact.self) {
            try await recorder.expectNone(
                of: { $0 == .actorEmitted }, "actor fact", from: opening,
                closedBy: { $0 == .mainActorEmitted }
            )
        }
        try await recorder.finish()
    }

    @Test("source cancellation is distinct from normal end")
    func cancelledSource() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.cancel()

        await #expect(throws: Cancelled.self) {
            try await recorder.expectNext(in: "scope", .actorEmitted)
        }
        try await recorder.finish()
    }

    @Test("an expectation cancelled before registration settles without a source fact")
    func cancellationBeforeRegistration() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        let step = HeldStep<Void>("before expectation", cancellation: .holdThroughCancellation)
        let waiting = Task {
            try await step.arrive(())
            try await recorder.expectNext(in: "scope", .actorEmitted)
        }
        _ = try await step.firstArrival()
        waiting.cancel()
        step.release()

        await #expect(throws: CancellationError.self) { try await waiting.value }
        try await recorder.finish()
    }

    @Test("one of two concurrent expectations fails misuse, then the registered one cancels")
    func concurrentExpectationAndCancellationAfterRegistration() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        await withTaskGroup(of: Result<Void, any Error>.self) { group in
            group.addTask {
                do {
                    try await recorder.expectNext(in: "scope", .actorEmitted)
                    return .success(())
                } catch { return .failure(error) }
            }
            group.addTask {
                do {
                    try await recorder.expectNext(in: "scope", .actorEmitted)
                    return .success(())
                } catch { return .failure(error) }
            }

            guard let misuse = await group.next() else {
                Issue.record("two expectations produced no result")
                return
            }
            if case .failure(let error) = misuse {
                #expect(error is ConcurrentExpectation)
            } else {
                Issue.record("an expectation completed without a source fact")
            }
            group.cancelAll()
            guard let cancelled = await group.next() else {
                Issue.record("registered expectation did not settle")
                return
            }
            if case .failure(let error) = cancelled {
                #expect(error is CancellationError)
            } else {
                Issue.record("cancelled expectation completed successfully")
            }
        }
        try await recorder.finish()
    }

    @Test("a duplicate close is reported at finish")
    func duplicateClose() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.sink("scope", .mainActorEmitted)
        source.sink("scope", .mainActorEmitted)

        await #expect(throws: DuplicateClose.self) { try await recorder.finish() }
    }

    @Test("a fact after a close is reported at finish")
    func factAfterClose() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.sink("scope", .mainActorEmitted)
        source.sink("scope", .actorEmitted)

        await #expect(throws: FactAfterClose.self) { try await recorder.finish() }
    }

    @Test("a terminal violation in one scope does not hide another scope's next fact")
    func terminalViolationStaysScopedDuringConsumption() async throws {
        let source = makeSource()
        let recorder = try source.attach()
        source.sink("broken", .mainActorEmitted)
        source.sink("broken", .actorEmitted)
        source.sink("healthy", .actorEmitted)

        try await recorder.expectNext(in: "healthy", .actorEmitted)
        await #expect(throws: FactAfterClose.self) { try await recorder.finish() }
    }

    @Test("finish stops an endless local source and is idempotent")
    func finishStopsSource() async throws {
        let source = makeSource()
        let recorder = try source.attach()

        try await recorder.finish()
        try await recorder.finish()
        source.sink("scope", .actorEmitted)
        await #expect(throws: SourceEnded.self) {
            try await recorder.expectNext(in: "scope", .actorEmitted)
        }
    }
}
