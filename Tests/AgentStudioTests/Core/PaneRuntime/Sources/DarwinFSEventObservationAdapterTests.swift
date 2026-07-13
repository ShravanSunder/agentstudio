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

    @Test("exact binding mismatch rejects before native pointer inspection")
    func exactBindingMismatchRejectsBeforePointerInspection() throws {
        let fixture = try makeFixture()
        let mismatchedBinding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: fixture.startingNativeLifetime.binding.fleetMailboxIdentity,
            physicalSlotID: fixture.startingNativeLifetime.binding.physicalSlotID,
            identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
            registration: fixture.registration,
            controlBlockIdentity: fixture.startingNativeLifetime.binding.controlBlockIdentity
        )
        let mismatchedStartingNativeLifetime = FilesystemObservationStartingNativeLifetime(
            desiredRegistration: fixture.startingNativeLifetime.desiredRegistration,
            consumedReservation: fixture.startingNativeLifetime.consumedReservation,
            binding: mismatchedBinding,
            nativeGenerationIdentity: fixture.startingNativeLifetime.nativeGenerationIdentity
        )
        let mismatchedControlBlock = try FSEventRegistrationControlBlock(
            startingNativeLifetime: mismatchedStartingNativeLifetime,
            watchRoot: fixture.controlBlock.watchRoot,
            captureLimits: fixture.controlBlock.captureLimits,
            callbackQueue: fixture.controlBlock.callbackQueue
        )
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: mismatchedControlBlock,
            callbackAdmissionPort: fixture.callbackAdmissionPort
        )
        let result = capture(
            adapter: adapter,
            reportedEventCount: 1,
            eventPaths: UnsafeMutableRawPointer(bitPattern: 1)!,
            flags: [],
            eventIDs: []
        )

        expectRejection(result, expected: .callbackAuthority(.slotBindingMismatch))
        expectNoActiveLease(mismatchedControlBlock)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("foreign control block rejects before native pointer inspection")
    func foreignControlBlockRejectsBeforePointerInspection() throws {
        let fixture = try makeFixture()
        let foreignBinding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: fixture.startingNativeLifetime.binding.fleetMailboxIdentity,
            physicalSlotID: fixture.startingNativeLifetime.binding.physicalSlotID,
            identity: fixture.startingNativeLifetime.binding.identity,
            registration: fixture.registration,
            controlBlockIdentity: FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
        )
        let foreignStartingNativeLifetime = FilesystemObservationStartingNativeLifetime(
            desiredRegistration: fixture.startingNativeLifetime.desiredRegistration,
            consumedReservation: fixture.startingNativeLifetime.consumedReservation,
            binding: foreignBinding,
            nativeGenerationIdentity: fixture.startingNativeLifetime.nativeGenerationIdentity
        )
        let foreignControlBlock = try FSEventRegistrationControlBlock(
            startingNativeLifetime: foreignStartingNativeLifetime,
            watchRoot: fixture.controlBlock.watchRoot,
            captureLimits: fixture.controlBlock.captureLimits,
            callbackQueue: fixture.controlBlock.callbackQueue
        )
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: foreignControlBlock,
            callbackAdmissionPort: fixture.callbackAdmissionPort
        )

        let result = capture(
            adapter: adapter,
            reportedEventCount: 1,
            eventPaths: UnsafeMutableRawPointer(bitPattern: 1)!,
            flags: [],
            eventIDs: []
        )

        expectRejection(result, expected: .callbackAuthority(.foreignControlBlock))
        expectNoActiveLease(foreignControlBlock)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("registration mismatch rejects before native pointer inspection")
    func registrationMismatchRejectsBeforePointerInspection() throws {
        let fixture = try makeFixture()
        let mismatchedRegistration = makeRegistration(registrationGeneration: 20)
        let mismatchedBinding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: fixture.startingNativeLifetime.binding.fleetMailboxIdentity,
            physicalSlotID: fixture.startingNativeLifetime.binding.physicalSlotID,
            identity: fixture.startingNativeLifetime.binding.identity,
            registration: mismatchedRegistration,
            controlBlockIdentity: fixture.startingNativeLifetime.binding.controlBlockIdentity
        )
        let mismatchedStartingNativeLifetime = FilesystemObservationStartingNativeLifetime(
            desiredRegistration: FilesystemObservationDesiredRegistration(
                identity: fixture.startingNativeLifetime.desiredRegistration.identity,
                registration: mismatchedRegistration
            ),
            consumedReservation: fixture.startingNativeLifetime.consumedReservation,
            binding: mismatchedBinding,
            nativeGenerationIdentity: fixture.startingNativeLifetime.nativeGenerationIdentity
        )
        let mismatchedControlBlock = try FSEventRegistrationControlBlock(
            startingNativeLifetime: mismatchedStartingNativeLifetime,
            watchRoot: WatchRoot(
                sourceID: mismatchedRegistration.sourceID,
                declaredPath: fixture.controlBlock.watchRoot.declaredPath,
                resolvedPath: fixture.controlBlock.watchRoot.resolvedPath
            ),
            captureLimits: fixture.controlBlock.captureLimits,
            callbackQueue: fixture.controlBlock.callbackQueue
        )
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: mismatchedControlBlock,
            callbackAdmissionPort: fixture.callbackAdmissionPort
        )

        let result = capture(
            adapter: adapter,
            reportedEventCount: 1,
            eventPaths: UnsafeMutableRawPointer(bitPattern: 1)!,
            flags: [],
            eventIDs: []
        )

        expectRejection(result, expected: .callbackAuthority(.registrationMismatch))
        expectNoActiveLease(mismatchedControlBlock)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 0)
    }

    @Test("callback lease remains held through synchronous mailbox admission")
    func callbackLeaseIsHeldThroughAdmission() throws {
        let recorder = LeaseCountRecorder()
        let fixture = try makeFixture(synchronization: recorder)
        recorder.attach(to: fixture.controlBlock)
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: fixture.controlBlock,
            callbackAdmissionPort: fixture.callbackAdmissionPort
        )

        _ = requireAuthoritative(
            capture(
                adapter: adapter,
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
        let gate = CaptureAdmissionGate(pause: .afterAuthorityConsumption)
        let fixture = try makeFixture(synchronization: gate)
        let adapter = DarwinFSEventObservationAdapter(
            controlBlock: fixture.controlBlock,
            callbackAdmissionPort: fixture.callbackAdmissionPort
        )

        DispatchQueue(label: "test.fsevent.capture-race").async {
            let result = capture(
                adapter: adapter,
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

    @Test("callback lease remains held after offer until its wake is applied")
    func callbackLeaseIsHeldBetweenOfferAndWake() throws {
        let gate = CaptureAdmissionGate(pause: .afterMailboxOffer)
        let fixture = try makeFixture(synchronization: gate)

        DispatchQueue(label: "test.fsevent.capture-before-wake").async {
            let result = capture(
                adapter: fixture.adapter,
                paths: ["/offered"] as CFArray,
                flags: ordinaryFlags(count: 1),
                eventIDs: [101]
            )
            gate.finish(with: result)
        }

        #expect(gate.waitForAdmissionEntry())
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.retainedContributionCount == 1)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.doorbellState == .idle)
        #expect(fixture.controlBlock.beginClosing() == .applied)
        #expect(fixture.controlBlock.markStreamInvalidated() == .applied)
        #expect(
            fixture.controlBlock.markCallbackQueueDrained()
                == .waitingForLeases(activeLeaseCount: 1)
        )

        gate.releaseAdmission.signal()
        _ = requireAuthoritative(try #require(gate.waitForCompletion()))
        #expect(fixture.mailbox.lifecyclePort.diagnostics.doorbellState == .signalPending)
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
    }

    @Test("callback admission authority is one shot")
    func callbackAdmissionAuthorityIsOneShot() throws {
        let fixture = try makeFixture()
        let lease = try #require(acquiredLease(from: fixture.controlBlock))
        defer { _ = lease.release() }
        let inspectionLedger = NativeInspectionLedger()

        let preflight = FilesystemObservationCallbackPreflight(
            captureLimits: fixture.controlBlock.captureLimits
        )
        let first = fixture.callbackAdmissionPort.admit(
            using: lease,
            preflight: preflight
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }
        let second = fixture.callbackAdmissionPort.admit(
            using: lease,
            preflight: preflight
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }

        guard case .ignoredEmptyCallback = first else {
            Issue.record("first callback admission must consume the available authority")
            return
        }
        expectRejection(second, expected: .callbackAuthority(.alreadyConsumed))
        #expect(inspectionLedger.inspectionCount == 1)
        #expect(lease.release() == .released)
        expectNoActiveLease(fixture.controlBlock)
    }

    @Test("capture configuration mismatch rejects before native inspection")
    func captureConfigurationMismatchSkipsNativeInspection() throws {
        let fixture = try makeFixture()
        let lease = try #require(acquiredLease(from: fixture.controlBlock))
        defer { _ = lease.release() }
        let inspectionLedger = NativeInspectionLedger()
        let mismatchedCaptureLimits = try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 8,
            maximumCopiedRecords: 7,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        )

        let result = fixture.callbackAdmissionPort.admit(
            using: lease,
            preflight: FilesystemObservationCallbackPreflight(
                captureLimits: mismatchedCaptureLimits
            )
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }

        expectRejection(
            result,
            expected: .callbackAuthority(.captureConfigurationMismatch)
        )
        #expect(inspectionLedger.inspectionCount == 0)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered == 0)
    }

}
