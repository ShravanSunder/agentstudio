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

    @Test("missing local activity evidence defers recurring fleet work")
    func missingLocalActivityEvidenceRetainsCorrectnessEligibility() async throws {
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
            ]
        )

        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        #expect(snapshot.sidebarAttendedWorktreeIds == [warmWorktreeID, inactiveWorktreeID])
        #expect(snapshot.warmRepositoryIds.isEmpty)
        #expect(snapshot.unknownRepositoryIds == [warmRepositoryID, inactiveRepositoryID])
        #expect(snapshot.locallyInactiveRepositoryIds.isEmpty)
        #expect(snapshot.warmAutomaticWorktreeIds.isEmpty)
        #expect(snapshot.unknownWorktreeIds == [warmWorktreeID, inactiveWorktreeID])
        #expect(snapshot.backgroundOnlyAutomaticWorktreeIds.isEmpty)
        #expect(snapshot.forgeDemandedWorktreeIds.isEmpty)
        #expect(snapshot.demandedRepositoryIds.isEmpty)
    }

    @Test("pre-hydration activity remains unknown and defers recurring fleet work")
    func preHydrationActivityRetainsCorrectnessEligibility() async throws {
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
            openWorktreeIds: [],
            repositoryIdByWorktreeId: input.repositoryIdByWorktreeId,
            activityTopology: input.activityTopology
        )

        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        #expect(snapshot.sidebarAttendedWorktreeIds == input.sidebarAttendedWorktreeIds)
        #expect(snapshot.warmRepositoryIds == Set(input.repositoryIdByWorktreeId.values))
        #expect(snapshot.locallyInactiveRepositoryIds.isEmpty)
        #expect(snapshot.unknownRepositoryIds.isEmpty)
        #expect(snapshot.warmAutomaticWorktreeIds == Set(input.repositoryIdByWorktreeId.keys))
        #expect(snapshot.unknownWorktreeIds.isEmpty)
        #expect(snapshot.backgroundOnlyAutomaticWorktreeIds.isEmpty)
        #expect(
            snapshot.forgeDemandedWorktreeIds
                == input.sidebarAttendedWorktreeIds.union(input.visibleActiveTabWorktreeIds)
        )
        #expect(snapshot.demandedRepositoryIds == Set(input.repositoryIdByWorktreeId.values))
    }

    @Test("settled unavailable activity admits unknown worktrees only to local background work")
    func unavailableActivityUsesOnlyLocalBackgroundEligibility() async throws {
        let receiver = RepositoryFactDemandReceiverProbe()
        let performanceRecorder = RepositoryFactDemandPerformanceRecorderSpy()
        let coordinator = RepositoryFactDemandCoordinator(
            performanceRecorder: performanceRecorder,
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let baseInput = try makeDemandInput(seed: 21)
        let input = RepositoryFactDemandInput(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: baseInput.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: baseInput.visibleActiveTabWorktreeIds,
            openWorktreeIds: [],
            repositoryIdByWorktreeId: baseInput.repositoryIdByWorktreeId,
            activityTopology: baseInput.activityTopology,
            localActivityHydrationDisposition: .unavailable
        )

        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        let everyWorktreeID = Set(input.repositoryIdByWorktreeId.keys)
        #expect(snapshot.warmRepositoryIds.isEmpty)
        #expect(snapshot.unknownRepositoryIds == Set(input.repositoryIdByWorktreeId.values))
        #expect(snapshot.warmAutomaticWorktreeIds.isEmpty)
        #expect(snapshot.unknownWorktreeIds == everyWorktreeID)
        #expect(snapshot.backgroundOnlyAutomaticWorktreeIds == everyWorktreeID)
        #expect(snapshot.automaticLocalGitWorktreeIds == everyWorktreeID)
        #expect(snapshot.forgeDemandedWorktreeIds.isEmpty)
        #expect(snapshot.demandedRepositoryIds.isEmpty)
        let performance = try #require(performanceRecorder.snapshots.last)
        #expect(performance.unknownRepositoryCurrent == 1)
        #expect(performance.unknownWorktreeCurrent == UInt64(everyWorktreeID.count))
        #expect(performance.unknownBackgroundOnlyCurrent == UInt64(everyWorktreeID.count))
        #expect(performance.unknownRemoteDemandCurrent == 0)
        #expect(performance.unknownForgeDemandCurrent == 0)
    }

    @Test("pre-hydration activity keeps remote demand for an open worktree")
    func preHydrationActivityKeepsOpenWorktreeRemoteDemand() async throws {
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator(
            wallClockNow: RepositoryFactDemandWallClock(referenceDate).read,
            delivery: { snapshot in
                await receiver.receive(snapshot)
            }
        )
        let input = try makeDemandInput(seed: 11)

        coordinator.accept(input)
        await coordinator.waitUntilIdle()

        let snapshot = try #require(await receiver.receivedSnapshots().last)
        #expect(snapshot.warmAutomaticWorktreeIds == input.openWorktreeIds)
        #expect(snapshot.unknownWorktreeIds.isEmpty)
        #expect(snapshot.backgroundOnlyAutomaticWorktreeIds.isEmpty)
        #expect(
            snapshot.forgeDemandedWorktreeIds
                == input.sidebarAttendedWorktreeIds.union(input.visibleActiveTabWorktreeIds)
        )
        #expect(snapshot.demandedRepositoryIds == Set(input.repositoryIdByWorktreeId.values))
    }

    @Test("open-pane changes reactivate a locally inactive repository")
    func openPaneChangesReactivateLocallyInactiveRepository() async throws {
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
        let inactiveActivity = try RepositoryLocalActivity(
            repositoryStableKey: repositoryStableKey,
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: referenceDate.addingTimeInterval(
                -AppPolicies.EntityRecency.applicationActivityHorizon - 1
            ),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let closedInput = RepositoryFactDemandInput(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: baseInput.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            repositoryIdByWorktreeId: baseInput.repositoryIdByWorktreeId,
            activityTopology: baseInput.activityTopology,
            localActivityHydrationDisposition: .authoritative,
            repositoryLocalActivityByStableKey: [repositoryStableKey: inactiveActivity]
        )
        coordinator.accept(closedInput)
        await coordinator.waitUntilIdle()
        #expect(clock.pendingSleepCount == 0)

        let openInput = RepositoryFactDemandInput(
            activePaneWorktreeId: closedInput.sidebarAttendedWorktreeIds.first,
            sidebarAttendedWorktreeIds: closedInput.sidebarAttendedWorktreeIds,
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: closedInput.sidebarAttendedWorktreeIds,
            repositoryIdByWorktreeId: closedInput.repositoryIdByWorktreeId,
            activityTopology: closedInput.activityTopology,
            localActivityHydrationDisposition: closedInput.localActivityHydrationDisposition,
            repositoryLocalActivityByStableKey: closedInput.repositoryLocalActivityByStableKey
        )
        coordinator.accept(openInput)
        await coordinator.waitUntilIdle()
        #expect(clock.pendingSleepCount == 0)

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
                        hydrationUnclassifiedCurrent: 1,
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
            unknownRepositoryIds: [],
            locallyInactiveRepositoryIds: [],
            warmAutomaticWorktreeIds: [
                activeWorktreeId,
                sidebarWorktreeId,
                activeTabWorktreeId,
                openWorktreeId,
            ],
            unknownWorktreeIds: [],
            backgroundOnlyAutomaticWorktreeIds: [],
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
