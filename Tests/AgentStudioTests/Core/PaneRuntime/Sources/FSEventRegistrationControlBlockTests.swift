import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("FSEvent registration control block")
struct FSEventRegistrationControlBlockTests {
    @Test("lease-drain completion owns no asynchronous task or stream")
    func leaseDrainCompletionOwnsNoAsynchronousTaskOrStream() throws {
        let source = try controlBlockProductionSource()
        let completionImplementation = try #require(
            source.components(
                separatedBy: "private final class FSEventCallbackLeaseDrainCompletion"
            ).dropFirst().first?.components(
                separatedBy: "enum FSEventRegistrationControlBlockError"
            ).first
        )

        #expect(!completionImplementation.contains("Task"))
        #expect(!completionImplementation.contains("AsyncStream"))
    }

    @Test("retained control-block fleet creates no eager lease-drain waiters")
    func retainedFleetCreatesNoEagerLeaseDrainWaiters() throws {
        var retainedControlBlocks: [FSEventRegistrationControlBlock] = []
        retainedControlBlocks.reserveCapacity(301)

        for registrationGeneration in UInt64(0)..<301 {
            retainedControlBlocks.append(
                try makeControlBlockFixture(
                    registrationGeneration: registrationGeneration
                ).controlBlock
            )
        }

        #expect(retainedControlBlocks.count == 301)
        #expect(
            retainedControlBlocks.allSatisfy {
                $0.leaseDrainCompletionSnapshot == .pending(waiterCount: 0)
            }
        )
    }

    @Test("close acquisition, callback barrier, and zero leases advance exactly four phases")
    func closeAndZeroLeaseDrainPhases() async throws {
        let fixture = try makeControlBlockFixture(registrationGeneration: 20)

        #expect(fixture.controlBlock.beginClosing() == .applied)
        #expect(fixture.controlBlock.acquireCallbackLease() == .closing)
        #expect(fixture.controlBlock.markStreamInvalidated() == .applied)
        #expect(fixture.controlBlock.markCallbackQueueDrained() == .leasesDrained)
        await fixture.controlBlock.waitUntilLeasesDrained()
        await fixture.controlBlock.waitUntilLeasesDrained()
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
    }

    @Test("lease deinitialization safely releases its control-block count")
    func leaseDeinitializationReleasesControlBlockCount() throws {
        let fixture = try makeControlBlockFixture(registrationGeneration: 25)

        do {
            let lease = try #require(acquiredLease(from: fixture.controlBlock))
            #expect(lease.registration == fixture.controlBlock.registration)
            #expect(fixture.controlBlock.lifecycleSnapshot == .open(activeLeaseCount: 1))
        }

        #expect(fixture.controlBlock.lifecycleSnapshot == .open(activeLeaseCount: 0))
    }

    @Test("lease drain advances only after queue barrier and the last release")
    func leaseDrainRequiresQueueBarrierAndLastRelease() async throws {
        let fixture = try makeControlBlockFixture(registrationGeneration: 31)
        let firstLease = try #require(acquiredLease(from: fixture.controlBlock))
        let secondLease = try #require(acquiredLease(from: fixture.controlBlock))

        #expect(fixture.controlBlock.beginClosing() == .applied)
        #expect(fixture.controlBlock.markStreamInvalidated() == .applied)
        #expect(
            fixture.controlBlock.markCallbackQueueDrained()
                == .waitingForLeases(activeLeaseCount: 2)
        )
        #expect(firstLease.release() == .released)
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.callbackQueueDrained, activeLeaseCount: 1)
        )
        #expect(secondLease.release() == .released)
        await fixture.controlBlock.waitUntilLeasesDrained()
        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
    }

    @Test("callback barrier and final release race resumes the registered waiter exactly once")
    func callbackBarrierAndFinalReleaseRaceResumesWaiterExactlyOnce() async throws {
        let fixture = try makeControlBlockFixture(registrationGeneration: 32)
        let lease = try #require(acquiredLease(from: fixture.controlBlock))

        #expect(fixture.controlBlock.beginClosing() == .applied)
        #expect(fixture.controlBlock.markStreamInvalidated() == .applied)

        let waiter = Task {
            await fixture.controlBlock.waitUntilLeasesDrained()
        }
        for _ in 0..<10_000 {
            if fixture.controlBlock.leaseDrainCompletionSnapshot == .pending(waiterCount: 1) {
                break
            }
            await Task.yield()
        }
        #expect(
            fixture.controlBlock.leaseDrainCompletionSnapshot == .pending(waiterCount: 1)
        )

        let callbackBarrier = Task {
            fixture.controlBlock.markCallbackQueueDrained()
        }
        let finalRelease = Task {
            lease.release()
        }
        _ = await callbackBarrier.value
        #expect(await finalRelease.value == .released)
        await waiter.value

        #expect(
            fixture.controlBlock.lifecycleSnapshot
                == .closing(.leasesDrained, activeLeaseCount: 0)
        )
        #expect(
            fixture.controlBlock.leaseDrainCompletionSnapshot
                == .completed(resumedWaiterCount: 1)
        )

        await fixture.controlBlock.waitUntilLeasesDrained()
        #expect(
            fixture.controlBlock.leaseDrainCompletionSnapshot
                == .completed(resumedWaiterCount: 1)
        )
    }

    @Test("out-of-order close phases preserve the current lifecycle")
    func outOfOrderClosePhasesAreRejected() throws {
        let fixture = try makeControlBlockFixture(registrationGeneration: 40)

        #expect(
            fixture.controlBlock.markStreamInvalidated()
                == .invalidTransition(.open(activeLeaseCount: 0))
        )
        #expect(fixture.controlBlock.beginClosing() == .applied)
        #expect(
            fixture.controlBlock.markCallbackQueueDrained()
                == .invalidTransition(.closing(.admissionClosed, activeLeaseCount: 0))
        )
    }

    @Test("control block rejects a watch root owned by another source")
    func watchRootSourceMustMatchRegistration() throws {
        let startingNativeLifetime = try makeStartingNativeLifetime(registrationGeneration: 50)
        let otherSource = FilesystemSourceID(kind: .registeredWorktreeContent, rootID: UUID())

        #expect(throws: FSEventRegistrationControlBlockError.watchRootSourceMismatch) {
            try FSEventRegistrationControlBlock(
                startingNativeLifetime: startingNativeLifetime,
                watchRoot: WatchRoot(
                    sourceID: otherSource,
                    declaredPath: "/workspace/repo",
                    resolvedPath: "/private/workspace/repo"
                ),
                captureLimits: try makeCaptureLimits(),
                callbackQueue: DispatchQueue(label: "test.fsevent.mismatched")
            )
        }
    }
}

private struct FSEventRegistrationControlBlockFixture {
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let controlBlock: FSEventRegistrationControlBlock
}

private func makeControlBlockFixture(
    registrationGeneration: UInt64,
    sourceRootID: UUID = UUID()
) throws -> FSEventRegistrationControlBlockFixture {
    let startingNativeLifetime = try makeStartingNativeLifetime(
        registrationGeneration: registrationGeneration,
        sourceRootID: sourceRootID
    )
    let callbackQueue = DispatchQueue(label: "test.fsevent.\(registrationGeneration)")
    let controlBlock = try FSEventRegistrationControlBlock(
        startingNativeLifetime: startingNativeLifetime,
        watchRoot: WatchRoot(
            sourceID: startingNativeLifetime.binding.registration.sourceID,
            declaredPath: "/workspace/repo",
            resolvedPath: "/private/workspace/repo"
        ),
        captureLimits: makeCaptureLimits(),
        callbackQueue: callbackQueue
    )
    #expect(controlBlock.callbackQueue === callbackQueue)
    #expect(controlBlock.binding == startingNativeLifetime.binding)
    #expect(controlBlock.controlBlockIdentity == startingNativeLifetime.binding.controlBlockIdentity)
    return FSEventRegistrationControlBlockFixture(
        startingNativeLifetime: startingNativeLifetime,
        controlBlock: controlBlock
    )
}

private func makeStartingNativeLifetime(
    registrationGeneration: UInt64,
    sourceRootID: UUID = UUID()
) throws -> FilesystemObservationStartingNativeLifetime {
    let registry = try FilesystemObservationSlotRegistry(
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0
    )
    let registration = makeToken(
        registrationGeneration: registrationGeneration,
        sourceRootID: sourceRootID
    )
    guard case .enqueued = registry.recordDesiredRegistration(registration) else {
        throw FSEventRegistrationControlBlockTestError.fixtureConstructionFailed
    }
    guard case .selected(let selection) = registry.selectNextDesiredSource() else {
        throw FSEventRegistrationControlBlockTestError.fixtureConstructionFailed
    }
    guard
        case .committed(let startingNativeLifetime) =
            registry.beginNativeLifetime(selection.reservation)
    else {
        throw FSEventRegistrationControlBlockTestError.fixtureConstructionFailed
    }
    return startingNativeLifetime
}

private func rejection<TResult: Sendable>(
    _ result: FSEventCallbackLeaseAdmissionResult<TResult>
) -> FSEventCallbackLeaseAuthorityRejection? {
    guard case .authorityRejected(let rejection) = result else { return nil }
    return rejection
}

private func foreignBindingBasedOn(
    _ binding: FilesystemObservationSlotBinding
) -> FilesystemObservationSlotBinding {
    FilesystemObservationSlotBinding(
        fleetMailboxIdentity: binding.fleetMailboxIdentity,
        physicalSlotID: binding.physicalSlotID,
        identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
        registration: binding.registration,
        controlBlockIdentity: binding.controlBlockIdentity
    )
}

private func makeCaptureLimits() throws -> FSEventCaptureLimits {
    try FSEventCaptureLimits(
        maximumInspectedNativeRecords: 32,
        maximumCopiedRecords: 16,
        maximumCopiedUTF8Bytes: 4096,
        maximumSinglePathUTF8Bytes: 1024
    )
}

private func makeToken(
    registrationGeneration: UInt64,
    sourceRootID: UUID
) -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: sourceRootID
        ),
        registrationGeneration: registrationGeneration,
        rootGeneration: 4
    )
}

private enum FSEventRegistrationControlBlockTestError: Error {
    case fixtureConstructionFailed
}

private func controlBlockProductionSource() throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = (0..<6).reduce(testFileURL) { partialURL, _ in
        partialURL.deletingLastPathComponent()
    }
    let productionSourceURL = repositoryRoot.appendingPathComponent(
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/"
            + "FSEventRegistrationControlBlock.swift"
    )
    return try String(contentsOf: productionSourceURL, encoding: .utf8)
}
