import Foundation

struct RepositoryFactDemandSnapshot: Equatable, Sendable {
    let activePaneWorktreeId: UUID?
    let sidebarAttendedWorktreeIds: Set<UUID>
    let visibleActiveTabWorktreeIds: Set<UUID>
    let openWorktreeIds: Set<UUID>
    let repositoryIdByWorktreeId: [UUID: UUID]

    static let empty = Self(
        activePaneWorktreeId: nil,
        sidebarAttendedWorktreeIds: [],
        visibleActiveTabWorktreeIds: [],
        openWorktreeIds: [],
        repositoryIdByWorktreeId: [:]
    )

    var forgeDemandedWorktreeIds: Set<UUID> {
        sidebarAttendedWorktreeIds.union(visibleActiveTabWorktreeIds)
    }

    var demandedRepositoryIds: Set<UUID> {
        Set(forgeDemandedWorktreeIds.compactMap { repositoryIdByWorktreeId[$0] })
    }

    var localGitAttentionWorktreeIds: Set<UUID> {
        var worktreeIds = openWorktreeIds
        worktreeIds.formUnion(sidebarAttendedWorktreeIds)
        worktreeIds.formUnion(visibleActiveTabWorktreeIds)
        if let activePaneWorktreeId {
            worktreeIds.insert(activePaneWorktreeId)
        }
        return worktreeIds
    }
}

@MainActor
final class RepositoryFactDemandCoordinator {
    typealias Delivery = @Sendable (RepositoryFactDemandSnapshot) async -> Void

    private let delivery: Delivery
    private var pendingSnapshot: RepositoryFactDemandSnapshot?
    private var pendingSnapshotMustDeliver = false
    private var inFlightSnapshot: RepositoryFactDemandSnapshot?
    private var lastDeliveredSnapshot: RepositoryFactDemandSnapshot?
    private var deliveryTask: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var acceptsSnapshots = true
    private var didStartShutdown = false

    init(delivery: @escaping Delivery) {
        self.delivery = delivery
    }

    func accept(_ snapshot: RepositoryFactDemandSnapshot) {
        guard acceptsSnapshots else { return }
        guard pendingSnapshot != snapshot else { return }
        if pendingSnapshot == nil, inFlightSnapshot == snapshot {
            return
        }
        if deliveryTask == nil, lastDeliveredSnapshot == snapshot {
            return
        }
        pendingSnapshot = snapshot
        pendingSnapshotMustDeliver = false
        startDeliveryTaskIfNeeded()
    }

    func waitUntilIdle() async {
        guard deliveryTask != nil else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func shutdown() async {
        guard !didStartShutdown else {
            await waitUntilIdle()
            return
        }
        didStartShutdown = true
        acceptsSnapshots = false
        pendingSnapshot = .empty
        pendingSnapshotMustDeliver = true
        startDeliveryTaskIfNeeded()
        await waitUntilIdle()
    }

    private func startDeliveryTaskIfNeeded() {
        guard deliveryTask == nil else { return }
        deliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while let nextSnapshot = self.pendingSnapshot {
                let mustDeliver = self.pendingSnapshotMustDeliver
                self.pendingSnapshot = nil
                self.pendingSnapshotMustDeliver = false
                if !mustDeliver, nextSnapshot == self.lastDeliveredSnapshot {
                    continue
                }

                self.inFlightSnapshot = nextSnapshot
                await self.delivery(nextSnapshot)
                self.inFlightSnapshot = nil
                guard !Task.isCancelled else {
                    self.finishDeliveryTask()
                    return
                }
                self.lastDeliveredSnapshot = nextSnapshot
            }
            self.finishDeliveryTask()
        }
    }

    private func finishDeliveryTask() {
        deliveryTask = nil
        let waiters = idleWaiters
        idleWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }
}
