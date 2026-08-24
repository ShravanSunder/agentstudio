import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepositoryFactDemandCoordinator")
struct RepositoryFactDemandCoordinatorTests {
    @Test("equal complete snapshots do not call the receiver twice")
    func equalSnapshotsAreSuppressedBeforeDelivery() async {
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator { snapshot in
            await receiver.receive(snapshot)
        }
        let snapshot = makeDemandSnapshot(seed: 1)

        coordinator.accept(snapshot)
        coordinator.accept(snapshot)
        await coordinator.waitUntilIdle()

        #expect(await receiver.receivedSnapshots() == [snapshot])
    }

    @Test("A B A reversion is delivered after B is already in flight")
    func latestValueDeliveryPreservesReversion() async {
        let receiver = RepositoryFactDemandReceiverProbe(blockedDeliveryOrdinal: 2)
        let coordinator = RepositoryFactDemandCoordinator { snapshot in
            await receiver.receive(snapshot)
        }
        let snapshotA = makeDemandSnapshot(seed: 1)
        let snapshotB = makeDemandSnapshot(seed: 2)

        coordinator.accept(snapshotA)
        await coordinator.waitUntilIdle()

        coordinator.accept(snapshotB)
        await receiver.waitUntilDeliveryStarts(ordinal: 2)
        coordinator.accept(snapshotA)
        await receiver.releaseBlockedDelivery()
        await coordinator.waitUntilIdle()

        #expect(await receiver.receivedSnapshots() == [snapshotA, snapshotB, snapshotA])
    }

    @Test("shutdown drains empty once and rejects late snapshots")
    func shutdownDrainsEmptyAndRejectsLateSnapshots() async {
        let receiver = RepositoryFactDemandReceiverProbe()
        let coordinator = RepositoryFactDemandCoordinator { snapshot in
            await receiver.receive(snapshot)
        }
        let populatedSnapshot = makeDemandSnapshot(seed: 1)

        coordinator.accept(populatedSnapshot)
        await coordinator.waitUntilIdle()
        await coordinator.shutdown()
        coordinator.accept(makeDemandSnapshot(seed: 2))
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
            ]
        )
    }

    private func seededUUID(_ seed: UInt8) -> UUID {
        UUID(uuid: (seed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, seed))
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
