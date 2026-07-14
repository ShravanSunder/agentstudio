import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Real Darwin FSEvent observation lifecycle")
struct DarwinFSEventObservationLifecycleIntegrationTests {
    @Test("real callback drains through fence, SourceGate, and release-once teardown")
    func realCallbackDrainsThroughFenceSourceGateAndReleaseOnceTeardown() async throws {
        // Arrange
        let temporaryRoot = try makeDarwinLifecycleTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let fixture = try await makeDarwinLifecycleFixture(temporaryRoot: temporaryRoot)

        // Act
        let callbackTrigger = triggerDarwinLifecycleCallback(
            temporaryRoot: temporaryRoot,
            callbackProbe: fixture.callbackProbe
        )
        let closeReceipt = try requireCloseReceipt(await fixture.generation.close())
        let replayedCloseReceipt = try requireCloseReceipt(await fixture.generation.close())
        let capturedResult = try callbackTrigger.requireCapture()
        let recoverySnapshot = try requireRecoverySnapshot(from: capturedResult)
        let retirementPermit = try await retireDarwinLifecycle(
            fixture: fixture,
            closeReceipt: closeReceipt,
            capture: capturedResult,
            recoverySnapshot: recoverySnapshot
        )
        let finalization = try finalizeDarwinLifecycle(
            fixture: fixture,
            retirementPermit: retirementPermit
        )

        // Assert
        #expect(fixture.acceptingLifetime.startingNativeLifetime == fixture.startingNativeLifetime)
        #expect(recoverySnapshot.revision.binding == fixture.startingNativeLifetime.binding)
        #expect(recoverySnapshot.evidence.contains(.callbackCaptureTruncation))
        #expect(closeReceipt === replayedCloseReceipt)
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
        #expect(
            fixture.controlBlock.leaseDrainCompletionSnapshot
                == .completed(resumedWaiterCount: 0)
        )
        #expect(
            fixture.nativeOperationLedger.events
                == [.create, .start, .stop, .invalidate, .barrier, .release]
        )
        #expect(finalization.acknowledgement == finalization.replayedAcknowledgement)
        #expect(finalization.contextFinalizer.releaseCount == 1)
        #expect(finalization.application.acknowledgement == finalization.acknowledgement)
        #expect(finalization.alreadyAppliedAcknowledgement == finalization.acknowledgement)
        #expect(
            fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            )
                == .vacant
        )
    }

    private func requireRecoverySnapshot(
        from capture: DarwinLifecycleAdmittedCapture
    ) throws -> FixedFilesystemRecoveryEvidenceSnapshot {
        guard case .admitted(let disposition, _) = capture.admission else {
            throw DarwinLifecycleIntegrationTestFailure.callbackWasNotAdmitted
        }
        switch disposition {
        case .retainedWithRecovery(let recovery), .contractedToRecovery(let recovery):
            return recovery
        case .retained:
            throw DarwinLifecycleIntegrationTestFailure.callbackDidNotRequireRecovery
        }
    }

    private func requireCloseReceipt(
        _ result: DarwinFSEventRegistrationGenerationCloseResult
    ) throws -> DarwinFSEventRegistrationLeaseDrainReceipt {
        guard case .closed(let receipt) = result else {
            throw DarwinLifecycleIntegrationTestFailure.nativeCloseFailed
        }
        return receipt
    }
}

private struct DarwinLifecycleFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeGenerationPorts: FilesystemObservationNativeGenerationPorts
    let controlBlock: FSEventRegistrationControlBlock
    let callbackProbe: DarwinLifecycleRecordingCallbackAdapter
    let nativeOperationLedger: DarwinLifecycleNativeOperationLedger
    let generation: DarwinFSEventRegistrationGeneration
    let acceptingLifetime: FilesystemObservationAcceptingNativeLifetime
}

private struct DarwinLifecycleFinalizationProof {
    let acknowledgement: FilesystemObservationContextReleaseAcknowledgement
    let replayedAcknowledgement: FilesystemObservationContextReleaseAcknowledgement
    let application: FilesystemObservationContextReleaseApplication
    let alreadyAppliedAcknowledgement: FilesystemObservationContextReleaseAcknowledgement
    let contextFinalizer: DarwinLifecycleRecordingContextFinalizer
}

private struct DarwinLifecycleStartInput {
    let temporaryRoot: URL
    let resolvedRootPath: String
    let registration: FSEventRegistrationToken
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeGenerationPorts: FilesystemObservationNativeGenerationPorts
}

private func makeDarwinLifecycleTemporaryRoot() throws -> URL {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "agentstudio-darwin-lifecycle-\(UUIDv7.generate().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: temporaryRoot,
        withIntermediateDirectories: false
    )
    return temporaryRoot
}

private func makeDarwinLifecycleFixture(
    temporaryRoot: URL
) async throws -> DarwinLifecycleFixture {
    let resolvedRootPath = temporaryRoot.resolvingSymlinksInPath().path
    let registration = FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUIDv7.generate()
        ),
        registrationGeneration: 1,
        rootGeneration: 1
    )
    let mailbox = try FilesystemObservationMailbox(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0,
        limits: leaseTransferMailboxLimits()
    )
    let configuration = FilesystemObservationSourceConfiguration(
        registration: registration,
        canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity(
            path: resolvedRootPath
        ),
        authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity(
            value: UUIDv7.generate()
        ),
        eventCoverage: .recursiveFileEvents
    )
    guard
        case .enqueued = mailbox.installDesiredConfiguration(
            configuration,
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 1)
        ),
        case .selected(let selection) = mailbox.selectNextDesiredSource(),
        case .committed(let startingNativeLifetime) = mailbox.beginNativeLifetime(
            selection.reservation
        ),
        case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
            for: startingNativeLifetime
        )
    else {
        throw DarwinLifecycleIntegrationTestFailure.fixtureConstructionFailed
    }
    return try await startDarwinLifecycleFixture(
        input: DarwinLifecycleStartInput(
            temporaryRoot: temporaryRoot,
            resolvedRootPath: resolvedRootPath,
            registration: registration,
            mailbox: mailbox,
            startingNativeLifetime: startingNativeLifetime,
            nativeGenerationPorts: nativeGenerationPorts
        )
    )
}

private func startDarwinLifecycleFixture(
    input: DarwinLifecycleStartInput
) async throws -> DarwinLifecycleFixture {
    let controlBlock = try FSEventRegistrationControlBlock(
        startingNativeLifetime: input.startingNativeLifetime,
        watchRoot: WatchRoot(
            sourceID: input.registration.sourceID,
            declaredPath: input.temporaryRoot.path,
            resolvedPath: input.resolvedRootPath
        ),
        captureLimits: try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 16,
            maximumCopiedRecords: 16,
            maximumCopiedUTF8Bytes: 16_384,
            maximumSinglePathUTF8Bytes: 1
        ),
        callbackQueue: DispatchQueue(
            label: "test.darwin-fsevent-observation-lifecycle.callback"
        )
    )
    let callbackProbe = DarwinLifecycleRecordingCallbackAdapter(
        delegate: DarwinFSEventObservationAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: input.nativeGenerationPorts.callbackAdmissionPort
        )
    )
    let nativeOperationLedger = DarwinLifecycleNativeOperationLedger()
    guard
        case .created(let generation) = input.nativeGenerationPorts.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: callbackProbe,
            nativeDriver: DarwinLifecycleRecordingNativeDriver(
                underlying: DarwinFSEventSystemNativeDriver(),
                ledger: nativeOperationLedger
            ),
            callbackQueueBarrier: DarwinLifecycleRecordingCallbackQueueBarrier(
                underlying: DarwinFSEventAsyncCallbackQueueBarrier(),
                ledger: nativeOperationLedger
            )
        ),
        case .started(let acceptingLifetime) = await input.nativeGenerationPorts.nativeOwner
            .startOrReplay(creation: generation)
    else {
        throw DarwinLifecycleIntegrationTestFailure.nativeStartFailed
    }
    return DarwinLifecycleFixture(
        mailbox: input.mailbox,
        startingNativeLifetime: input.startingNativeLifetime,
        nativeGenerationPorts: input.nativeGenerationPorts,
        controlBlock: controlBlock,
        callbackProbe: callbackProbe,
        nativeOperationLedger: nativeOperationLedger,
        generation: generation,
        acceptingLifetime: acceptingLifetime
    )
}

private func retireDarwinLifecycle(
    fixture: DarwinLifecycleFixture,
    closeReceipt: DarwinFSEventRegistrationLeaseDrainReceipt,
    capture: DarwinLifecycleAdmittedCapture,
    recoverySnapshot: FixedFilesystemRecoveryEvidenceSnapshot
) async throws -> FilesystemObservationNativeRetirementPermit {
    guard case .installed = fixture.mailbox.lifecyclePort.requestRetirementFence(closeReceipt)
    else {
        throw DarwinLifecycleIntegrationTestFailure.retirementFenceUnavailable
    }
    let drainHarness = try FilesystemObservationDrainHarnessActor(
        mailbox: fixture.mailbox,
        bindings: [fixture.startingNativeLifetime.binding],
        maximumContributionsPerLease: 3
    )
    guard case .lease(let lease) = await drainHarness.takeLease() else {
        throw DarwinLifecycleIntegrationTestFailure.leaseUnavailable
    }
    let recoveryContext = FilesystemObservationRecoveryAdmissionContext.required(
        trigger: .captureTruncation,
        watermark: .eventIDs(capture.offer.observation.eventIDWatermark),
        participants: makeDarwinLifecycleRepairParticipants()
    )
    guard
        case .completed(.transferred(let transferReceipt)) = await drainHarness.transferLease(
            lease,
            recoveryContext: recoveryContext
        ),
        case .retired(let retirementReceipt) = transferReceipt.outcome,
        case .quiescentAfterRecovery(let retirementRecoveryRevision) =
            retirementReceipt.disposition,
        retirementRecoveryRevision == recoverySnapshot.revision,
        case .issued(let retirementPermit) = fixture.mailbox.lifecyclePort
            .fenceBackedRetirementPermit(for: retirementReceipt)
    else {
        throw DarwinLifecycleIntegrationTestFailure.transferDidNotRetire
    }
    return retirementPermit
}

private func makeDarwinLifecycleRepairParticipants()
    -> Set<FilesystemRepairParticipantToken>
{
    Set(
        [
            FilesystemRepairParticipantKind.contentRepairProjector,
            .gitWorkingDirectoryProjector,
            .paneFilesystemProjection,
        ].map {
            FilesystemRepairParticipantToken(
                kind: $0,
                participantID: UUIDv7.generate(),
                participantGeneration: 1
            )
        }
    )
}

private func finalizeDarwinLifecycle(
    fixture: DarwinLifecycleFixture,
    retirementPermit: FilesystemObservationNativeRetirementPermit
) throws -> DarwinLifecycleFinalizationProof {
    let contextFinalizer = DarwinLifecycleRecordingContextFinalizer()
    guard
        case .finalized(let acknowledgement) =
            fixture.nativeGenerationPorts.nativeOwner.finalizeNativeLifetime(
                using: retirementPermit,
                contextFinalizer: contextFinalizer
            ),
        case .alreadyFinalized(let replayedAcknowledgement) =
            fixture.nativeGenerationPorts.nativeOwner.finalizeNativeLifetime(
                using: retirementPermit,
                contextFinalizer: contextFinalizer
            ),
        case .applied(let application) = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(acknowledgement),
        case .alreadyApplied(let alreadyAppliedAcknowledgement) = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(acknowledgement)
    else {
        throw DarwinLifecycleIntegrationTestFailure.contextReleaseFailed
    }
    return DarwinLifecycleFinalizationProof(
        acknowledgement: acknowledgement,
        replayedAcknowledgement: replayedAcknowledgement,
        application: application,
        alreadyAppliedAcknowledgement: alreadyAppliedAcknowledgement,
        contextFinalizer: contextFinalizer
    )
}

private struct DarwinLifecycleAdmittedCapture: Sendable {
    let offer: FilesystemObservationOffer
    let admission: FilesystemObservationCallbackAdmissionResult
}

private enum DarwinLifecycleCallbackTriggerResult {
    case captured(DarwinLifecycleAdmittedCapture)
    case writeFailed(any Error)
    case callbackTimedOut

    func requireCapture() throws -> DarwinLifecycleAdmittedCapture {
        switch self {
        case .captured(let capture):
            return capture
        case .writeFailed(let error):
            throw error
        case .callbackTimedOut:
            throw DarwinLifecycleIntegrationTestFailure.callbackTimedOut
        }
    }
}

private func triggerDarwinLifecycleCallback(
    temporaryRoot: URL,
    callbackProbe: DarwinLifecycleRecordingCallbackAdapter
) -> DarwinLifecycleCallbackTriggerResult {
    let changedFile = temporaryRoot.appendingPathComponent(
        "changed-\(UUIDv7.generate().uuidString).txt"
    )
    do {
        try Data("native-fsevent".utf8).write(to: changedFile, options: .atomic)
    } catch {
        return .writeFailed(error)
    }
    guard let capture = callbackProbe.waitForAdmittedCapture() else {
        return .callbackTimedOut
    }
    return .captured(capture)
}

private final class DarwinLifecycleRecordingCallbackAdapter:
    DarwinFSEventRegistrationCallbackAdapter,
    @unchecked Sendable
{
    private enum State: Sendable {
        case awaitingCapture
        case captured(DarwinLifecycleAdmittedCapture)
    }

    let controlBlock: FSEventRegistrationControlBlock
    private let delegate: DarwinFSEventObservationAdapter
    private let captureAvailable = DispatchSemaphore(value: 0)
    private let state = OSAllocatedUnfairLock(initialState: State.awaitingCapture)

    init(delegate: DarwinFSEventObservationAdapter) {
        self.delegate = delegate
        controlBlock = delegate.controlBlock
    }

    func capture(
        input: DarwinFSEventNativeCallbackInput
    ) -> DarwinFSEventObservationCaptureResult {
        let result = delegate.capture(input: input)
        guard case .admitted(let offer, let admission) = result else { return result }
        let didCapture = state.withLock { state -> Bool in
            guard case .awaitingCapture = state else { return false }
            state = .captured(DarwinLifecycleAdmittedCapture(offer: offer, admission: admission))
            return true
        }
        if didCapture { captureAvailable.signal() }
        return result
    }

    func waitForAdmittedCapture() -> DarwinLifecycleAdmittedCapture? {
        guard captureAvailable.wait(timeout: .now() + 10) == .success else {
            return nil
        }
        return state.withLock { state in
            guard case .captured(let capture) = state else {
                preconditionFailure("signaled Darwin capture must retain its exact result")
            }
            return capture
        }
    }
}

private enum DarwinLifecycleNativeOperation: Equatable, Sendable {
    case create
    case start
    case stop
    case invalidate
    case barrier
    case release
}

private final class DarwinLifecycleNativeOperationLedger: @unchecked Sendable {
    private let recordedEvents = OSAllocatedUnfairLock(
        initialState: [DarwinLifecycleNativeOperation]()
    )

    var events: [DarwinLifecycleNativeOperation] {
        recordedEvents.withLock { $0 }
    }

    func record(_ event: DarwinLifecycleNativeOperation) {
        recordedEvents.withLock { $0.append(event) }
    }
}

private struct DarwinLifecycleRecordingNativeDriver: DarwinFSEventNativeDriver {
    let underlying: DarwinFSEventSystemNativeDriver
    let ledger: DarwinLifecycleNativeOperationLedger

    func createStream(
        request: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        ledger.record(.create)
        return underlying.createStream(request: request)
    }

    func startStream(_ stream: DarwinFSEventNativeStreamHandle) -> Bool {
        ledger.record(.start)
        return underlying.startStream(stream)
    }

    func stopStream(_ stream: DarwinFSEventNativeStreamHandle) {
        ledger.record(.stop)
        underlying.stopStream(stream)
    }

    func invalidateStream(_ stream: DarwinFSEventNativeStreamHandle) {
        ledger.record(.invalidate)
        underlying.invalidateStream(stream)
    }

    func releaseStream(_ stream: DarwinFSEventNativeStreamHandle) {
        ledger.record(.release)
        underlying.releaseStream(stream)
    }
}

private struct DarwinLifecycleRecordingCallbackQueueBarrier:
    DarwinFSEventCallbackQueueBarrier
{
    let underlying: DarwinFSEventAsyncCallbackQueueBarrier
    let ledger: DarwinLifecycleNativeOperationLedger

    func waitForBarrier(on callbackQueue: DispatchQueue) async {
        await underlying.waitForBarrier(on: callbackQueue)
        ledger.record(.barrier)
    }
}

private final class DarwinLifecycleRecordingContextFinalizer:
    DarwinFSEventCallbackContextFinalizer,
    @unchecked Sendable
{
    private let underlying = DarwinFSEventUnmanagedCallbackContextFinalizer()
    private let recordedReleaseCount = OSAllocatedUnfairLock(initialState: 0)

    var releaseCount: Int { recordedReleaseCount.withLock { $0 } }

    func releaseRetainedContext(at pointerAddress: UInt) {
        underlying.releaseRetainedContext(at: pointerAddress)
        recordedReleaseCount.withLock { $0 += 1 }
    }
}

private enum DarwinLifecycleIntegrationTestFailure: Error {
    case fixtureConstructionFailed
    case nativeStartFailed
    case callbackTimedOut
    case callbackWasNotAdmitted
    case callbackDidNotRequireRecovery
    case nativeCloseFailed
    case retirementFenceUnavailable
    case leaseUnavailable
    case transferDidNotRetire
    case contextReleaseFailed
}
