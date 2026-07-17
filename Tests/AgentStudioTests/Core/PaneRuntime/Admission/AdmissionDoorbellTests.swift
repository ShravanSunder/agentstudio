import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission Doorbell")
struct AdmissionDoorbellTests {
    @Test("many signals coalesce into one pending payload-free wake")
    func manySignalsCoalesceIntoOnePendingWake() async {
        let doorbell = AdmissionDoorbell()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort

        signaler.signal()
        signaler.signal()
        signaler.signal()

        #expect(lifecycle.stateSnapshot == .signalPending)
        #expect(await consumer.nextSignal() == .signaled)
        #expect(lifecycle.stateSnapshot == .idle)
        lifecycle.finish()
    }

    @Test("signal resumes the single long-lived consumer")
    func signalResumesConsumer() async {
        let doorbell = AdmissionDoorbell()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort

        async let result = consumer.nextSignal()
        #expect(await waitForDoorbellState(.consumerWaiting, lifecycle: lifecycle))
        signaler.signal()

        #expect(await result == .signaled)
        #expect(lifecycle.stateSnapshot == .idle)
        lifecycle.finish()
    }

    @Test("finish wakes a waiter and permanently dominates pending and later signals")
    func finishIsExactAndTerminal() async {
        let doorbell = AdmissionDoorbell()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort

        async let waitingResult = consumer.nextSignal()
        #expect(await waitForDoorbellState(.consumerWaiting, lifecycle: lifecycle))
        lifecycle.finish()

        #expect(await waitingResult == .finished)
        signaler.signal()
        lifecycle.finish()
        #expect(await consumer.nextSignal() == .finished)
        #expect(await consumer.nextSignal() == .finished)
        #expect(lifecycle.stateSnapshot == .finished)
    }

    @Test("finish discards an unconsumed level signal")
    func finishDiscardsPendingSignal() async {
        let doorbell = AdmissionDoorbell()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort

        signaler.signal()
        #expect(lifecycle.stateSnapshot == .signalPending)
        lifecycle.finish()

        #expect(await consumer.nextSignal() == .finished)
        #expect(lifecycle.stateSnapshot == .finished)
    }

    @Test("concurrent signals preserve capacity one")
    func concurrentSignalsPreserveCapacityOne() async {
        let doorbell = AdmissionDoorbell()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort
        let signalCount = 256

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<signalCount {
                group.addTask {
                    signaler.signal()
                }
            }
        }

        #expect(lifecycle.stateSnapshot == .signalPending)
        #expect(await consumer.nextSignal() == .signaled)
        #expect(lifecycle.stateSnapshot == .idle)
        lifecycle.finish()
    }

    @Test("consumer cancellation revokes only its waiter and preserves replacement signaling")
    func consumerCancellationPermitsReplacementWait() async {
        let (doorbell, consumerRegistration) = makeDoorbellWithRegistrationAcknowledgement()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort
        let cancelledWaiter = Task {
            await consumer.nextSignal()
        }

        var registrationIterator = consumerRegistration.makeAsyncIterator()
        #expect(await registrationIterator.next() != nil)
        #expect(lifecycle.stateSnapshot == .consumerWaiting)
        cancelledWaiter.cancel()
        #expect(await cancelledWaiter.value == .finished)
        #expect(lifecycle.stateSnapshot == .idle)

        async let replacementResult = consumer.nextSignal()
        signaler.signal()

        #expect(await replacementResult == .signaled)
        #expect(lifecycle.stateSnapshot == .idle)
        lifecycle.finish()
    }

    @Test("pre-cancelled wait registration preserves an existing pending signal")
    func preCancelledWaitPreservesPendingSignal() async {
        let doorbell = AdmissionDoorbell()
        let signaler = doorbell.signalerPort
        let consumer = doorbell.consumerPort
        let lifecycle = doorbell.lifecyclePort
        let startGate = AsyncStream<Void>.makeStream()
        let cancelledConsumer = Task {
            for await _ in startGate.stream {
                break
            }
            return await consumer.nextSignal()
        }

        signaler.signal()
        cancelledConsumer.cancel()
        startGate.continuation.yield()
        startGate.continuation.finish()

        #expect(await cancelledConsumer.value == .finished)
        #expect(lifecycle.stateSnapshot == .signalPending)
        #expect(await consumer.nextSignal() == .signaled)
        #expect(lifecycle.stateSnapshot == .idle)
        lifecycle.finish()
    }

    @Test("signal cancellation and finish races resume the consumer exactly once")
    func signalCancellationAndFinishRaceResumesExactlyOnce() async {
        for _ in 0..<64 {
            let (doorbell, consumerRegistration) = makeDoorbellWithRegistrationAcknowledgement()
            let signaler = doorbell.signalerPort
            let consumer = doorbell.consumerPort
            let lifecycle = doorbell.lifecyclePort
            let completionLedger = DoorbellCompletionLedger()
            let waitingConsumer = Task {
                let result = await consumer.nextSignal()
                await completionLedger.record(result)
                return result
            }

            var registrationIterator = consumerRegistration.makeAsyncIterator()
            #expect(await registrationIterator.next() != nil)
            #expect(lifecycle.stateSnapshot == .consumerWaiting)

            let arrivalGate = AsyncStream<Void>.makeStream()
            let startGate = AsyncStream<Void>.makeStream()
            let signalContender = Task {
                arrivalGate.continuation.yield()
                for await _ in startGate.stream { break }
                signaler.signal()
            }
            let cancellationContender = Task {
                arrivalGate.continuation.yield()
                for await _ in startGate.stream { break }
                waitingConsumer.cancel()
            }
            let finishContender = Task {
                arrivalGate.continuation.yield()
                for await _ in startGate.stream { break }
                lifecycle.finish()
            }

            var arrivalIterator = arrivalGate.stream.makeAsyncIterator()
            for _ in 0..<3 {
                #expect(await arrivalIterator.next() != nil)
            }
            arrivalGate.continuation.finish()
            for _ in 0..<3 {
                startGate.continuation.yield()
            }
            startGate.continuation.finish()

            _ = await signalContender.value
            _ = await cancellationContender.value
            _ = await finishContender.value
            let result = await waitingConsumer.value
            let recordedResults = await completionLedger.results

            #expect(result == .signaled || result == .finished)
            #expect(recordedResults == [result])
            #expect(lifecycle.stateSnapshot == .finished)
            #expect(await consumer.nextSignal() == .finished)
        }
    }

    @Test("concrete ports expose only their assigned capabilities")
    func concretePortsExposeOnlyAssignedCapabilities() throws {
        let doorbell = AdmissionDoorbell()
        requireSignaler(doorbell.signalerPort)
        requireConsumer(doorbell.consumerPort)
        requireLifecycle(doorbell.lifecyclePort)

        let source = try admissionDoorbellSource()
        let signalerSource = try sourceSlice(
            source,
            from: "struct AdmissionDoorbellSignalerPort",
            to: "struct AdmissionDoorbellConsumerPort"
        )
        let consumerSource = try sourceSlice(
            source,
            from: "struct AdmissionDoorbellConsumerPort",
            to: "struct AdmissionDoorbellLifecyclePort"
        )
        let lifecycleSource = try sourceSlice(
            source,
            from: "struct AdmissionDoorbellLifecyclePort",
            to: "final class AdmissionDoorbell"
        )

        #expect(signalerSource.contains("func signal()"))
        #expect(signalerSource.contains("nextSignal") == false)
        #expect(signalerSource.contains("func finish()") == false)
        #expect(consumerSource.contains("func nextSignal()"))
        #expect(consumerSource.contains("func signal()") == false)
        #expect(consumerSource.contains("func finish()") == false)
        #expect(lifecycleSource.contains("func finish()"))
        #expect(lifecycleSource.contains("func signal()") == false)
        #expect(lifecycleSource.contains("nextSignal") == false)
    }

    @Test("doorbell owns no payload queue or per-signal task creation")
    func doorbellOwnsNoPayloadQueueOrPerSignalTask() throws {
        let source = try admissionDoorbellSource()
        let implementationSource = try sourceSlice(
            source,
            from: "final class AdmissionDoorbell",
            to: nil
        )

        #expect(implementationSource.contains("AsyncStream") == false)
        #expect(implementationSource.contains("Task {") == false)
        let detachedTaskSpelling = ["Task", "detached"].joined(separator: ".")
        #expect(implementationSource.contains(detachedTaskSpelling) == false)
        #expect(implementationSource.contains("[AdmissionDoorbellResult]") == false)
        #expect(implementationSource.contains("Array<AdmissionDoorbellResult>") == false)
        #expect(implementationSource.contains("<Payload") == false)
        #expect(implementationSource.contains("case .consumerWaiting(let waitingConsumer) = state"))
        #expect(implementationSource.contains("cancelledConsumer?.continuation.resume"))
    }

    @Test("doorbell storage and wait registration expose only closed transitions")
    func doorbellStorageAndWaitRegistrationAreClosed() throws {
        let source = try admissionDoorbellSource()
        let implementationSource = try sourceSlice(
            source,
            from: "final class AdmissionDoorbell",
            to: nil
        )

        #expect(implementationSource.contains("var hasPendingSignal") == false)
        #expect(implementationSource.contains("var waitingConsumer") == false)
        #expect(implementationSource.contains("var isFinished") == false)
        #expect(implementationSource.contains("-> AdmissionDoorbellResult?") == false)
        #expect(implementationSource.contains("enum WaitRegistrationTransition"))
        #expect(implementationSource.contains("case suspended"))
        #expect(implementationSource.contains("case resume(AdmissionDoorbellResult)"))
    }

    private func requireSignaler<TSignaler: AdmissionDoorbellSignaler>(_: TSignaler) {}

    private func requireConsumer<TConsumer: AdmissionDoorbellConsumer>(_: TConsumer) {}

    private func requireLifecycle<TLifecycle: AdmissionDoorbellLifecycle>(_: TLifecycle) {}

    private func admissionDoorbellSource() throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Admission/AdmissionDoorbell.swift"
            ),
            encoding: .utf8
        )
    }

    private func sourceSlice(
        _ source: String,
        from startMarker: String,
        to endMarker: String?
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end: String.Index
        if let endMarker {
            end = try #require(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        } else {
            end = source.endIndex
        }
        return source[start..<end]
    }

    private func waitForDoorbellState(
        _ expectedState: AdmissionDoorbellStateSnapshot,
        lifecycle: AdmissionDoorbellLifecyclePort,
        maximumTurns: Int = 100
    ) async -> Bool {
        for _ in 0..<maximumTurns {
            if lifecycle.stateSnapshot == expectedState {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func makeDoorbellWithRegistrationAcknowledgement() -> (
        doorbell: AdmissionDoorbell,
        consumerRegistration: AsyncStream<Void>
    ) {
        let registration = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let doorbell = AdmissionDoorbell {
            registration.continuation.yield()
            registration.continuation.finish()
        }
        return (doorbell, registration.stream)
    }
}

private actor DoorbellCompletionLedger {
    private var recordedResults: [AdmissionDoorbellResult] = []

    func record(_ result: AdmissionDoorbellResult) {
        recordedResults.append(result)
    }

    var results: [AdmissionDoorbellResult] {
        recordedResults
    }
}
