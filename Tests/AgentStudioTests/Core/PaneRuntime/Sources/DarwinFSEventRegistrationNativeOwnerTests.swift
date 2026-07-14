import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Darwin FSEvent persistent native owner")
struct DarwinFSEventRegistrationNativeOwnerTests {
    @Test("claimed create cannot be abandoned and replays exact completion")
    func createAttemptClaimedBeforeNativeCreateCannotBeAbandonedAndReplaysExactCompletion()
        async throws
    {
        // Arrange
        let nativeCreateGate = DarwinNativeOwnerControllableCall()
        let fixture = try makeNativeOwnerFixture(
            createSynchronization: .controlled(nativeCreateGate)
        )
        let abandonmentInvocation = DarwinNativeOwnerInvocationProbe()

        // Act
        let createTask = Task {
            fixture.nativeOwner.createOrReplay(
                controlBlock: fixture.controlBlock,
                adapter: fixture.adapter,
                nativeDriver: fixture.nativeDriver,
                callbackQueueBarrier: fixture.callbackQueueBarrier
            )
        }
        await nativeCreateGate.waitUntilEntered()
        let abandonmentTask = Task {
            await abandonmentInvocation.recordInvocation()
            return fixture.nativeOwner.abandonCreation()
        }
        await abandonmentInvocation.waitUntilInvoked()
        nativeCreateGate.release()
        let createResult = await createTask.value
        let abandonmentResult = await abandonmentTask.value

        // Assert
        guard case .created(let createCompletion) = createResult,
            case .created(let abandonmentReplay) = abandonmentResult
        else {
            Issue.record("claimed native create must win and retain one exact completion")
            return
        }
        #expect(createCompletion === abandonmentReplay)
        #expect(fixture.ledger.events == [.create])
    }

    @Test("start abandonment consumes the start right and replays exact completion")
    func startAbandonmentPermanentlyConsumesStartRightAndReplaysExactCompletion() async throws {
        // Arrange
        let fixture = try makeNativeOwnerFixture()
        let creation = try requireCreatedCompletion(fixture)

        // Act
        let firstResult = await fixture.nativeOwner.abandonStartAfterCreate(
            creation: creation
        )
        let replayedResult = await fixture.nativeOwner.abandonStartAfterCreate(
            creation: creation
        )
        let delayedStart = await fixture.nativeOwner.startOrReplay(creation: creation)

        // Assert
        guard
            case .unpublished(.createdNeverStartedClosed(let firstCompletion)) = firstResult,
            case .unpublished(.createdNeverStartedClosed(let replayedCompletion)) =
                replayedResult,
            case .unpublished(.createdNeverStartedClosed(let delayedStartCompletion)) =
                delayedStart
        else {
            Issue.record("abandoned start authority must replay created-never-started closure")
            return
        }
        #expect(firstCompletion === replayedCompletion)
        #expect(firstCompletion === delayedStartCompletion)
        #expect(fixture.ledger.events == [.create, .invalidate, .barrier, .release])
    }

    @Test("created-never-started closure proves zero callback quiescence")
    func createdNeverStartedClosureReturnsExactZeroCallbackQuiescence() async throws {
        // Arrange
        let fixture = try makeNativeOwnerFixture()
        let creation = try requireCreatedCompletion(fixture)

        // Act
        let result = await fixture.nativeOwner.abandonStartAfterCreate(
            creation: creation
        )

        // Assert
        guard case .unpublished(.createdNeverStartedClosed) = result else {
            Issue.record("created stream abandonment must return exact unpublished quiescence")
            return
        }
        #expect(fixture.ledger.events == [.create, .invalidate, .barrier, .release])
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
        let gatherDiagnostics = fixture.mailbox.lifecyclePort.diagnostics.gather
        #expect(gatherDiagnostics.retainedContributionCount == 0)
        #expect(gatherDiagnostics.retainedItemCount == 0)
        #expect(gatherDiagnostics.leasedContributionCount == 0)
        #expect(gatherDiagnostics.leasedItemCount == 0)
        #expect(
            fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            ) == .starting(fixture.startingNativeLifetime)
        )
    }

    @Test("claimed start cannot be abandoned and replays exact completion")
    func startAttemptClaimedBeforeNativeStartCannotBeAbandonedAndReplaysExactCompletion()
        async throws
    {
        // Arrange
        let nativeStartGate = DarwinNativeOwnerControllableCall()
        let fixture = try makeNativeOwnerFixture(
            startSynchronization: .controlled(nativeStartGate)
        )
        let creation = try requireCreatedCompletion(fixture)

        // Act
        let startTask = Task {
            await fixture.nativeOwner.startOrReplay(creation: creation)
        }
        await nativeStartGate.waitUntilEntered()
        let abandonmentTask = Task {
            await fixture.nativeOwner.abandonStartAfterCreate(
                creation: creation
            )
        }
        nativeStartGate.release()
        let startResult = await startTask.value
        let abandonmentResult = await abandonmentTask.value
        let replayedStart = await fixture.nativeOwner.startOrReplay(creation: creation)

        // Assert
        guard case .started(let startCompletion) = startResult,
            case .started(let abandonmentReplay) = abandonmentResult,
            case .started(let startReplay) = replayedStart
        else {
            Issue.record("claimed native start must win and retain one exact completion")
            return
        }
        #expect(startCompletion == abandonmentReplay)
        #expect(startCompletion == startReplay)
        #expect(fixture.ledger.events == [.create, .start])
    }

    @Test("start rejection drains with zero callback custody and replays quiescence")
    func startRejectionDrainsWithoutCallbackCustodyAndReplaysExactQuiescence() async throws {
        // Arrange
        let fixture = try makeNativeOwnerFixture(startSucceeds: false)
        let creation = try requireCreatedCompletion(fixture)

        // Act
        let firstResult = await fixture.nativeOwner.startOrReplay(creation: creation)
        let replayedResult = await fixture.nativeOwner.startOrReplay(creation: creation)
        let delayedAbandonment = await fixture.nativeOwner.abandonStartAfterCreate(
            creation: creation
        )

        // Assert
        guard case .unpublished(.startRejectedAfterDrain(let firstCompletion)) = firstResult,
            case .unpublished(.startRejectedAfterDrain(let replayedCompletion)) = replayedResult,
            case .unpublished(.startRejectedAfterDrain(let abandonmentReplay)) = delayedAbandonment
        else {
            Issue.record("rejected start must retain one exact zero-callback quiescence")
            return
        }
        #expect(firstCompletion === replayedCompletion)
        #expect(firstCompletion === abandonmentReplay)
        #expect(fixture.ledger.events == [.create, .start, .invalidate, .barrier, .release])
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
        let gatherDiagnostics = fixture.mailbox.lifecyclePort.diagnostics.gather
        #expect(gatherDiagnostics.retainedContributionCount == 0)
        #expect(gatherDiagnostics.leasedContributionCount == 0)
        #expect(
            fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            ) == .starting(fixture.startingNativeLifetime)
        )
    }

    @Test("dropping unpublished evidence cannot release fixed-owner callback context")
    func droppingUnpublishedEvidenceDoesNotReleaseFixedOwnerCallbackContext() throws {
        // Arrange
        var fixture: DarwinNativeOwnerFixture? = try makeNativeOwnerFixture()
        let mailbox = try #require(fixture).mailbox
        weak var retainedAdapter = try #require(fixture).adapter

        // Act
        do {
            let scopedFixture = try #require(fixture)
            _ = scopedFixture.nativeOwner.createOrReplay(
                controlBlock: scopedFixture.controlBlock,
                adapter: scopedFixture.adapter,
                nativeDriver: scopedFixture.nativeDriver,
                callbackQueueBarrier: scopedFixture.callbackQueueBarrier
            )
        }
        fixture = nil

        // Assert
        withExtendedLifetime(mailbox) {
            #expect(retainedAdapter != nil)
        }
    }

    private func requireCreatedCompletion(
        _ fixture: DarwinNativeOwnerFixture
    ) throws -> DarwinFSEventRegistrationGeneration {
        let result = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )
        guard case .created(let creation) = result else {
            throw DarwinNativeOwnerTestFailure.expectedCreatedCompletion
        }
        return creation
    }

    private func makeNativeOwnerFixture(
        createSucceeds: Bool = true,
        startSucceeds: Bool = true,
        createSynchronization: DarwinNativeOwnerTestCallSynchronization = .immediate,
        startSynchronization: DarwinNativeOwnerTestCallSynchronization = .immediate
    ) throws -> DarwinNativeOwnerFixture {
        let mailbox = try FilesystemObservationMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 82),
            maximumSimultaneousSourceCount: 1,
            replacementReserveSlotCount: 0,
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: 1,
                maximumRetainedContributions: 8,
                maximumRetainedItems: 8,
                maximumRetainedBytes: 512,
                maximumRetainedContributionsPerKey: 8,
                maximumRetainedItemsPerKey: 8,
                maximumRetainedBytesPerKey: 512,
                maximumContributionsPerLease: 4,
                maximumItemsPerLease: 4,
                maximumBytesPerLease: 256,
                cleanupQuantum: .entriesAndBytes(maximumEntries: 4, maximumBytes: 256)
            )
        )
        let registration = makeNativeOwnerRegistration()
        _ = mailbox.installTestConfiguration(registration)
        guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
            case .committed(let startingNativeLifetime) = mailbox.beginNativeLifetime(
                selection.reservation
            ),
            case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            )
        else {
            throw DarwinNativeOwnerTestFailure.fixtureConstructionFailed
        }
        let controlBlock = try FSEventRegistrationControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            watchRoot: WatchRoot(
                sourceID: registration.sourceID,
                declaredPath: "/workspace/native-owner",
                resolvedPath: "/private/workspace/native-owner"
            ),
            captureLimits: try FSEventCaptureLimits(
                maximumInspectedNativeRecords: 8,
                maximumCopiedRecords: 8,
                maximumCopiedUTF8Bytes: 4096,
                maximumSinglePathUTF8Bytes: 1024
            ),
            callbackQueue: DispatchQueue(label: "test.darwin-native-owner.callback")
        )
        let adapter = DarwinNativeOwnerTestCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort
        )
        let ledger = DarwinNativeOwnerTestLedger()
        return DarwinNativeOwnerFixture(
            mailbox: mailbox,
            startingNativeLifetime: startingNativeLifetime,
            nativeGenerationPorts: nativeGenerationPorts,
            nativeOwner: nativeGenerationPorts.nativeOwner,
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: DarwinNativeOwnerTestDriver(
                ledger: ledger,
                createSucceeds: createSucceeds,
                startSucceeds: startSucceeds,
                createSynchronization: createSynchronization,
                startSynchronization: startSynchronization
            ),
            callbackQueueBarrier: DarwinNativeOwnerTestBarrier(ledger: ledger),
            ledger: ledger
        )
    }

    private func makeNativeOwnerRegistration() -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
            ),
            registrationGeneration: 42,
            rootGeneration: 8
        )
    }
}

private struct DarwinNativeOwnerFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeGenerationPorts: FilesystemObservationNativeGenerationPorts
    let nativeOwner: DarwinFSEventRegistrationNativeOwner
    let controlBlock: FSEventRegistrationControlBlock
    let adapter: DarwinNativeOwnerTestCallbackAdapter
    let nativeDriver: DarwinNativeOwnerTestDriver
    let callbackQueueBarrier: DarwinNativeOwnerTestBarrier
    let ledger: DarwinNativeOwnerTestLedger
}

private enum DarwinNativeOwnerTestFailure: Error {
    case fixtureConstructionFailed
    case expectedCreatedCompletion
}

private final class DarwinNativeOwnerTestCallbackAdapter:
    DarwinFSEventRegistrationCallbackAdapter,
    @unchecked Sendable
{
    let controlBlock: FSEventRegistrationControlBlock
    let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort

    init(
        controlBlock: FSEventRegistrationControlBlock,
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    ) {
        self.controlBlock = controlBlock
        self.callbackAdmissionPort = callbackAdmissionPort
    }

    func capture(
        input _: DarwinFSEventNativeCallbackInput
    ) -> DarwinFSEventObservationCaptureResult {
        .ignoredEmptyCallback
    }
}

private enum DarwinNativeOwnerTestEvent: Equatable, Sendable {
    case create
    case start
    case stop
    case invalidate
    case barrier
    case release
}

private final class DarwinNativeOwnerTestLedger: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [DarwinNativeOwnerTestEvent]())

    var events: [DarwinNativeOwnerTestEvent] {
        lock.withLock { $0 }
    }

    func record(_ event: DarwinNativeOwnerTestEvent) {
        lock.withLock { $0.append(event) }
    }
}

private struct DarwinNativeOwnerTestDriver: DarwinFSEventNativeDriver {
    let ledger: DarwinNativeOwnerTestLedger
    let createSucceeds: Bool
    let startSucceeds: Bool
    let createSynchronization: DarwinNativeOwnerTestCallSynchronization
    let startSynchronization: DarwinNativeOwnerTestCallSynchronization

    func createStream(
        request _: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        ledger.record(.create)
        createSynchronization.pauseIfControlled()
        guard createSucceeds else { return .failure(.nativeCreateRejected) }
        return .success(.testHandle())
    }

    func startStream(_: DarwinFSEventNativeStreamHandle) -> Bool {
        ledger.record(.start)
        startSynchronization.pauseIfControlled()
        return startSucceeds
    }

    func stopStream(_: DarwinFSEventNativeStreamHandle) {
        ledger.record(.stop)
    }

    func invalidateStream(_: DarwinFSEventNativeStreamHandle) {
        ledger.record(.invalidate)
    }

    func releaseStream(_: DarwinFSEventNativeStreamHandle) {
        ledger.record(.release)
    }
}

private enum DarwinNativeOwnerTestCallSynchronization: Sendable {
    case immediate
    case controlled(DarwinNativeOwnerControllableCall)

    func pauseIfControlled() {
        guard case .controlled(let controllableCall) = self else { return }
        controllableCall.pause()
    }
}

private final class DarwinNativeOwnerControllableCall: @unchecked Sendable {
    private enum EntryState {
        case pending
        case waiting(CheckedContinuation<Void, Never>)
        case entered
    }

    private let entryLock = OSAllocatedUnfairLock(initialState: EntryState.pending)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func pause() {
        let waiter = entryLock.withLock { state -> CheckedContinuation<Void, Never>? in
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
            let didEnter = entryLock.withLock { state -> Bool in
                switch state {
                case .pending:
                    state = .waiting(continuation)
                    return false
                case .waiting:
                    preconditionFailure("controlled native call supports one waiter")
                case .entered:
                    return true
                }
            }
            if didEnter {
                continuation.resume()
            }
        }
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private actor DarwinNativeOwnerInvocationProbe {
    private var didInvoke = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordInvocation() {
        didInvoke = true
        let pendingWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }

    func waitUntilInvoked() async {
        guard !didInvoke else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private struct DarwinNativeOwnerTestBarrier: DarwinFSEventCallbackQueueBarrier {
    let ledger: DarwinNativeOwnerTestLedger

    func waitForBarrier(on _: DispatchQueue) async {
        ledger.record(.barrier)
    }
}
