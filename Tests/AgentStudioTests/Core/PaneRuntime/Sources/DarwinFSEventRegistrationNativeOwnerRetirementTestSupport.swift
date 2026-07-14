import Dispatch
import Foundation
import os

@testable import AgentStudio

struct D3NativeOwnerRetirementFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let nativeOwner: DarwinFSEventRegistrationNativeOwner
    let controlBlock: FSEventRegistrationControlBlock
    let adapter: D3NativeOwnerRetirementCallbackAdapter
    let nativeDriver: D3NativeOwnerRetirementDriver
    let callbackQueueBarrier: D3NativeOwnerRetirementBarrier
    let nativeDriverLedger: D3NativeDriverLedger
    let finalizationLedger: D3NativeFinalizationLedger
}

func makeD3NativeOwnerRetirementFixture(
    generationValue: UInt64,
    createSucceeds: Bool = true,
    startSucceeds: Bool = true
) throws -> D3NativeOwnerRetirementFixture {
    let mailbox = try FilesystemObservationMailbox(
        generation: AdmissionGeneration(
            owner: .filesystemObservation,
            value: generationValue
        ),
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
    let registration = FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUIDv7.generate()
        ),
        registrationGeneration: generationValue,
        rootGeneration: 1
    )
    _ = mailbox.installTestConfiguration(registration)
    guard case .selected(let selection) = mailbox.selectNextDesiredSource(),
        case .committed(let startingNativeLifetime) = mailbox.beginNativeLifetime(
            selection.reservation
        ),
        case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
            for: startingNativeLifetime
        )
    else {
        throw D3NativeOwnerRetirementTestFailure.fixtureConstructionFailed
    }
    let controlBlock = try FSEventRegistrationControlBlock(
        startingNativeLifetime: startingNativeLifetime,
        watchRoot: WatchRoot(
            sourceID: registration.sourceID,
            declaredPath: "/workspace/d3-native-retirement",
            resolvedPath: "/private/workspace/d3-native-retirement"
        ),
        captureLimits: try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 8,
            maximumCopiedRecords: 8,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        ),
        callbackQueue: DispatchQueue(label: "test.d3-native-retirement.callback")
    )
    let nativeDriverLedger = D3NativeDriverLedger()
    let adapter = D3NativeOwnerRetirementCallbackAdapter(
        controlBlock: controlBlock,
        callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort
    )
    return D3NativeOwnerRetirementFixture(
        mailbox: mailbox,
        startingNativeLifetime: startingNativeLifetime,
        nativeOwner: nativeGenerationPorts.nativeOwner,
        controlBlock: controlBlock,
        adapter: adapter,
        nativeDriver: D3NativeOwnerRetirementDriver(
            ledger: nativeDriverLedger,
            createSucceeds: createSucceeds,
            startSucceeds: startSucceeds
        ),
        callbackQueueBarrier: D3NativeOwnerRetirementBarrier(),
        nativeDriverLedger: nativeDriverLedger,
        finalizationLedger: D3NativeFinalizationLedger()
    )
}

enum D3NativeOwnerRetirementTestFailure: Error {
    case fixtureConstructionFailed
    case expectedCreatedGeneration
    case expectedRetainedContextQuiescence
    case expectedRetiringLifetime
    case expectedUnpublishedFinalReceipt
    case expectedFenceInstallation
    case expectedFenceLease
    case expectedFenceRetirementReceipt
    case expectedFenceBackedPermit
    case expectedCreateRejection
    case expectedStartRejectionAfterDrain
}

final class D3NativeOwnerRetirementCallbackAdapter:
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

enum D3NativeDriverEvent: Equatable, Sendable {
    case create
}

final class D3NativeDriverLedger: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [D3NativeDriverEvent]())

    var events: [D3NativeDriverEvent] {
        lock.withLock { $0 }
    }

    func record(_ event: D3NativeDriverEvent) {
        lock.withLock { $0.append(event) }
    }
}

struct D3NativeOwnerRetirementDriver: DarwinFSEventNativeDriver {
    let ledger: D3NativeDriverLedger
    let createSucceeds: Bool
    let startSucceeds: Bool

    func createStream(
        request _: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        ledger.record(.create)
        guard createSucceeds else { return .failure(.nativeCreateRejected) }
        return .success(.testHandle())
    }

    func startStream(_: DarwinFSEventNativeStreamHandle) -> Bool { startSucceeds }
    func stopStream(_: DarwinFSEventNativeStreamHandle) {}
    func invalidateStream(_: DarwinFSEventNativeStreamHandle) {}
    func releaseStream(_: DarwinFSEventNativeStreamHandle) {}
}

struct D3NativeOwnerRetirementBarrier: DarwinFSEventCallbackQueueBarrier {
    func waitForBarrier(on _: DispatchQueue) async {}
}

final class D3NativeFinalizationLedger:
    DarwinFSEventCallbackContextFinalizer,
    @unchecked Sendable
{
    private let lock = OSAllocatedUnfairLock(
        initialState: [UInt]()
    )

    var finalizations: [UInt] {
        lock.withLock { $0 }
    }

    var retainedPointerReleaseCount: Int {
        finalizations.count
    }

    func releaseRetainedContext(at pointerAddress: UInt) {
        lock.withLock { $0.append(pointerAddress) }
    }
}
