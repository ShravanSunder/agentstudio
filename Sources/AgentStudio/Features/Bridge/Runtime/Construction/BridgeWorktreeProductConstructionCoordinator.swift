import Foundation

actor BridgeWorktreeProductConstructionCoordinator {
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func cancel() {
            lock.withLock { cancelled = true }
        }
    }

    private struct BuildIdentity: Hashable {
        let key: BridgeWorktreeProductConstructionKey
        let epoch: BridgeWorktreeFreshnessEpoch
    }

    private enum EntryPhase {
        case building
        case ready(BridgeWorktreeProductConstructionArtifact)
        case tombstone
    }

    private struct Waiter {
        let leaseNonce: UInt64
        let cancellationState: CancellationState
        let continuation: CheckedContinuation<BridgeWorktreeProductConstructionLease, any Error>
    }

    private struct Entry {
        let identity: BuildIdentity
        let nonce: UInt64
        var phase: EntryPhase
        var isInFlight: Bool
        var waiters: [UInt64: Waiter]
        var activeLeaseNonces: Set<UInt64>
    }

    private let eventSink: BridgeWorktreeProductConstructionEventSink?
    private var currentEpochByWorktree: [BridgeWorktreeIdentityKey: BridgeWorktreeFreshnessEpoch] = [:]
    private var currentEntryNonceByIdentity: [BuildIdentity: UInt64] = [:]
    private var entriesByNonce: [UInt64: Entry] = [:]
    private var entryNonceByWaiterNonce: [UInt64: UInt64] = [:]
    private var nextEntryNonce: UInt64 = 1
    private var nextLeaseNonce: UInt64 = 1

    init(eventSink: BridgeWorktreeProductConstructionEventSink? = nil) {
        self.eventSink = eventSink
    }

    func acquire(
        key: BridgeWorktreeProductConstructionKey,
        build:
            @escaping @Sendable (BridgeWorktreeProductConstructionContext) async throws
            -> BridgeWorktreeProductConstructionArtifact
    ) async throws -> BridgeWorktreeProductConstructionLease {
        try Task.checkCancellation()
        let epoch = currentEpoch(for: key.worktree)
        let identity = BuildIdentity(key: key, epoch: epoch)
        let leaseNonce = takeNextLeaseNonce()
        let cancellationState = CancellationState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    identity: identity,
                    leaseNonce: leaseNonce,
                    cancellationState: cancellationState,
                    continuation: continuation,
                    build: build
                )
            }
        } onCancel: {
            cancellationState.cancel()
            Task {
                await self.cancelWaiter(leaseNonce: leaseNonce)
            }
        }
    }

    @discardableResult
    func invalidate(worktree: BridgeWorktreeIdentityKey) -> BridgeWorktreeFreshnessEpoch {
        let previousEpoch = currentEpoch(for: worktree)
        let advancedEpoch = BridgeWorktreeFreshnessEpoch(rawValue: previousEpoch.rawValue &+ 1)
        currentEpochByWorktree[worktree] = advancedEpoch

        let affectedEntryNonces = entriesByNonce.values
            .filter { $0.identity.key.worktree == worktree && $0.identity.epoch != advancedEpoch }
            .map(\.nonce)
        for entryNonce in affectedEntryNonces {
            guard var entry = entriesByNonce[entryNonce] else { continue }
            if currentEntryNonceByIdentity[entry.identity] == entryNonce {
                currentEntryNonceByIdentity.removeValue(forKey: entry.identity)
            }
            emit(.invalidated, entry: entry)
            switch entry.phase {
            case .building:
                failWaiters(in: &entry, with: BridgeWorktreeProductConstructionError.invalidated)
                if entry.isInFlight {
                    entry.phase = .tombstone
                    entriesByNonce[entryNonce] = entry
                    emit(.tombstoneCreated, entry: entry)
                } else {
                    removeEntry(entry)
                }
            case .ready:
                if entry.activeLeaseNonces.isEmpty {
                    removeEntry(entry)
                } else {
                    entriesByNonce[entryNonce] = entry
                }
            case .tombstone:
                entriesByNonce[entryNonce] = entry
            }
        }
        return advancedEpoch
    }

    func release(_ lease: BridgeWorktreeProductConstructionLease) {
        guard var entry = entriesByNonce[lease.entryNonce],
            entry.identity.key == lease.key,
            entry.identity.epoch == lease.epoch,
            entry.activeLeaseNonces.remove(lease.leaseNonce) != nil
        else { return }

        emit(.leaseReleased, entry: entry, leaseNonce: lease.leaseNonce)
        guard entry.activeLeaseNonces.isEmpty else {
            entriesByNonce[entry.nonce] = entry
            return
        }
        removeEntry(entry)
    }

    func snapshot() -> BridgeWorktreeProductConstructionSnapshot {
        var waiterCount = 0
        var leaseCount = 0
        var payloadCount = 0
        var inFlightCount = 0
        var locatorCount = 0
        var tombstoneCount = 0
        var retainedByteCount = 0

        for entry in entriesByNonce.values {
            waiterCount += entry.waiters.count
            leaseCount += entry.activeLeaseNonces.count
            inFlightCount += entry.isInFlight ? 1 : 0
            switch entry.phase {
            case .building:
                break
            case .ready(let artifact):
                payloadCount += 1
                locatorCount += artifact.contentLocatorCount
                retainedByteCount += artifact.retainedByteCount
            case .tombstone:
                tombstoneCount += 1
            }
        }

        return BridgeWorktreeProductConstructionSnapshot(
            entryCount: entriesByNonce.count,
            waiterCount: waiterCount,
            leaseCount: leaseCount,
            payloadCount: payloadCount,
            inFlightCount: inFlightCount,
            locatorCount: locatorCount,
            drainingTombstoneCount: tombstoneCount,
            retainedArtifactByteCount: retainedByteCount
        )
    }

    private func enqueue(
        identity: BuildIdentity,
        leaseNonce: UInt64,
        cancellationState: CancellationState,
        continuation: CheckedContinuation<BridgeWorktreeProductConstructionLease, any Error>,
        build:
            @escaping @Sendable (BridgeWorktreeProductConstructionContext) async throws
            -> BridgeWorktreeProductConstructionArtifact
    ) {
        if let entryNonce = currentEntryNonceByIdentity[identity],
            var entry = entriesByNonce[entryNonce]
        {
            switch entry.phase {
            case .building:
                let waiter = Waiter(
                    leaseNonce: leaseNonce,
                    cancellationState: cancellationState,
                    continuation: continuation
                )
                entry.waiters[leaseNonce] = waiter
                entryNonceByWaiterNonce[leaseNonce] = entryNonce
                entriesByNonce[entryNonce] = entry
                emit(.consumerJoined, entry: entry, leaseNonce: leaseNonce)
                return
            case .ready(let artifact):
                guard !cancellationState.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    emit(.consumerCancelled, entry: entry, leaseNonce: leaseNonce)
                    return
                }
                entry.activeLeaseNonces.insert(leaseNonce)
                entriesByNonce[entryNonce] = entry
                emit(.consumerJoined, entry: entry, leaseNonce: leaseNonce)
                continuation.resume(
                    returning: makeLease(
                        entry: entry,
                        leaseNonce: leaseNonce,
                        artifact: artifact
                    )
                )
                return
            case .tombstone:
                currentEntryNonceByIdentity.removeValue(forKey: identity)
            }
        }

        let entryNonce = takeNextEntryNonce()
        let waiter = Waiter(
            leaseNonce: leaseNonce,
            cancellationState: cancellationState,
            continuation: continuation
        )
        let entry = Entry(
            identity: identity,
            nonce: entryNonce,
            phase: .building,
            isInFlight: true,
            waiters: [leaseNonce: waiter],
            activeLeaseNonces: []
        )
        entriesByNonce[entryNonce] = entry
        currentEntryNonceByIdentity[identity] = entryNonce
        entryNonceByWaiterNonce[leaseNonce] = entryNonce
        emit(.buildStarted, entry: entry, leaseNonce: leaseNonce)

        let context = BridgeWorktreeProductConstructionContext(
            key: identity.key,
            epoch: identity.epoch,
            entryNonce: entryNonce
        )
        // Construction must not inherit this coordinator's actor isolation.
        // swiftlint:disable:next no_task_detached
        Task.detached { [weak self] in
            let result: Result<BridgeWorktreeProductConstructionArtifact, any Error>
            do {
                result = .success(try await build(context))
            } catch {
                result = .failure(error)
            }
            await self?.complete(entryNonce: entryNonce, result: result)
        }
    }

    private func complete(
        entryNonce: UInt64,
        result: Result<BridgeWorktreeProductConstructionArtifact, any Error>
    ) {
        guard var entry = entriesByNonce[entryNonce] else { return }
        entry.isInFlight = false

        guard case .building = entry.phase else {
            emit(.staleCompletionDropped, entry: entry)
            removeEntry(entry)
            return
        }
        guard currentEpoch(for: entry.identity.key.worktree) == entry.identity.epoch,
            currentEntryNonceByIdentity[entry.identity] == entryNonce
        else {
            failWaiters(in: &entry, with: BridgeWorktreeProductConstructionError.invalidated)
            emit(.staleCompletionDropped, entry: entry)
            removeEntry(entry)
            return
        }

        switch result {
        case .failure(let error):
            failWaiters(in: &entry, with: error)
            emit(.buildFailed, entry: entry)
            removeEntry(entry)
        case .success(let artifact):
            guard artifact.productKind == entry.identity.key.productKind else {
                failWaiters(in: &entry, with: BridgeWorktreeProductConstructionError.artifactKindMismatch)
                emit(.buildFailed, entry: entry)
                removeEntry(entry)
                return
            }
            let waiters = Array(entry.waiters.values)
            let activeWaiters = waiters.filter { !$0.cancellationState.isCancelled }
            let cancelledWaiters = waiters.filter { $0.cancellationState.isCancelled }
            entry.waiters.removeAll(keepingCapacity: false)
            for waiter in waiters {
                entryNonceByWaiterNonce.removeValue(forKey: waiter.leaseNonce)
            }
            for waiter in cancelledWaiters {
                waiter.continuation.resume(throwing: CancellationError())
                emit(.consumerCancelled, entry: entry, leaseNonce: waiter.leaseNonce)
            }
            for waiter in activeWaiters {
                entry.activeLeaseNonces.insert(waiter.leaseNonce)
            }
            guard !entry.activeLeaseNonces.isEmpty else {
                removeEntry(entry)
                return
            }
            entry.phase = .ready(artifact)
            entriesByNonce[entryNonce] = entry
            emit(.buildReady, entry: entry)
            for waiter in activeWaiters {
                waiter.continuation.resume(
                    returning: makeLease(
                        entry: entry,
                        leaseNonce: waiter.leaseNonce,
                        artifact: artifact
                    )
                )
            }
        }
    }

    private func cancelWaiter(leaseNonce: UInt64) {
        guard let entryNonce = entryNonceByWaiterNonce.removeValue(forKey: leaseNonce),
            var entry = entriesByNonce[entryNonce],
            let waiter = entry.waiters.removeValue(forKey: leaseNonce)
        else { return }

        waiter.continuation.resume(throwing: CancellationError())
        emit(.consumerCancelled, entry: entry, leaseNonce: leaseNonce)
        guard entry.waiters.isEmpty else {
            entriesByNonce[entryNonce] = entry
            return
        }
        if currentEntryNonceByIdentity[entry.identity] == entryNonce {
            currentEntryNonceByIdentity.removeValue(forKey: entry.identity)
        }
        if entry.isInFlight {
            entry.phase = .tombstone
            entriesByNonce[entryNonce] = entry
            emit(.tombstoneCreated, entry: entry)
        } else {
            removeEntry(entry)
        }
    }

    private func failWaiters(in entry: inout Entry, with error: any Error) {
        let waiters = entry.waiters.values
        entry.waiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            entryNonceByWaiterNonce.removeValue(forKey: waiter.leaseNonce)
            waiter.continuation.resume(throwing: error)
        }
    }

    private func makeLease(
        entry: Entry,
        leaseNonce: UInt64,
        artifact: BridgeWorktreeProductConstructionArtifact
    ) -> BridgeWorktreeProductConstructionLease {
        BridgeWorktreeProductConstructionLease(
            key: entry.identity.key,
            epoch: entry.identity.epoch,
            entryNonce: entry.nonce,
            leaseNonce: leaseNonce,
            artifact: artifact
        )
    }

    private func removeEntry(_ entry: Entry) {
        if currentEntryNonceByIdentity[entry.identity] == entry.nonce {
            currentEntryNonceByIdentity.removeValue(forKey: entry.identity)
        }
        for waiterNonce in entry.waiters.keys {
            entryNonceByWaiterNonce.removeValue(forKey: waiterNonce)
        }
        entriesByNonce.removeValue(forKey: entry.nonce)
        emit(.entryRemoved, entry: entry)
    }

    private func currentEpoch(for worktree: BridgeWorktreeIdentityKey) -> BridgeWorktreeFreshnessEpoch {
        if let epoch = currentEpochByWorktree[worktree] { return epoch }
        let initialEpoch = BridgeWorktreeFreshnessEpoch(rawValue: 1)
        currentEpochByWorktree[worktree] = initialEpoch
        return initialEpoch
    }

    private func takeNextEntryNonce() -> UInt64 {
        let nonce = nextEntryNonce
        nextEntryNonce &+= 1
        return nonce
    }

    private func takeNextLeaseNonce() -> UInt64 {
        let nonce = nextLeaseNonce
        nextLeaseNonce &+= 1
        return nonce
    }

    private func emit(
        _ kind: BridgeWorktreeProductConstructionEventKind,
        entry: Entry,
        leaseNonce: UInt64? = nil
    ) {
        eventSink?(
            BridgeWorktreeProductConstructionEvent(
                kind: kind,
                productKind: entry.identity.key.productKind,
                epoch: entry.identity.epoch,
                entryNonce: entry.nonce,
                leaseNonce: leaseNonce
            )
        )
    }
}
