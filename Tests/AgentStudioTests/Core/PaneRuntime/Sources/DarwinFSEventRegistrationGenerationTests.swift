import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Dormant Darwin FSEvent registration generation")
struct DarwinFSEventRegistrationGenerationTests {
    @Test("persistent native owner creates once and replays exact completion")
    func persistentNativeOwnerCreatesOnceAndReplaysCompletion() throws {
        // Arrange
        let fixture = try makePersistentNativeOwnerFixture()

        // Act
        let firstResult = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )
        let replayedResult = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )

        // Assert
        guard case .created(let firstCompletion) = firstResult,
            case .created(let replayedCompletion) = replayedResult
        else {
            Issue.record("exact owner create must succeed and replay its typed completion")
            return
        }
        #expect(firstCompletion === replayedCompletion)
        #expect(fixture.ledger.events == [.create])
    }

    @Test("creation abandonment is exact replayable and permanently consumes create right")
    func creationAbandonmentPermanentlyConsumesCreateRight() throws {
        // Arrange
        let fixture = try makePersistentNativeOwnerFixture()

        // Act
        let firstAbandonment = fixture.nativeOwner.abandonCreation()
        let replayedAbandonment = fixture.nativeOwner.abandonCreation()
        let delayedCreate = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )

        // Assert
        guard case .creationAbandoned(let firstCompletion) = firstAbandonment,
            case .creationAbandoned(let replayedCompletion) = replayedAbandonment,
            case .creationAbandoned(let delayedCreateCompletion) = delayedCreate
        else {
            Issue.record("abandoned create authority must replay one exact typed completion")
            return
        }
        #expect(firstCompletion === replayedCompletion)
        #expect(firstCompletion === delayedCreateCompletion)
        #expect(fixture.ledger.events.isEmpty)
    }

    @Test("foreign binding is a typed native owner authority rejection")
    func foreignBindingIsTypedAuthorityRejection() throws {
        // Arrange
        let localFixture = try makePersistentNativeOwnerFixture()
        let foreignFixture = try makePersistentNativeOwnerFixture()

        // Act
        let result = localFixture.nativeOwner.createOrReplay(
            controlBlock: foreignFixture.controlBlock,
            adapter: foreignFixture.adapter,
            nativeDriver: localFixture.nativeDriver,
            callbackQueueBarrier: localFixture.callbackQueueBarrier
        )

        // Assert
        guard
            case .authorityRejected(
                .bindingMismatch(let expectedBinding, let presentedBinding)
            ) = result
        else {
            Issue.record("foreign binding must return a typed authority rejection")
            return
        }
        #expect(expectedBinding == localFixture.startingNativeLifetime.binding)
        #expect(presentedBinding == foreignFixture.startingNativeLifetime.binding)
        #expect(localFixture.ledger.events.isEmpty)
    }

    @Test("native create failure returns exact typed cleanup without stream operations")
    func createFailureReturnsTypedCleanup() throws {
        var fixture: GenerationFixture? = try makeFixture(createSucceeds: false)
        let mailbox = try #require(fixture).mailbox
        let ledger = try #require(fixture).ledger
        let startingNativeLifetime = try #require(fixture).startingNativeLifetime
        weak var retainedAdapter = try #require(fixture).adapter

        switch try #require(fixture).creationResult {
        case .created:
            Issue.record("configured native create failure must not produce a generation")
        case .creationRejected(let cleanup):
            #expect(cleanup.startingNativeLifetime == startingNativeLifetime)
            #expect(cleanup.nativeFailure == .nativeCreateRejected)
        case .creationAbandoned, .authorityRejected:
            Issue.record("configured native create failure must retain typed rejection evidence")
        }
        fixture = nil

        withExtendedLifetime(mailbox) {
            #expect(retainedAdapter != nil)
        }
        #expect(ledger.events == [.create])
    }

    @Test("native start failure invalidates and drains without stopping")
    func startFailureNeverStopsUnstartedStream() async throws {
        var fixture: GenerationFixture? = try makeFixture(startSucceeds: false)
        let mailbox = try #require(fixture).mailbox
        let ledger = try #require(fixture).ledger
        let startingNativeLifetime = try #require(fixture).startingNativeLifetime
        weak var retainedAdapter = try #require(fixture).adapter

        do {
            let generation = try requireCreatedGeneration(try #require(fixture).creationResult)
            switch await generation.start() {
            case .started, .acceptingPublicationRejected, .invalidPhase:
                Issue.record("configured native start failure must return typed cleanup")
            case .failed(let cleanup):
                #expect(cleanup.startingNativeLifetime == startingNativeLifetime)
                #expect(cleanup.binding == startingNativeLifetime.binding)
                #expect(
                    cleanup.nativeGenerationIdentity
                        == startingNativeLifetime.nativeGenerationIdentity
                )
                #expect(
                    cleanup.controlBlockIdentity
                        == startingNativeLifetime.binding.controlBlockIdentity
                )
            }
            #expect(generation.phase == .startFailed)
        }
        fixture = nil

        withExtendedLifetime(mailbox) {
            #expect(retainedAdapter != nil)
        }
        #expect(ledger.events == [.create, .start, .invalidate, .barrier, .release])
    }

    @Test("successful start atomically publishes exact accepting lifetime")
    func successfulStartPublishesExactAcceptingLifetime() async throws {
        let fixture = try makeFixture()
        let generation = try requireCreatedGeneration(fixture.creationResult)

        switch await generation.start() {
        case .started(let acceptingNativeLifetime):
            #expect(
                acceptingNativeLifetime.startingNativeLifetime
                    == fixture.startingNativeLifetime
            )
            #expect(
                fixture.mailbox.physicalSlotState(
                    of: fixture.startingNativeLifetime.binding.physicalSlotID
                ) == .accepting(acceptingNativeLifetime)
            )
        case .failed, .acceptingPublicationRejected, .invalidPhase:
            Issue.record("successful native start must publish the exact accepting lifetime")
        }
        #expect(fixture.ledger.events == [.create, .start])
        #expect(generation.phase == .started)
    }

    @Test("accepting publication rejects an exact starting-lifetime mismatch")
    func acceptingPublicationRejectsMismatch() throws {
        let fixture = try makeFixture()
        let mismatchedStartingNativeLifetime = FilesystemObservationStartingNativeLifetime(
            desiredRegistration: fixture.startingNativeLifetime.desiredRegistration,
            consumedReservation: fixture.startingNativeLifetime.consumedReservation,
            binding: fixture.startingNativeLifetime.binding,
            nativeGenerationIdentity: FilesystemObservationNativeGenerationIdentity(
                value: UUIDv7.generate()
            )
        )

        let result = fixture.nativeGenerationPorts.lifecyclePort.publishAccepting(
            mismatchedStartingNativeLifetime
        )

        #expect(
            result
                == .startingNativeLifetimeMismatch(fixture.startingNativeLifetime)
        )
        #expect(
            fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            ) == .starting(fixture.startingNativeLifetime)
        )
    }

    @Test("repeated native-port factory calls replay one exact authority assembly")
    func nativePortFactoryIsIdempotent() throws {
        let fixture = try makeFixture()

        let replayedPorts = try requireNativeGenerationPorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingNativeLifetime)
        )

        #expect(
            replayedPorts.callbackAdmissionPort.identity
                == fixture.nativeGenerationPorts.callbackAdmissionPort.identity
        )
        let firstPublication = fixture.nativeGenerationPorts.lifecyclePort.publishAccepting(
            fixture.startingNativeLifetime
        )
        let replayedPublication = replayedPorts.lifecyclePort.publishAccepting(
            fixture.startingNativeLifetime
        )
        guard case .published(let acceptingNativeLifetime) = firstPublication else {
            Issue.record("first exact assembly must publish accepting")
            return
        }
        #expect(replayedPublication == .alreadyPublished(acceptingNativeLifetime))
    }

    @Test("mailbox releases after its last external native-port assembly")
    func nativePortReplayCustodyDoesNotRetainMailbox() throws {
        weak var mailbox: FilesystemObservationMailbox?
        var nativeGenerationPorts: FilesystemObservationNativeGenerationPorts?
        do {
            let fixture = try makeMailboxFixture()
            mailbox = fixture.mailbox
            nativeGenerationPorts = fixture.nativeGenerationPorts
        }

        #expect(nativeGenerationPorts != nil)
        #expect(mailbox != nil)
        nativeGenerationPorts = nil
        #expect(mailbox == nil)
    }

    @Test("started close follows native fence order and releases stream once")
    func startedCloseUsesExactOrder() async throws {
        let fixture = try makeFixture()
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = await generation.start()

        let receipt = try requireClosedReceipt(await generation.close())

        #expect(
            fixture.ledger.events
                == [.create, .start, .stop, .invalidate, .barrier, .release]
        )
        #expect(receipt.binding == fixture.startingNativeLifetime.binding)
        #expect(
            receipt.nativeGenerationIdentity
                == fixture.startingNativeLifetime.nativeGenerationIdentity
        )
        #expect(
            receipt.controlBlockIdentity
                == fixture.startingNativeLifetime.binding.controlBlockIdentity
        )
        guard
            case .closingAwaitingCallbackLeaseDrain(let closingNativeLifetime) =
                fixture.mailbox.physicalSlotState(
                    of: fixture.startingNativeLifetime.binding.physicalSlotID
                )
        else {
            Issue.record("close must publish callback-lease-drain waiting before receipt")
            return
        }
        #expect(
            closingNativeLifetime.acceptingNativeLifetime.startingNativeLifetime
                == fixture.startingNativeLifetime
        )
        #expect(generation.phase == .closed)
    }

    @Test("created close omits stop and retains callback context beyond stream release")
    func unstartedCloseRetainsCallbackContext() async throws {
        var fixture: GenerationFixture? = try makeFixture()
        let mailbox = try #require(fixture).mailbox
        let ledger = try #require(fixture).ledger
        let startingNativeLifetime = try #require(fixture).startingNativeLifetime
        weak var retainedAdapter = try #require(fixture).adapter

        do {
            let generation = try requireCreatedGeneration(try #require(fixture).creationResult)
            let receipt = try requireClosedReceipt(await generation.close())
            #expect(receipt.binding == startingNativeLifetime.binding)
            #expect(
                receipt.nativeGenerationIdentity
                    == startingNativeLifetime.nativeGenerationIdentity
            )
        }
        fixture = nil

        #expect(ledger.events == [.create, .invalidate, .barrier, .release])
        withExtendedLifetime(mailbox) {
            #expect(retainedAdapter != nil)
        }
    }

    @Test("duplicate close replays the identical retained receipt")
    func duplicateCloseReplaysReceipt() async throws {
        let fixture = try makeFixture()
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = await generation.start()

        let firstReceipt = try requireClosedReceipt(await generation.close())
        let secondReceipt = try requireClosedReceipt(await generation.close())

        #expect(firstReceipt === secondReceipt)
        #expect(
            fixture.ledger.events
                == [.create, .start, .stop, .invalidate, .barrier, .release]
        )
    }

    @Test("missing callback-queue barrier phase cannot mint a drain receipt")
    func callbackBarrierMustCompleteBeforeReceipt() async throws {
        let barrier = DarwinGenerationControllableBarrier()
        let fixture = try makeFixture(callbackQueueBarrier: barrier)
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = await generation.start()

        let closeTask = Task { await generation.close() }
        await barrier.waitUntilStarted()

        #expect(generation.phase == .closingStartedStream)
        #expect(fixture.ledger.events == [.create, .start, .stop, .invalidate])
        guard
            case .closingAwaitingCallbackLeaseDrain = fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            )
        else {
            Issue.record("slot must enter lease-drain closing before barrier and receipt")
            return
        }

        await barrier.release()
        _ = try requireClosedReceipt(await closeTask.value)
        #expect(fixture.ledger.events.last == .release)
    }

    @Test("active callback lease withholds the retained close receipt until release")
    func activeCallbackLeaseWithholdsCloseReceipt() async throws {
        let barrier = DarwinGenerationControllableBarrier()
        let fixture = try makeFixture(callbackQueueBarrier: barrier)
        let generation = try requireCreatedGeneration(fixture.creationResult)
        _ = await generation.start()
        guard case .acquired(let callbackLease) = generation.controlBlock.acquireCallbackLease()
        else {
            Issue.record("started native generation must admit its exact callback lease")
            return
        }
        let completionProbe = DarwinGenerationCloseCompletionProbe()

        let closeTask = Task {
            let result = await generation.close()
            await completionProbe.record(result)
            return result
        }
        await barrier.waitUntilStarted()
        await barrier.release()
        try await waitForLeaseDrainCheckpoint(
            controlBlock: generation.controlBlock,
            completionProbe: completionProbe
        )

        #expect(
            generation.controlBlock.lifecycleSnapshot
                == .closing(.callbackQueueDrained, activeLeaseCount: 1)
        )
        #expect(!(await completionProbe.didComplete))
        #expect(generation.phase == .closingStartedStream)
        #expect(fixture.ledger.events == [.create, .start, .stop, .invalidate])

        #expect(callbackLease.release() == .released)
        let receipt = try requireClosedReceipt(await closeTask.value)
        #expect(receipt.binding == fixture.startingNativeLifetime.binding)
        #expect(generation.phase == .closed)
        #expect(fixture.ledger.events.last == .release)
    }

    @Test("close requested during native start is retained and completed")
    func closeDuringStartCannotBeLost() async throws {
        let startGate = DarwinGenerationControllableNativeStart()
        let fixture = try makeFixture(startSynchronization: .controlled(startGate))
        let generation = try requireCreatedGeneration(fixture.creationResult)

        let startTask = Task { await generation.start() }
        await startGate.waitUntilStartEntered()
        let closeTask = Task { await generation.close() }
        try await waitForPhase(.startingCloseRequested, generation: generation)
        startGate.releaseStart()
        switch await startTask.value {
        case .started(let acceptingNativeLifetime):
            #expect(
                acceptingNativeLifetime.startingNativeLifetime
                    == fixture.startingNativeLifetime
            )
        case .failed, .acceptingPublicationRejected, .invalidPhase:
            Issue.record("successful native start must publish accepting")
        }
        let receipt = try requireClosedReceipt(await closeTask.value)
        #expect(receipt.binding == fixture.startingNativeLifetime.binding)
        #expect(
            fixture.ledger.events
                == [.create, .start, .stop, .invalidate, .barrier, .release]
        )
        #expect(generation.phase == .closed)
        guard
            case .closingAwaitingCallbackLeaseDrain = fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            )
        else {
            Issue.record("retained close must transition the accepting slot")
            return
        }
    }

    private func makeFixture(
        createSucceeds: Bool = true,
        startSucceeds: Bool = true,
        startSynchronization: DarwinGenerationTestStartSynchronization = .immediate,
        callbackQueueBarrier: (any DarwinFSEventCallbackQueueBarrier)? = nil
    ) throws -> GenerationFixture {
        let mailboxFixture = try makeMailboxFixture()
        let startingNativeLifetime = mailboxFixture.startingNativeLifetime
        let controlBlock = try FSEventRegistrationControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            watchRoot: WatchRoot(
                sourceID: startingNativeLifetime.binding.registration.sourceID,
                declaredPath: "/workspace/repo",
                resolvedPath: "/private/workspace/repo"
            ),
            captureLimits: try FSEventCaptureLimits(
                maximumInspectedNativeRecords: 8,
                maximumCopiedRecords: 8,
                maximumCopiedUTF8Bytes: 4096,
                maximumSinglePathUTF8Bytes: 1024
            ),
            callbackQueue: DispatchQueue(label: "test.darwin-generation.callback")
        )
        let adapter = DarwinGenerationTestCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: mailboxFixture.nativeGenerationPorts.callbackAdmissionPort
        )
        let ledger = DarwinGenerationTestLedger()
        let nativeDriver = DarwinGenerationTestNativeDriver(
            ledger: ledger,
            createSucceeds: createSucceeds,
            startSucceeds: startSucceeds,
            startSynchronization: startSynchronization
        )
        let creationResult = mailboxFixture.nativeGenerationPorts.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: nativeDriver,
            callbackQueueBarrier: callbackQueueBarrier
                ?? DarwinGenerationTestBarrier(ledger: ledger)
        )
        return GenerationFixture(
            mailbox: mailboxFixture.mailbox,
            startingNativeLifetime: startingNativeLifetime,
            nativeGenerationPorts: mailboxFixture.nativeGenerationPorts,
            adapter: adapter,
            ledger: ledger,
            creationResult: creationResult
        )
    }

    private func makePersistentNativeOwnerFixture() throws -> PersistentNativeOwnerFixture {
        let mailboxFixture = try makeMailboxFixture()
        let startingNativeLifetime = mailboxFixture.startingNativeLifetime
        let controlBlock = try FSEventRegistrationControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            watchRoot: WatchRoot(
                sourceID: startingNativeLifetime.binding.registration.sourceID,
                declaredPath: "/workspace/repo",
                resolvedPath: "/private/workspace/repo"
            ),
            captureLimits: try FSEventCaptureLimits(
                maximumInspectedNativeRecords: 8,
                maximumCopiedRecords: 8,
                maximumCopiedUTF8Bytes: 4096,
                maximumSinglePathUTF8Bytes: 1024
            ),
            callbackQueue: DispatchQueue(label: "test.darwin-native-owner.callback")
        )
        let adapter = DarwinGenerationTestCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: mailboxFixture.nativeGenerationPorts.callbackAdmissionPort
        )
        let ledger = DarwinGenerationTestLedger()
        let nativeDriver = DarwinGenerationTestNativeDriver(
            ledger: ledger,
            createSucceeds: true,
            startSucceeds: true,
            startSynchronization: .immediate
        )
        return PersistentNativeOwnerFixture(
            mailbox: mailboxFixture.mailbox,
            startingNativeLifetime: startingNativeLifetime,
            nativeOwner: mailboxFixture.nativeGenerationPorts.nativeOwner,
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: nativeDriver,
            callbackQueueBarrier: DarwinGenerationTestBarrier(ledger: ledger),
            ledger: ledger
        )
    }

    private func makeMailboxFixture() throws -> GenerationMailboxFixture {
        let mailbox = try FilesystemObservationMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 81),
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
        let registration = makeRegistration()
        _ = mailbox.installTestConfiguration(registration)
        guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
            case .committed(let startingNativeLifetime) = mailbox.beginNativeLifetime(
                selection.reservation
            ),
            case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
                for: startingNativeLifetime
            )
        else {
            throw GenerationTestFailure.mailboxFixtureConstructionFailed
        }
        return GenerationMailboxFixture(
            mailbox: mailbox,
            startingNativeLifetime: startingNativeLifetime,
            nativeGenerationPorts: nativeGenerationPorts
        )
    }

    private func makeRegistration() -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            registrationGeneration: 41,
            rootGeneration: 7
        )
    }

    private func requireCreatedGeneration(
        _ result: DarwinFSEventNativeOwnerCreationResult
    ) throws -> DarwinFSEventRegistrationGeneration {
        switch result {
        case .created(let generation):
            generation
        case .creationRejected, .creationAbandoned, .authorityRejected:
            try #require(nil as DarwinFSEventRegistrationGeneration?)
        }
    }

    private func requireClosedReceipt(
        _ result: DarwinFSEventRegistrationGenerationCloseResult
    ) throws -> DarwinFSEventRegistrationLeaseDrainReceipt {
        switch result {
        case .closed(let receipt):
            receipt
        case .alreadyClosing, .startFailed, .mailboxRejected:
            try #require(nil as DarwinFSEventRegistrationLeaseDrainReceipt?)
        }
    }

    private func requireNativeGenerationPorts(
        _ result: FilesystemObservationNativeGenerationPortCreationResult
    ) throws -> FilesystemObservationNativeGenerationPorts {
        guard case .created(let ports) = result else {
            throw GenerationTestFailure.mailboxFixtureConstructionFailed
        }
        return ports
    }

    private func waitForPhase(
        _ expectedPhase: DarwinFSEventRegistrationGenerationPhase,
        generation: DarwinFSEventRegistrationGeneration
    ) async throws {
        for _ in 0..<1000 {
            guard generation.phase != expectedPhase else { return }
            await Task.yield()
        }
        throw GenerationTestFailure.closeRequestWasNotRegistered
    }

    private func waitForLeaseDrainCheckpoint(
        controlBlock: FSEventRegistrationControlBlock,
        completionProbe: DarwinGenerationCloseCompletionProbe
    ) async throws {
        for _ in 0..<1000 {
            let didComplete = await completionProbe.didComplete
            if controlBlock.lifecycleSnapshot
                == .closing(.callbackQueueDrained, activeLeaseCount: 1)
                || didComplete
            {
                return
            }
            await Task.yield()
        }
        throw GenerationTestFailure.leaseDrainCheckpointNotReached
    }
}

private struct GenerationFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeGenerationPorts: FilesystemObservationNativeGenerationPorts
    var adapter: DarwinGenerationTestCallbackAdapter?
    let ledger: DarwinGenerationTestLedger
    let creationResult: DarwinFSEventNativeOwnerCreationResult
}

private struct PersistentNativeOwnerFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeOwner: DarwinFSEventRegistrationNativeOwner
    let controlBlock: FSEventRegistrationControlBlock
    let adapter: DarwinGenerationTestCallbackAdapter
    let nativeDriver: DarwinGenerationTestNativeDriver
    let callbackQueueBarrier: DarwinGenerationTestBarrier
    let ledger: DarwinGenerationTestLedger
}

private struct GenerationMailboxFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeGenerationPorts: FilesystemObservationNativeGenerationPorts
}

private enum GenerationTestFailure: Error {
    case mailboxFixtureConstructionFailed
    case closeRequestWasNotRegistered
    case leaseDrainCheckpointNotReached
}

private actor DarwinGenerationCloseCompletionProbe {
    private(set) var didComplete = false

    func record(_: DarwinFSEventRegistrationGenerationCloseResult) {
        didComplete = true
    }
}

private final class DarwinGenerationTestCallbackAdapter:
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

private enum DarwinGenerationTestEvent: Equatable, Sendable {
    case create
    case start
    case stop
    case invalidate
    case barrier
    case release
}

private final class DarwinGenerationTestLedger: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [DarwinGenerationTestEvent]())

    var events: [DarwinGenerationTestEvent] {
        lock.withLock { $0 }
    }

    func record(_ event: DarwinGenerationTestEvent) {
        lock.withLock { events in
            events.append(event)
        }
    }
}

private struct DarwinGenerationTestNativeDriver: DarwinFSEventNativeDriver {
    let ledger: DarwinGenerationTestLedger
    let createSucceeds: Bool
    let startSucceeds: Bool
    let startSynchronization: DarwinGenerationTestStartSynchronization

    func createStream(
        request _: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        ledger.record(.create)
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

private enum DarwinGenerationTestStartSynchronization: Sendable {
    case immediate
    case controlled(DarwinGenerationControllableNativeStart)

    func pauseIfControlled() {
        switch self {
        case .immediate:
            return
        case .controlled(let controllableStart):
            controllableStart.pause()
        }
    }
}

private final class DarwinGenerationControllableNativeStart: @unchecked Sendable {
    private enum EntryState {
        case pending
        case waiting(CheckedContinuation<Void, Never>)
        case entered
    }

    private let entryLock = OSAllocatedUnfairLock(initialState: EntryState.pending)
    private let startRelease = DispatchSemaphore(value: 0)

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
                preconditionFailure("controllable native start enters exactly once")
            }
        }
        waiter?.resume()
        startRelease.wait()
    }

    func waitUntilStartEntered() async {
        await withCheckedContinuation { continuation in
            let didEnter = entryLock.withLock { state -> Bool in
                switch state {
                case .pending:
                    state = .waiting(continuation)
                    return false
                case .waiting:
                    preconditionFailure("controllable native start supports one waiter")
                case .entered:
                    return true
                }
            }
            if didEnter {
                continuation.resume()
            }
        }
    }

    func releaseStart() {
        startRelease.signal()
    }
}

private struct DarwinGenerationTestBarrier: DarwinFSEventCallbackQueueBarrier {
    let ledger: DarwinGenerationTestLedger

    func waitForBarrier(on _: DispatchQueue) async {
        ledger.record(.barrier)
    }
}

private actor DarwinGenerationControllableBarrier: DarwinFSEventCallbackQueueBarrier {
    private var didStart = false
    private var didRelease = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForBarrier(on _: DispatchQueue) async {
        didStart = true
        let pendingStartWaiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in pendingStartWaiters {
            waiter.resume()
        }
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        guard !didRelease else { return }
        didRelease = true
        let pendingReleaseWaiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in pendingReleaseWaiters {
            waiter.resume()
        }
    }
}
