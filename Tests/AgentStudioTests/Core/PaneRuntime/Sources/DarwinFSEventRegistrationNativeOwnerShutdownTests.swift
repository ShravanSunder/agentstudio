import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Darwin FSEvent native owner fleet shutdown")
struct DarwinFSEventRegistrationNativeOwnerShutdownTests {
    @Test("retry joins the prior result while its publication is in progress")
    func retryJoinsPublishingAdvanceResult() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_011)
        let publicationGate = DarwinNativeOwnerShutdownSynchronousGate()
        let publisher = ControlledShutdownResultPublisher(publicationGate: publicationGate)
        let coordinator = DarwinFSEventNativeOwnerShutdownAdvanceCoordinator {
            publisher
        }
        guard case .perform(let claimedPublisher) = coordinator.claim() else {
            Issue.record("First shutdown advance claim must perform")
            return
        }
        let abandonment = DarwinFSEventRegistrationCreationAbandonment(
            startingNativeLifetime: fixture.startingNativeLifetime
        )
        let result = DarwinFSEventNativeOwnerFleetShutdownResult.completed(
            .unpublished(.creationAbandoned(abandonment))
        )
        let publishTask = Task {
            coordinator.publish(result, for: claimedPublisher)
        }
        await publicationGate.waitUntilEntered()

        // Act
        let concurrentClaim = coordinator.claim()
        publicationGate.release()
        await publishTask.value
        let replay = coordinator.claim()

        // Assert
        guard case .wait(let joinedPublisher) = concurrentClaim else {
            Issue.record("Concurrent retry must join the result being published")
            return
        }
        #expect(joinedPublisher === claimedPublisher)
        #expect(replay.isCompleted(with: .unpublished(.creationAbandoned(abandonment))))
    }

    @Test("creation authority is abandoned once and exact completion replays")
    func creationAvailableAbandonsAndReplaysExactCompletion() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_001)

        // Act
        let first = await fixture.nativeOwner.advanceFleetShutdown()
        let replay = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        guard case .completed(.unpublished(.creationAbandoned(let abandonment))) = first,
            case .completed(.unpublished(.creationAbandoned(let replayedAbandonment))) = replay
        else {
            Issue.record("unused creation authority must become exact unpublished quiescence")
            return
        }
        #expect(abandonment === replayedAbandonment)
        #expect(abandonment.startingNativeLifetime == fixture.startingNativeLifetime)
        #expect(fixture.nativeDriverLedger.events.isEmpty)
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.advancePhase
                == .completed(.unpublished(.creationAbandoned(abandonment)))
        )
    }

    @Test("created generation closes without start and replays exact quiescence")
    func createdGenerationClosesWithoutStartAndReplays() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_002)
        _ = try createGeneration(fixture)

        // Act
        let first = await fixture.nativeOwner.advanceFleetShutdown()
        let replay = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        guard
            case .completed(.unpublished(.createdNeverStartedClosed(let completion))) = first,
            case .completed(
                .unpublished(.createdNeverStartedClosed(let replayedCompletion))
            ) = replay
        else {
            Issue.record("created generation must close through the existing abandon-start path")
            return
        }
        #expect(completion === replayedCompletion)
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.nativePhase
                == .unpublished(.createdNeverStartedClosed(completion))
        )
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.finalizationPhase == .retainedContext
        )
    }

    @Test("rejected native creation is exact terminal shutdown completion")
    func rejectedCreationReplaysExactCleanup() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(
            generationValue: 10_003,
            createSucceeds: false
        )
        guard
            case .creationRejected(let cleanup) = fixture.nativeOwner.createOrReplay(
                controlBlock: fixture.controlBlock,
                adapter: fixture.adapter,
                nativeDriver: fixture.nativeDriver,
                callbackQueueBarrier: fixture.callbackQueueBarrier
            )
        else {
            Issue.record("fixture must retain rejected creation cleanup")
            return
        }

        // Act
        let result = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        #expect(result == .completed(.unpublished(.creationRejected(cleanup))))
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.nativePhase
                == .creationRejected(cleanup)
        )
    }

    @Test("start rejection drain is retained as exact unpublished completion")
    func startRejectedDrainReplaysExactCompletion() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(
            generationValue: 10_004,
            startSucceeds: false
        )
        let generation = try createGeneration(fixture)
        guard
            case .unpublished(.startRejectedAfterDrain(let quiescence)) =
                await fixture.nativeOwner.startOrReplay(creation: generation)
        else {
            Issue.record("fixture must retain exact rejected-start drain")
            return
        }

        // Act
        let result = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        #expect(result == .completed(.unpublished(.startRejectedAfterDrain(quiescence))))
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.nativePhase
                == .unpublished(.startRejectedAfterDrain(quiescence))
        )
    }

    @Test("started generation closes once and replays exact lease-drain receipt")
    func startedGenerationClosesOnceAndReplaysReceipt() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_005)
        let generation = try createGeneration(fixture)
        guard case .started = await fixture.nativeOwner.startOrReplay(creation: generation)
        else {
            Issue.record("fixture must publish one accepting generation")
            return
        }

        // Act
        async let first = fixture.nativeOwner.advanceFleetShutdown()
        async let concurrent = fixture.nativeOwner.advanceFleetShutdown()
        let results = await (first, concurrent)
        let replay = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        guard case .completed(.acceptingGenerationClosed(let receipt)) = results.0,
            case .completed(.acceptingGenerationClosed(let concurrentReceipt)) = results.1,
            case .completed(.acceptingGenerationClosed(let replayedReceipt)) = replay
        else {
            Issue.record("all shutdown callers must join or replay one exact native close")
            return
        }
        #expect(receipt === concurrentReceipt)
        #expect(receipt === replayedReceipt)
        #expect(receipt.binding == fixture.startingNativeLifetime.binding)
        #expect(generation.phase == .closed)
    }

    @Test("accepting publication debt retries and remains exact")
    func acceptingPublicationDebtRetriesAndRemainsExact() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_010)
        let generation = try createGeneration(fixture)
        guard
            case .retirementRequired =
                fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                    fixture.startingNativeLifetime
                ),
            case .acceptingPublicationRejected(let initialRejection) =
                await fixture.nativeOwner.startOrReplay(creation: generation)
        else {
            Issue.record("fixture must retain one exact accepting-publication rejection")
            return
        }

        // Act
        let firstRetry = await fixture.nativeOwner.advanceFleetShutdown()
        let secondRetry = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        #expect(firstRetry == .incomplete(.acceptingPublicationPending(initialRejection)))
        #expect(secondRetry == .incomplete(.acceptingPublicationPending(initialRejection)))
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.nativePhase
                == .acceptingPublicationPending(
                    fixture.startingNativeLifetime,
                    initialRejection,
                    generationPhase: .startedAwaitingAcceptingPublication
                )
        )
        #expect(fixture.nativeOwner.fleetShutdownProjection.advancePhase == .available)
    }

    @Test("shutdown joins an already claimed native start then closes its generation")
    func shutdownJoinsStartRaceAndClosesExactGeneration() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_006)
        let startGate = DarwinNativeOwnerShutdownSynchronousGate()
        let driver = DarwinNativeOwnerShutdownDriver(startGate: startGate)
        let generation = try createGeneration(fixture, nativeDriver: driver)
        let startTask = Task {
            await fixture.nativeOwner.startOrReplay(creation: generation)
        }
        await startGate.waitUntilEntered()

        // Act
        let shutdownTask = Task { await fixture.nativeOwner.advanceFleetShutdown() }
        startGate.release()
        let startResult = await startTask.value
        let shutdownResult = await shutdownTask.value

        // Assert
        guard case .started = startResult,
            case .completed(.acceptingGenerationClosed(let receipt)) = shutdownResult
        else {
            Issue.record("shutdown must join the claimed start and close its exact generation")
            return
        }
        #expect(receipt.binding == fixture.startingNativeLifetime.binding)
        #expect(generation.phase == .closed)
    }

    @Test("shutdown joins an already claimed native create then closes without start")
    func shutdownJoinsCreateRaceAndClosesCreatedGeneration() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_007)
        let createGate = DarwinNativeOwnerShutdownSynchronousGate()
        let driver = DarwinNativeOwnerShutdownDriver(createGate: createGate)
        let createTask = Task {
            fixture.nativeOwner.createOrReplay(
                controlBlock: fixture.controlBlock,
                adapter: fixture.adapter,
                nativeDriver: driver,
                callbackQueueBarrier: fixture.callbackQueueBarrier
            )
        }
        await createGate.waitUntilEntered()

        // Act
        let shutdownTask = Task { await fixture.nativeOwner.advanceFleetShutdown() }
        createGate.release()
        let createResult = await createTask.value
        let shutdownResult = await shutdownTask.value

        // Assert
        guard case .created = createResult,
            case .completed(.unpublished(.createdNeverStartedClosed)) = shutdownResult
        else {
            Issue.record("shutdown must join create and consume the remaining start right")
            return
        }
    }

    @Test("requester cancellation cannot erase native drain or its retained receipt")
    func callerCancellationDoesNotEraseNativeDrain() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_008)
        let barrierGate = DarwinNativeOwnerShutdownAsyncGate()
        let generation = try createGeneration(
            fixture,
            callbackQueueBarrier: DarwinNativeOwnerShutdownBarrier(gate: barrierGate)
        )
        guard case .started = await fixture.nativeOwner.startOrReplay(creation: generation)
        else {
            Issue.record("fixture must publish one accepting generation")
            return
        }
        let cancelledRequester = Task {
            await fixture.nativeOwner.advanceFleetShutdown()
        }
        await barrierGate.waitUntilEntered()

        // Act
        cancelledRequester.cancel()
        await barrierGate.release()
        let lostResponse = await cancelledRequester.value
        let replay = await fixture.nativeOwner.advanceFleetShutdown()

        // Assert
        guard case .completed(.acceptingGenerationClosed(let receipt)) = lostResponse,
            case .completed(.acceptingGenerationClosed(let replayedReceipt)) = replay
        else {
            Issue.record("caller cancellation must not cancel owner-local native custody")
            return
        }
        #expect(receipt === replayedReceipt)
    }

    @Test("projection reports retained permit and final acknowledgement without payload custody")
    func projectionReportsExactFinalizationPhases() async throws {
        // Arrange
        let fixture = try makeD3NativeOwnerRetirementFixture(generationValue: 10_009)
        guard
            case .completed(.unpublished(.creationAbandoned(let abandonment))) =
                await fixture.nativeOwner.advanceFleetShutdown(),
            case .retirementRequired(let retiringLifetime) =
                fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                    abandonment.startingNativeLifetime
                ),
            case .finalized(let receipt) =
                fixture.mailbox.lifecyclePort.finalizeUnpublishedNativeGeneration(
                    retiringLifetime,
                    completion: .creationAbandoned(abandonment)
                )
        else {
            Issue.record("fixture must issue one exact unpublished retirement permit")
            return
        }
        let permit = FilesystemObservationNativeRetirementPermit.unpublished(receipt)

        // Act / Assert
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.finalizationPhase
                == .retirementPermitRetained(permit)
        )
        guard
            case .finalized(let acknowledgement) = fixture.nativeOwner.finalizeNativeLifetime(
                using: permit,
                contextFinalizer: fixture.finalizationLedger
            )
        else {
            Issue.record("retained permit must finalize the exact owner-local native lifetime")
            return
        }
        #expect(
            fixture.nativeOwner.fleetShutdownProjection.finalizationPhase
                == .finalized(acknowledgement)
        )
        #expect(fixture.finalizationLedger.retainedPointerReleaseCount == 0)
    }
}

private final class ControlledShutdownResultPublisher:
    DarwinFSEventNativeOwnerShutdownResultPublisher,
    @unchecked Sendable
{
    private let publicationGate: DarwinNativeOwnerShutdownSynchronousGate

    init(publicationGate: DarwinNativeOwnerShutdownSynchronousGate) {
        self.publicationGate = publicationGate
    }

    func wait() async -> DarwinFSEventNativeOwnerFleetShutdownResult {
        preconditionFailure("The coordinator ordering test joins by publisher identity")
    }

    func publish(_: DarwinFSEventNativeOwnerFleetShutdownResult) {
        publicationGate.pause()
    }
}

extension DarwinFSEventNativeOwnerShutdownAdvanceClaim {
    fileprivate func isCompleted(
        with expected: DarwinFSEventNativeOwnerFleetShutdownCompletion
    ) -> Bool {
        guard case .completed(let completion) = self else { return false }
        return completion == expected
    }
}

private func createGeneration(
    _ fixture: D3NativeOwnerRetirementFixture,
    nativeDriver: any DarwinFSEventNativeDriver,
    callbackQueueBarrier: any DarwinFSEventCallbackQueueBarrier
) throws -> DarwinFSEventRegistrationGeneration {
    guard
        case .created(let generation) = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: nativeDriver,
            callbackQueueBarrier: callbackQueueBarrier
        )
    else {
        throw DarwinNativeOwnerShutdownTestFailure.expectedCreatedGeneration
    }
    return generation
}

private func createGeneration(
    _ fixture: D3NativeOwnerRetirementFixture,
    nativeDriver: (any DarwinFSEventNativeDriver)? = nil,
    callbackQueueBarrier: (any DarwinFSEventCallbackQueueBarrier)? = nil
) throws -> DarwinFSEventRegistrationGeneration {
    try createGeneration(
        fixture,
        nativeDriver: nativeDriver ?? fixture.nativeDriver,
        callbackQueueBarrier: callbackQueueBarrier ?? fixture.callbackQueueBarrier
    )
}

private enum DarwinNativeOwnerShutdownTestFailure: Error {
    case expectedCreatedGeneration
}

private struct DarwinNativeOwnerShutdownDriver: DarwinFSEventNativeDriver {
    let createGate: DarwinNativeOwnerShutdownSynchronousGate?
    let startGate: DarwinNativeOwnerShutdownSynchronousGate?

    init(
        createGate: DarwinNativeOwnerShutdownSynchronousGate? = nil,
        startGate: DarwinNativeOwnerShutdownSynchronousGate? = nil
    ) {
        self.createGate = createGate
        self.startGate = startGate
    }

    func createStream(
        request _: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        createGate?.pause()
        return .success(.testHandle())
    }

    func startStream(_: DarwinFSEventNativeStreamHandle) -> Bool {
        startGate?.pause()
        return true
    }

    func stopStream(_: DarwinFSEventNativeStreamHandle) {}
    func invalidateStream(_: DarwinFSEventNativeStreamHandle) {}
    func releaseStream(_: DarwinFSEventNativeStreamHandle) {}
}

private final class DarwinNativeOwnerShutdownSynchronousGate: @unchecked Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<Void, Never>)
        case entered
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State.pending)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func pause() {
        let waiter = stateLock.withLock { state -> CheckedContinuation<Void, Never>? in
            switch state {
            case .pending:
                state = .entered
                return nil
            case .waiting(let continuation):
                state = .entered
                return continuation
            case .entered:
                preconditionFailure("controlled native call enters exactly once")
            }
        }
        waiter?.resume()
        releaseSemaphore.wait()
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            let didEnter = stateLock.withLock { state -> Bool in
                switch state {
                case .pending:
                    state = .waiting(continuation)
                    return false
                case .waiting:
                    preconditionFailure("controlled native call supports one entry waiter")
                case .entered:
                    return true
                }
            }
            if didEnter { continuation.resume() }
        }
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private actor DarwinNativeOwnerShutdownAsyncGate {
    private var didEnter = false
    private var didRelease = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        didRelease = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}

private struct DarwinNativeOwnerShutdownBarrier: DarwinFSEventCallbackQueueBarrier {
    let gate: DarwinNativeOwnerShutdownAsyncGate

    func waitForBarrier(on _: DispatchQueue) async {
        await gate.pause()
    }
}
