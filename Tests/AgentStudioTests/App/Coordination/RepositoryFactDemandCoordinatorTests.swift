import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepositoryFactDemandCoordinator")
struct RepositoryFactDemandCoordinatorTests {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test("activity classification preserves membership while suppressing inactive automatic demand")
    func activityClassificationPrecedesAutomaticDemand() async throws {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000)
        let warmRepositoryID = seededUUID(1)
        let warmWorktreeID = seededUUID(2)
        let inactiveRepositoryID = seededUUID(3)
        let inactiveWorktreeID = seededUUID(4)
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let input = RepositoryFactDemandInput(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [warmWorktreeID, inactiveWorktreeID],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            repositoryIdByWorktreeId: [
                warmWorktreeID: warmRepositoryID,
                inactiveWorktreeID: inactiveRepositoryID,
            ],
            activityTopology: [
                RepositoryActivityTopology(
                    repositoryID: warmRepositoryID,
                    repositoryStableKey: "1111111111111111",
                    worktreeStableKeysByID: [warmWorktreeID: "2222222222222222"]
                ),
                RepositoryActivityTopology(
                    repositoryID: inactiveRepositoryID,
                    repositoryStableKey: "3333333333333333",
                    worktreeStableKeysByID: [inactiveWorktreeID: "4444444444444444"]
                ),
            ],
            recencyHydrationDisposition: .authoritative,
            applicationRecency: [
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: "1111111111111111"),
                    interaction: .opened,
                    lastInteractedAt: referenceDate
                )
            ]
        )

        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        #expect(snapshot.sidebarAttendedWorktreeIds == [warmWorktreeID, inactiveWorktreeID])
        #expect(snapshot.warmRepositoryIds == [warmRepositoryID])
        #expect(snapshot.locallyInactiveRepositoryIds == [inactiveRepositoryID])
        #expect(snapshot.warmAutomaticWorktreeIds == [warmWorktreeID])
        #expect(snapshot.forgeDemandedWorktreeIds == [warmWorktreeID])
        #expect(snapshot.demandedRepositoryIds == [warmRepositoryID])
    }

    @Test("pre-hydration input produces no automatic source eligibility")
    func preHydrationInputHasNoAutomaticEligibility() async throws {
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        var input = try makeDemandInput(seed: 1)
        input = RepositoryFactDemandInput(
            activePaneWorktreeId: input.activePaneWorktreeId,
            sidebarAttendedWorktreeIds: input.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: input.visibleActiveTabWorktreeIds,
            openWorktreeIds: input.openWorktreeIds,
            repositoryIdByWorktreeId: input.repositoryIdByWorktreeId,
            activityTopology: input.activityTopology,
            recencyHydrationDisposition: .pending,
            applicationRecency: []
        )

        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        #expect(snapshot.sidebarAttendedWorktreeIds == input.sidebarAttendedWorktreeIds)
        #expect(snapshot.warmRepositoryIds.isEmpty)
        #expect(snapshot.locallyInactiveRepositoryIds.isEmpty)
        #expect(snapshot.warmAutomaticWorktreeIds.isEmpty)
        #expect(snapshot.forgeDemandedWorktreeIds.isEmpty)
        #expect(snapshot.demandedRepositoryIds.isEmpty)
    }

    @Test("current inactivity boundary reclassifies without polling")
    func inactivityBoundaryReclassifiesLatestInput() async throws {
        let clock = TestPushClock()
        let wallClock = RepositoryFactDemandWallClock(referenceDate)
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: wallClock.read,
            sleepClock: clock,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let baseInput = try makeDemandInput(seed: 1)
        let repositoryStableKey = try #require(baseInput.activityTopology.first?.repositoryStableKey)
        let input = RepositoryFactDemandInput(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: baseInput.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            repositoryIdByWorktreeId: baseInput.repositoryIdByWorktreeId,
            activityTopology: baseInput.activityTopology,
            recencyHydrationDisposition: .authoritative,
            applicationRecency: [
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: repositoryStableKey),
                    interaction: .opened,
                    lastInteractedAt: referenceDate.addingTimeInterval(
                        -AppPolicies.EntityRecency.applicationActivityHorizon + 10
                    )
                )
            ]
        )

        coordinator.accept(input)
        await coordinator.waitUntilIdle()
        #expect(await receiver.receivedSnapshots().last?.warmRepositoryIds.isEmpty == false)
        await clock.waitForPendingSleepCount(atLeast: 1)

        wallClock.set(referenceDate.addingTimeInterval(11))
        clock.advance(by: .seconds(11))
        await receiver.waitUntilDeliveryStarts(ordinal: 2)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        #expect(snapshot.warmRepositoryIds.isEmpty)
        #expect(!snapshot.locallyInactiveRepositoryIds.isEmpty)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test("superseded inactivity boundary has no publication authority")
    func staleInactivityBoundaryIsCancelled() async throws {
        let clock = TestPushClock()
        let wallClock = RepositoryFactDemandWallClock(referenceDate)
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: wallClock.read,
            sleepClock: clock,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let baseInput = try makeDemandInput(seed: 1)
        let repositoryStableKey = try #require(baseInput.activityTopology.first?.repositoryStableKey)
        let closedInput = RepositoryFactDemandInput(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: baseInput.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            repositoryIdByWorktreeId: baseInput.repositoryIdByWorktreeId,
            activityTopology: baseInput.activityTopology,
            recencyHydrationDisposition: .authoritative,
            applicationRecency: [
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: repositoryStableKey),
                    interaction: .opened,
                    lastInteractedAt: referenceDate.addingTimeInterval(
                        -AppPolicies.EntityRecency.applicationActivityHorizon + 10
                    )
                )
            ]
        )
        coordinator.accept(closedInput)
        await coordinator.waitUntilIdle()
        await clock.waitForPendingSleepCount(atLeast: 1)

        let openInput = RepositoryFactDemandInput(
            activePaneWorktreeId: closedInput.sidebarAttendedWorktreeIds.first,
            sidebarAttendedWorktreeIds: closedInput.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: closedInput.sidebarAttendedWorktreeIds,
            repositoryIdByWorktreeId: closedInput.repositoryIdByWorktreeId,
            activityTopology: closedInput.activityTopology,
            recencyHydrationDisposition: .authoritative,
            applicationRecency: closedInput.applicationRecency
        )
        coordinator.accept(openInput)
        await coordinator.waitUntilIdle()
        #expect(clock.pendingSleepCount == 0)

        wallClock.set(referenceDate.addingTimeInterval(11))
        clock.advance(by: .seconds(11))
        for _ in 0..<100 {
            await Task.yield()
        }

        let snapshots = await receiver.receivedSnapshots()
        #expect(snapshots.count == 2)
        #expect(snapshots.last?.warmRepositoryIds.isEmpty == false)
        #expect(snapshots.last?.locallyInactiveRepositoryIds.isEmpty == true)
    }

    @Test("equal complete snapshots do not call the receiver twice")
    func equalSnapshotsAreSuppressedBeforeDelivery() async throws {
        let receiver = RepositoryFactDemandReceiverProbe()
        let performanceRecorder = RepositoryFactDemandPerformanceRecorderSpy()
        let coordinator = RepositoryFactDemandCoordinator(
            performanceRecorder: performanceRecorder,
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let input = try makeDemandInput(seed: 1)
        let snapshot = makeDemandSnapshot(seed: 1)

        coordinator.accept(input)
        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        #expect(await receiver.receivedSnapshots() == [snapshot])
        #expect(
            performanceRecorder.snapshots
                == [
                    RepositoryFactDemandPerformanceSnapshot(
                        projected: 2,
                        contentEqual: 1,
                        delivered: 1,
                        cleared: 0,
                        rejectedAfterShutdown: 0,
                        warmRepositoryCurrent: 1,
                        warmWorktreeCurrent: 4
                    )
                ]
        )
    }

    @Test("high-rate equal input flushes bounded aggregate snapshots")
    func equalInputTelemetryStaysBounded() async throws {
        let performanceRecorder = RepositoryFactDemandPerformanceRecorderSpy()
        let coordinator = RepositoryFactDemandCoordinator(
            performanceRecorder: performanceRecorder,
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { _ in }
        )
        let input = try makeDemandInput(seed: 1)

        coordinator.accept(input)
        await coordinator.waitUntilIdle()
        for _ in 0..<Int(AppPolicies.RepositoryFactDemand.telemetryFlushInputCount * 2) {
            coordinator.accept(input)
        }
        await coordinator.waitUntilIdle()

        #expect(performanceRecorder.snapshots.count == 3)
        #expect(performanceRecorder.snapshots.dropFirst().allSatisfy { $0.contentEqual == 64 })
    }

    @Test("A B A reversion is delivered after B is already in flight")
    func latestValueDeliveryPreservesReversion() async throws {
        let receiver = RepositoryFactDemandReceiverProbe(blockedDeliveryOrdinal: 2)
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let inputA = try makeDemandInput(seed: 1)
        let inputB = try makeDemandInput(seed: 2)
        let snapshotA = makeDemandSnapshot(seed: 1)
        let snapshotB = makeDemandSnapshot(seed: 2)

        coordinator.accept(inputA)
        await coordinator.waitUntilIdle()

        coordinator.accept(inputB)
        await receiver.waitUntilDeliveryStarts(ordinal: 2)
        coordinator.accept(inputA)
        await receiver.releaseBlockedDelivery()
        await coordinator.waitUntilIdle()

        #expect(await receiver.receivedSnapshots() == [snapshotA, snapshotB, snapshotA])
    }

    @Test("shutdown drains empty once and rejects late snapshots")
    func shutdownDrainsEmptyAndRejectsLateSnapshots() async throws {
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let populatedInput = try makeDemandInput(seed: 1)
        let populatedSnapshot = makeDemandSnapshot(seed: 1)

        coordinator.accept(populatedInput)
        await coordinator.waitUntilIdle()
        await coordinator.shutdown()
        coordinator.accept(try makeDemandInput(seed: 2))
        await coordinator.shutdown()

        #expect(await receiver.receivedSnapshots() == [populatedSnapshot, .empty])
    }

    private func makeDemandSnapshot(seed: UInt8) -> RepositoryFactDemandSnapshot {
        let activeWorktreeId = seededUUID(seed)
        let sidebarWorktreeId = seededUUID(seed &+ 1)
        let activeTabWorktreeId = seededUUID(seed &+ 2)
        let openWorktreeId = seededUUID(seed &+ 3)
        let repositoryId = seededUUID(seed &+ 4)
        return RepositoryFactDemandSnapshot(
            activePaneWorktreeId: activeWorktreeId,
            sidebarAttendedWorktreeIds: [sidebarWorktreeId],
            visibleActiveTabWorktreeIds: [activeTabWorktreeId],
            openWorktreeIds: [activeWorktreeId, sidebarWorktreeId, activeTabWorktreeId, openWorktreeId],
            repositoryIdByWorktreeId: [
                activeWorktreeId: repositoryId,
                sidebarWorktreeId: repositoryId,
                activeTabWorktreeId: repositoryId,
                openWorktreeId: repositoryId,
            ],
            warmRepositoryIds: [repositoryId],
            locallyInactiveRepositoryIds: [],
            warmAutomaticWorktreeIds: [
                activeWorktreeId,
                sidebarWorktreeId,
                activeTabWorktreeId,
                openWorktreeId,
            ],
            locallyInactiveWorktreeIds: []
        )
    }

    private func makeDemandInput(seed: UInt8) throws -> RepositoryFactDemandInput {
        let snapshot = makeDemandSnapshot(seed: seed)
        let repositoryID = try #require(snapshot.repositoryIdByWorktreeId.values.first)
        let repositoryStableKey = String(format: "%016x", seed)
        let stableKeysByWorktreeID = Dictionary(
            uniqueKeysWithValues: snapshot.repositoryIdByWorktreeId.keys.enumerated().map { index, worktreeID in
                (worktreeID, String(format: "%016x", Int(seed) + index + 100))
            }
        )
        return RepositoryFactDemandInput(
            activePaneWorktreeId: snapshot.activePaneWorktreeId,
            sidebarAttendedWorktreeIds: snapshot.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: snapshot.visibleActiveTabWorktreeIds,
            openWorktreeIds: snapshot.openWorktreeIds,
            repositoryIdByWorktreeId: snapshot.repositoryIdByWorktreeId,
            activityTopology: [
                RepositoryActivityTopology(
                    repositoryID: repositoryID,
                    repositoryStableKey: repositoryStableKey,
                    worktreeStableKeysByID: stableKeysByWorktreeID
                )
            ],
            recencyHydrationDisposition: .authoritative,
            applicationRecency: [
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: repositoryStableKey),
                    interaction: .opened,
                    lastInteractedAt: referenceDate
                )
            ]
        )
    }

    private func seededUUID(_ seed: UInt8) -> UUID {
        UUID(uuid: (seed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, seed))
    }
}

private final class RepositoryFactDemandWallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(_ now: Date) {
        storedNow = now
    }

    var now: Date {
        lock.withLock { storedNow }
    }

    func read() -> Date {
        now
    }

    func set(_ now: Date) {
        lock.withLock { storedNow = now }
    }
}

private final class RepositoryFactDemandPerformanceRecorderSpy:
    RepositoryFactDemandPerformanceRecording, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedSnapshots: [RepositoryFactDemandPerformanceSnapshot] = []

    var snapshots: [RepositoryFactDemandPerformanceSnapshot] {
        lock.withLock { recordedSnapshots }
    }

    func recordRepositoryFactDemandPerformanceSnapshot(
        _ snapshot: RepositoryFactDemandPerformanceSnapshot
    ) {
        lock.withLock { recordedSnapshots.append(snapshot) }
    }
}

private actor RepositoryFactDemandReceiverProbe {
    private let blockedDeliveryOrdinal: Int?
    private var snapshots: [RepositoryFactDemandSnapshot] = []
    private var deliveryStartWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var blockedDeliveryContinuation: CheckedContinuation<Void, Never>?

    init(blockedDeliveryOrdinal: Int? = nil) {
        self.blockedDeliveryOrdinal = blockedDeliveryOrdinal
    }

    func receive(_ snapshot: RepositoryFactDemandSnapshot) async {
        let deliveryOrdinal = snapshots.count + 1
        snapshots.append(snapshot)
        let waiters = deliveryStartWaiters.removeValue(forKey: deliveryOrdinal) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        guard blockedDeliveryOrdinal == deliveryOrdinal else { return }
        await withCheckedContinuation { continuation in
            blockedDeliveryContinuation = continuation
        }
    }

    func waitUntilDeliveryStarts(ordinal: Int) async {
        guard snapshots.count < ordinal else { return }
        await withCheckedContinuation { continuation in
            deliveryStartWaiters[ordinal, default: []].append(continuation)
        }
    }

    func releaseBlockedDelivery() {
        blockedDeliveryContinuation?.resume()
        blockedDeliveryContinuation = nil
    }

    func receivedSnapshots() -> [RepositoryFactDemandSnapshot] {
        snapshots
    }
}
