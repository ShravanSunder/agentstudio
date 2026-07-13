import CoreServices
import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Darwin FSEvent observation adapter capture")
struct DarwinFSEventObservationAdapterTests: Sendable {
    @Test("ordinary native records retain exact paths, flags, and ID watermark")
    func ordinaryRecordsAreCapturedExactly() throws {
        let fixture = try makeFixture()
        let result = capture(
            fixture: fixture,
            paths: ["/workspace/repo/first.swift", "/workspace/repo/second.swift"] as CFArray,
            flags: [
                FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagOwnEvent
                ),
            ],
            eventIDs: [41, 48]
        )

        let observation = requireAuthoritative(result)
        #expect(observation.totalRecordCount == .exact(2))
        #expect(observation.inspectedNativeRecordCount == 2)
        #expect(
            observation.records == [
                FSEventRecord(path: "/workspace/repo/first.swift", flags: [.itemCreated], eventID: 41),
                FSEventRecord(
                    path: "/workspace/repo/second.swift",
                    flags: [.itemModified, .ownEvent],
                    eventID: 48
                ),
            ]
        )
        #expect(observation.unionedInspectedFlags == [.itemCreated, .itemModified, .ownEvent])
        #expect(observation.eventIDWatermark == .inspected(first: 41, last: 48))
        #expect(observation.completeness == .complete)
    }

    @Test("kernel drop, root change, and rename join rather than mask recovery evidence")
    func discontinuityAndOrdinaryFlagsJoin() throws {
        let fixture = try makeFixture()
        let joinedFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagItemRenamed
        )

        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                paths: ["/workspace/repo/renamed.swift"] as CFArray,
                flags: [joinedFlags],
                eventIDs: [71]
            )
        )

        #expect(observation.records[0].flags == [.kernelDropped, .rootChanged, .itemRenamed])
        #expect(observation.completeness == .complete)
        #expect(evidence.contains(.continuityLoss))
        #expect(evidence.contains(.rootIdentityRevalidation))
        #expect(!evidence.contains(.callbackCaptureTruncation))
    }

    @Test("unknown native bits retain provenance and require conservative recovery")
    func unknownBitsRequireRecovery() throws {
        let fixture = try makeFixture()
        let unknownBit = FSEventStreamEventFlags(1 << 31)
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                paths: ["/workspace/repo/future"] as CFArray,
                flags: [unknownBit | FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)],
                eventIDs: [91]
            )
        )

        #expect(observation.records[0].flags.rawValue & UInt32(unknownBit) != 0)
        #expect(observation.unionedInspectedFlags.rawValue & UInt32(unknownBit) != 0)
        #expect(evidence.contains(.continuityLoss))
        #expect(evidence.contains(.unsupportedNativeFlags))
    }

    @Test("native inspection stops at its independent hard cap")
    func inspectedNativeRecordCapStopsNativeWalk() throws {
        let fixture = try makeFixture(
            captureLimits: makeCaptureLimits(maximumInspected: 2)
        )
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                paths: ["/one", "/two", "/uninspected"] as CFArray,
                flags: [
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
                    FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
                ],
                eventIDs: [10, 11, 12]
            )
        )

        #expect(observation.totalRecordCount == .exact(3))
        #expect(observation.inspectedNativeRecordCount == 2)
        #expect(observation.records.map(\.path) == ["/one", "/two"])
        #expect(observation.unionedInspectedFlags == [.itemCreated, .itemModified])
        #expect(observation.eventIDWatermark == .inspected(first: 10, last: 11))
        #expect(observation.completeness == .truncated([.inspectedRecordLimitReached]))
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("copied records stop independently while inspected evidence continues")
    func copiedRecordCapDoesNotStopBoundedInspection() throws {
        let fixture = try makeFixture(captureLimits: makeCaptureLimits(maximumCopied: 2))
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                paths: ["/one", "/two", "/three"] as CFArray,
                flags: [
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
                    FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
                ],
                eventIDs: [20, 21, 22]
            )
        )

        #expect(observation.inspectedNativeRecordCount == 3)
        #expect(observation.records.map(\.path) == ["/one", "/two"])
        #expect(observation.unionedInspectedFlags.contains(.rootChanged))
        #expect(observation.eventIDWatermark == .inspected(first: 20, last: 22))
        #expect(observation.completeness == .truncated([.copiedRecordLimitReached]))
        #expect(evidence.contains(.rootIdentityRevalidation))
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("cumulative copied UTF-8 bytes have an independent hard cap")
    func cumulativeCopiedByteCapIsEnforced() throws {
        let fixture = try makeFixture(captureLimits: makeCaptureLimits(maximumBytes: 4))
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                paths: ["/a", "/b", "/c"] as CFArray,
                flags: ordinaryFlags(count: 3),
                eventIDs: [30, 31, 32]
            )
        )

        #expect(observation.records.map(\.path) == ["/a", "/b"])
        #expect(observation.copiedUTF8ByteCount == 4)
        #expect(observation.completeness == .truncated([.copiedByteLimitReached]))
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("one oversized path admits zero-item recovery custody")
    func maximumSinglePathCapHasZeroMailboxFootprint() throws {
        let fixture = try makeFixture(
            captureLimits: makeCaptureLimits(maximumSinglePathBytes: 4)
        )
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                paths: ["/oversized"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [40]
            )
        )

        #expect(observation.inspectedNativeRecordCount == 1)
        #expect(observation.records.isEmpty)
        #expect(observation.copiedUTF8ByteCount == 0)
        #expect(observation.completeness == .truncated([.singlePathByteLimitReached]))
        #expect(evidence.contains(.callbackCaptureTruncation))
        let diagnostics = fixture.mailbox.lifecyclePort.diagnostics.gather
        #expect(diagnostics.retainedContributionCount == 1)
        #expect(diagnostics.retainedItemCount == 0)
        #expect(diagnostics.retainedByteCount == 0)
    }

    @Test("Unicode path admission uses its bounded UTF-8 size")
    func unicodePathHonorsUTF8Boundary() throws {
        let acceptedFixture = try makeFixture(
            captureLimits: makeCaptureLimits(maximumSinglePathBytes: 2)
        )
        let accepted = requireAuthoritative(
            capture(
                fixture: acceptedFixture,
                paths: ["é"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [41]
            )
        )
        #expect(accepted.records.map(\.path) == ["é"])
        #expect(accepted.copiedUTF8ByteCount == 2)

        let rejectedFixture = try makeFixture(
            registrationGeneration: 20,
            captureLimits: makeCaptureLimits(maximumSinglePathBytes: 1)
        )
        let (rejected, evidence) = requireRecovery(
            capture(
                fixture: rejectedFixture,
                paths: ["é"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [42]
            )
        )
        #expect(rejected.records.isEmpty)
        #expect(rejected.completeness == .truncated([.singlePathByteLimitReached]))
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("reported and CFArray counts retain malformed native shape")
    func malformedCFArrayCountIsCapturedConservatively() throws {
        let fixture = try makeFixture()
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                reportedEventCount: 2,
                paths: ["/available"] as CFArray,
                flags: ordinaryFlags(count: 2),
                eventIDs: [50, 51]
            )
        )

        #expect(
            observation.totalRecordCount
                == .malformed(
                    .nativeArrayCountMismatch(reportedRecordCount: 2, availableRecordCount: 1)
                )
        )
        #expect(observation.records.map(\.path) == ["/available"])
        #expect(observation.eventIDWatermark == .inspected(first: 50, last: 50))
        #expect(observation.completeness == .truncated([.malformedNativeShape]))
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("short flags buffer bounds native inspection")
    func shortFlagsBufferIsCapturedConservatively() throws {
        let fixture = try makeFixture()
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                reportedEventCount: 2,
                paths: ["/one", "/must-not-inspect"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [60, 61]
            )
        )
        expectMalformedPrefix(observation, availableCount: 1, retainedPath: "/one")
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("short event ID buffer bounds native inspection")
    func shortEventIDBufferIsCapturedConservatively() throws {
        let fixture = try makeFixture()
        let (observation, evidence) = requireRecovery(
            capture(
                fixture: fixture,
                reportedEventCount: 2,
                paths: ["/one", "/must-not-inspect"] as CFArray,
                flags: ordinaryFlags(count: 2),
                eventIDs: [70]
            )
        )
        expectMalformedPrefix(observation, availableCount: 1, retainedPath: "/one")
        #expect(evidence.contains(.callbackCaptureTruncation))
    }

    @Test("asymmetric native counts use the shortest available prefix")
    func asymmetricNativeCountsUseShortestPrefix() throws {
        let fixture = try makeFixture()
        let (observation, _) = requireRecovery(
            capture(
                fixture: fixture,
                reportedEventCount: 4,
                paths: ["/one", "/two", "/three"] as CFArray,
                flags: ordinaryFlags(count: 2),
                eventIDs: [80]
            )
        )
        expectMalformedPrefix(
            observation,
            reportedCount: 4,
            availableCount: 1,
            retainedPath: "/one"
        )
    }

    @Test("empty callback uses counted empty metadata buffers and creates no custody")
    func zeroRecordsAreIgnored() throws {
        let fixture = try makeFixture()
        let result = capture(
            fixture: fixture,
            reportedEventCount: 0,
            paths: [] as CFArray,
            flags: [],
            eventIDs: []
        )

        guard case .ignoredEmptyCallback = result else {
            Issue.record("empty callback must not create observation or mailbox custody")
            return
        }
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("stale registration rejects before native pointer inspection")
    func staleRegistrationRejectsBeforePointerInspection() throws {
        let fixture = try makeFixture()
        let stale = makeRegistration(registrationGeneration: 999)
        let result = capture(
            adapter: fixture.adapter,
            expectedRegistration: stale,
            reportedEventCount: 1,
            eventPaths: UnsafeMutableRawPointer(bitPattern: 1)!,
            flags: [],
            eventIDs: []
        )

        expectRejection(result, expected: .staleRegistration)
        expectNoActiveLease(fixture.controlBlock)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("callback lease remains held through synchronous mailbox admission")
    func callbackLeaseIsHeldThroughAdmission() throws {
        let fixture = try makeFixture()
        let recorder = LeaseCountRecorder()
        let underlyingProducer = fixture.mailbox.callbackProducerPort
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: fixture.controlBlock,
            producer: FilesystemObservationCallbackProducerPort { offer in
                recorder.record(fixture.controlBlock.lifecycleSnapshot)
                return underlyingProducer.offer(offer)
            },
            signaler: fixture.mailbox.callbackSignalerPort
        )

        _ = requireAuthoritative(
            capture(
                adapter: adapter,
                expectedRegistration: fixture.registration,
                paths: ["/held"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [90]
            )
        )
        #expect(recorder.observedActiveLeaseCount == 1)
        expectNoActiveLease(fixture.controlBlock)
    }

    @Test("closing during admission waits for the held callback lease")
    func closingAndAdmissionLeaseDrainRaceIsDeterministic() throws {
        let fixture = try makeFixture()
        let gate = CaptureAdmissionGate()
        let underlyingProducer = fixture.mailbox.callbackProducerPort
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: fixture.controlBlock,
            producer: FilesystemObservationCallbackProducerPort { offer in
                gate.admissionEntered.signal()
                gate.waitForAdmissionRelease()
                return underlyingProducer.offer(offer)
            },
            signaler: fixture.mailbox.callbackSignalerPort
        )

        DispatchQueue(label: "test.fsevent.capture-race").async {
            let result = capture(
                adapter: adapter,
                expectedRegistration: fixture.registration,
                paths: ["/racing"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [100]
            )
            gate.finish(with: result)
        }

        #expect(gate.waitForAdmissionEntry())
        #expect(fixture.controlBlock.beginClosing() == .applied)
        #expect(fixture.controlBlock.markStreamInvalidated() == .applied)
        #expect(
            fixture.controlBlock.markCallbackQueueDrained()
                == .waitingForLeases(activeLeaseCount: 1)
        )
        gate.releaseAdmission.signal()
        let result = try #require(gate.waitForCompletion())
        _ = requireAuthoritative(result)
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
    }

    private func capture(
        fixture: AdapterFixture,
        reportedEventCount: Int? = nil,
        paths: CFArray,
        flags: [FSEventStreamEventFlags],
        eventIDs: [FSEventStreamEventId]
    ) -> DarwinFSEventObservationCaptureResult {
        capture(
            adapter: fixture.adapter,
            expectedRegistration: fixture.registration,
            reportedEventCount: reportedEventCount ?? flags.count,
            eventPaths: Unmanaged.passUnretained(paths).toOpaque(),
            flags: flags,
            eventIDs: eventIDs
        )
    }

    private func capture(
        adapter: DarwinFSEventObservationAdapter,
        expectedRegistration: FSEventRegistrationToken,
        paths: CFArray,
        flags: [FSEventStreamEventFlags],
        eventIDs: [FSEventStreamEventId]
    ) -> DarwinFSEventObservationCaptureResult {
        capture(
            adapter: adapter,
            expectedRegistration: expectedRegistration,
            reportedEventCount: flags.count,
            eventPaths: Unmanaged.passUnretained(paths).toOpaque(),
            flags: flags,
            eventIDs: eventIDs
        )
    }

    private func capture(
        adapter: DarwinFSEventObservationAdapter,
        expectedRegistration: FSEventRegistrationToken,
        reportedEventCount: Int,
        eventPaths: UnsafeMutableRawPointer,
        flags: [FSEventStreamEventFlags],
        eventIDs: [FSEventStreamEventId]
    ) -> DarwinFSEventObservationCaptureResult {
        flags.withUnsafeBufferPointer { flagBuffer in
            eventIDs.withUnsafeBufferPointer { eventIDBuffer in
                adapter.capture(
                    expectedRegistration: expectedRegistration,
                    input: DarwinFSEventNativeCallbackInput(
                        capturedAt: ContinuousClock.now,
                        reportedEventCount: reportedEventCount,
                        eventPaths: eventPaths,
                        eventFlags: flagBuffer,
                        eventIDs: eventIDBuffer
                    )
                )
            }
        }
    }

    private func makeFixture(
        registrationGeneration: UInt64 = 19,
        captureLimits: FSEventCaptureLimits? = nil
    ) throws -> AdapterFixture {
        let registration = makeRegistration(registrationGeneration: registrationGeneration)
        let mailbox = try FilesystemObservationMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: registrationGeneration),
            declaredRegistrations: [registration],
            limits: mailboxLimits()
        )
        let controlBlock = try FSEventRegistrationControlBlock(
            registration: registration,
            watchRoot: WatchRoot(
                sourceID: registration.sourceID,
                declaredPath: "/workspace/repo",
                resolvedPath: "/private/workspace/repo"
            ),
            captureLimits: captureLimits ?? makeCaptureLimits(),
            callbackQueue: DispatchQueue(label: "test.fsevent.observation.capture")
        )
        return AdapterFixture(
            registration: registration,
            mailbox: mailbox,
            controlBlock: controlBlock,
            adapter: DarwinFSEventObservationAdapter(
                controlBlock: controlBlock,
                producer: mailbox.callbackProducerPort,
                signaler: mailbox.callbackSignalerPort
            )
        )
    }

    private func makeRegistration(registrationGeneration: UInt64) -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            registrationGeneration: registrationGeneration,
            rootGeneration: 5
        )
    }

    private func makeCaptureLimits(
        maximumInspected: Int = 8,
        maximumCopied: Int = 8,
        maximumBytes: Int = 4096,
        maximumSinglePathBytes: Int = 1024
    ) throws -> FSEventCaptureLimits {
        try FSEventCaptureLimits(
            maximumInspectedNativeRecords: maximumInspected,
            maximumCopiedRecords: maximumCopied,
            maximumCopiedUTF8Bytes: maximumBytes,
            maximumSinglePathUTF8Bytes: maximumSinglePathBytes
        )
    }

    private func mailboxLimits() -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 8,
            maximumRetainedItems: 64,
            maximumRetainedBytes: 65_536,
            maximumRetainedContributionsPerKey: 8,
            maximumRetainedItemsPerKey: 64,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: 8,
            maximumItemsPerLease: 64,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 65_536)
        )
    }

    private func ordinaryFlags(count: Int) -> [FSEventStreamEventFlags] {
        Array(
            repeating: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
            count: count
        )
    }
}

private struct AdapterFixture: Sendable {
    let registration: FSEventRegistrationToken
    let mailbox: FilesystemObservationMailbox
    let controlBlock: FSEventRegistrationControlBlock
    let adapter: DarwinFSEventObservationAdapter
}

private final class LeaseCountRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func record(_ snapshot: FSEventRegistrationLifecycleSnapshot) {
        guard case .open(let activeLeaseCount) = snapshot else { return }
        lock.withLock { $0 = activeLeaseCount }
    }

    var observedActiveLeaseCount: Int { lock.withLock { $0 } }
}

private final class CaptureAdmissionGate: @unchecked Sendable {
    private enum State: Sendable {
        case pending
        case completed(DarwinFSEventObservationCaptureResult)
    }

    let admissionEntered = DispatchSemaphore(value: 0)
    let releaseAdmission = DispatchSemaphore(value: 0)
    private let completed = DispatchSemaphore(value: 0)
    private let state = OSAllocatedUnfairLock(initialState: State.pending)

    func waitForAdmissionRelease() {
        if releaseAdmission.wait(timeout: .now() + 5) != .success {
            Issue.record("timed out waiting to release gated callback admission")
        }
    }

    func finish(with result: DarwinFSEventObservationCaptureResult) {
        state.withLock { $0 = .completed(result) }
        completed.signal()
    }

    func waitForAdmissionEntry() -> Bool {
        admissionEntered.wait(timeout: .now() + 5) == .success
    }

    func waitForCompletion() -> DarwinFSEventObservationCaptureResult? {
        guard completed.wait(timeout: .now() + 5) == .success else {
            Issue.record("timed out waiting for gated callback completion")
            return nil
        }
        return state.withLock { state in
            guard case .completed(let result) = state else { return nil }
            return result
        }
    }
}

private func requireAuthoritative(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FSEventObservation {
    guard
        case .admitted(offer: .authoritative(let observation), receipt: let receipt) = result,
        case .retained = receipt.disposition
    else {
        Issue.record("expected retained authoritative admission", sourceLocation: sourceLocation)
        preconditionFailure("expected authoritative callback admission")
    }
    return observation
}

private func requireRecovery(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> (FSEventObservation, FilesystemRecoveryEvidence) {
    guard
        case .admitted(
            offer: .requiresRecovery(let observation, let evidence),
            receipt: let receipt
        ) = result,
        case .retainedWithRecovery = receipt.disposition
    else {
        Issue.record("expected retained recovery admission", sourceLocation: sourceLocation)
        preconditionFailure("expected recovery callback admission")
    }
    return (observation, evidence)
}

private func expectRejection(
    _ result: DarwinFSEventObservationCaptureResult,
    expected: DarwinFSEventObservationCaptureRejection,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .rejected(let actual) = result else {
        Issue.record("expected callback rejection", sourceLocation: sourceLocation)
        return
    }
    #expect(actual == expected, sourceLocation: sourceLocation)
}

private func expectNoActiveLease(
    _ controlBlock: FSEventRegistrationControlBlock,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    switch controlBlock.lifecycleSnapshot {
    case .open(let activeLeaseCount), .closing(_, let activeLeaseCount):
        #expect(activeLeaseCount == 0, sourceLocation: sourceLocation)
    case .closed:
        break
    }
}

private func expectMalformedPrefix(
    _ observation: FSEventObservation,
    reportedCount: Int = 2,
    availableCount: Int,
    retainedPath: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        observation.totalRecordCount
            == .malformed(
                .nativeArrayCountMismatch(
                    reportedRecordCount: reportedCount,
                    availableRecordCount: availableCount
                )
            ),
        sourceLocation: sourceLocation
    )
    #expect(observation.inspectedNativeRecordCount == availableCount, sourceLocation: sourceLocation)
    #expect(observation.records.map(\.path) == [retainedPath], sourceLocation: sourceLocation)
    #expect(observation.completeness == .truncated([.malformedNativeShape]), sourceLocation: sourceLocation)
}
