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

    private enum EntryMode {
        case completionOnly
        case progressiveFile
    }

    private struct Waiter {
        let leaseNonce: UInt64
        let cancellationState: CancellationState
        let continuation: CheckedContinuation<BridgeWorktreeProductConstructionLease, any Error>
    }

    private struct Entry {
        let identity: BuildIdentity
        let nonce: UInt64
        let mode: EntryMode
        var phase: EntryPhase
        var isInFlight: Bool
        var waiters: [UInt64: Waiter]
        var activeLeaseNonces: Set<UInt64>
        var progressiveFileState: BridgeProgressiveFileConstructionState?
        var progressiveBuildTask: Task<Void, Never>?
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

    func acquireProgressiveFile(
        key: BridgeFileConstructionKey,
        build: @escaping BridgeSharedFileSnapshotBuildOperation
    ) async throws -> BridgeSharedFileSnapshotConsumerLease {
        try Task.checkCancellation()
        let constructionKey = BridgeWorktreeProductConstructionKey.file(key)
        let epoch = currentEpoch(for: key.owner.worktree)
        let identity = BuildIdentity(key: constructionKey, epoch: epoch)
        let leaseNonce = takeNextLeaseNonce()

        if let entryNonce = currentEntryNonceByIdentity[identity],
            var entry = entriesByNonce[entryNonce]
        {
            guard entry.mode == .progressiveFile else {
                throw BridgeWorktreeProductConstructionError.acquisitionModeMismatch
            }
            switch entry.phase {
            case .building, .ready:
                entry.activeLeaseNonces.insert(leaseNonce)
                entriesByNonce[entryNonce] = entry
                emit(.consumerJoined, entry: entry, leaseNonce: leaseNonce)
                return makeFileLease(entry: entry, leaseNonce: leaseNonce)
            case .tombstone:
                currentEntryNonceByIdentity.removeValue(forKey: identity)
            }
        }

        let entryNonce = takeNextEntryNonce()
        let entry = Entry(
            identity: identity,
            nonce: entryNonce,
            mode: .progressiveFile,
            phase: .building,
            isInFlight: true,
            waiters: [:],
            activeLeaseNonces: [leaseNonce],
            progressiveFileState: BridgeProgressiveFileConstructionState(),
            progressiveBuildTask: nil
        )
        entriesByNonce[entryNonce] = entry
        currentEntryNonceByIdentity[identity] = entryNonce
        emit(.buildStarted, entry: entry, leaseNonce: leaseNonce)
        startProgressiveFileBuild(entry: entry, build: build)
        return makeFileLease(entry: entry, leaseNonce: leaseNonce)
    }

    func nextFileSnapshotRead(
        for lease: BridgeSharedFileSnapshotConsumerLease,
        cursor: BridgeSharedFileSnapshotCursor
    ) async throws -> BridgeSharedFileSnapshotRead {
        try Task.checkCancellation()
        let cancellationState = BridgeProgressiveFileConstructionState.ReadCancellationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueueFileSnapshotRead(
                    for: lease,
                    cursor: cursor,
                    cancellationState: cancellationState,
                    continuation: continuation
                )
            }
        } onCancel: {
            cancellationState.cancel()
            Task {
                await self.cancelFileReadWaiter(leaseNonce: lease.leaseNonce)
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
                failFileReadWaiters(
                    in: &entry,
                    with: BridgeWorktreeProductConstructionError.invalidated
                )
                if entry.mode == .progressiveFile {
                    entry.progressiveBuildTask?.cancel()
                    entry.activeLeaseNonces.removeAll(keepingCapacity: false)
                    entry.progressiveFileState = nil
                }
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

    func release(_ lease: BridgeSharedFileSnapshotConsumerLease) {
        guard var entry = entriesByNonce[lease.entryNonce],
            entry.mode == .progressiveFile,
            entry.identity.key == .file(lease.key),
            entry.identity.epoch == lease.epoch,
            entry.activeLeaseNonces.remove(lease.leaseNonce) != nil
        else { return }

        entry.progressiveFileState?.cancelPendingRead(leaseNonce: lease.leaseNonce)
        emit(.leaseReleased, entry: entry, leaseNonce: lease.leaseNonce)
        guard entry.activeLeaseNonces.isEmpty else {
            entriesByNonce[entry.nonce] = entry
            return
        }
        guard case .building = entry.phase, entry.isInFlight else {
            removeEntry(entry)
            return
        }
        if currentEntryNonceByIdentity[entry.identity] == entry.nonce {
            currentEntryNonceByIdentity.removeValue(forKey: entry.identity)
        }
        failFileReadWaiters(in: &entry, with: CancellationError())
        entry.progressiveBuildTask?.cancel()
        entry.progressiveFileState = nil
        entry.phase = .tombstone
        entriesByNonce[entry.nonce] = entry
        emit(.tombstoneCreated, entry: entry)
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
            waiterCount +=
                entry.waiters.count
                + (entry.progressiveFileState?.pendingReadCount ?? 0)
            leaseCount += entry.activeLeaseNonces.count
            inFlightCount += entry.isInFlight ? 1 : 0
            switch entry.phase {
            case .building:
                retainedByteCount += entry.progressiveFileState?.retainedByteCount ?? 0
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
            guard entry.mode == .completionOnly else {
                continuation.resume(
                    throwing: BridgeWorktreeProductConstructionError.acquisitionModeMismatch
                )
                return
            }
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
            mode: .completionOnly,
            phase: .building,
            isInFlight: true,
            waiters: [leaseNonce: waiter],
            activeLeaseNonces: [],
            progressiveFileState: nil,
            progressiveBuildTask: nil
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

    private func startProgressiveFileBuild(
        entry: Entry,
        build: @escaping BridgeSharedFileSnapshotBuildOperation
    ) {
        let context = BridgeWorktreeProductConstructionContext(
            key: entry.identity.key,
            epoch: entry.identity.epoch,
            entryNonce: entry.nonce
        )
        let publisher = BridgeSharedFileSnapshotPublisher(
            preparationSink: { [weak self] preparation in
                guard let self else {
                    throw BridgeWorktreeProductConstructionError.invalidated
                }
                try await self.publishFilePreparation(
                    preparation,
                    entryNonce: entry.nonce
                )
            },
            windowSink: { [weak self] window in
                guard let self else {
                    throw BridgeWorktreeProductConstructionError.invalidated
                }
                try await self.appendFileWindow(window, entryNonce: entry.nonce)
            }
        )
        // Construction must not inherit this coordinator's actor isolation.
        // swiftlint:disable:next no_task_detached
        let task = Task.detached { [weak self] in
            let result: Result<BridgeSharedFileSnapshotCompletion, any Error>
            do {
                result = .success(try await build(context, publisher))
            } catch {
                result = .failure(error)
            }
            await self?.completeProgressiveFile(entryNonce: entry.nonce, result: result)
        }
        guard var currentEntry = entriesByNonce[entry.nonce],
            currentEntry.mode == .progressiveFile
        else {
            task.cancel()
            return
        }
        currentEntry.progressiveBuildTask = task
        entriesByNonce[entry.nonce] = currentEntry
    }

    private func publishFilePreparation(
        _ preparation: BridgeSharedFileSnapshotPreparation,
        entryNonce: UInt64
    ) throws {
        guard var entry = currentProgressiveFileBuildingEntry(entryNonce: entryNonce),
            var state = entry.progressiveFileState
        else {
            throw BridgeWorktreeProductConstructionError.invalidated
        }
        try state.publishPreparation(preparation)
        entry.progressiveFileState = state
        entriesByNonce[entryNonce] = entry
        emit(.filePreparationPublished, entry: entry)
    }

    private func appendFileWindow(
        _ window: BridgeSharedFileSnapshotWindow,
        entryNonce: UInt64
    ) throws {
        guard var entry = currentProgressiveFileBuildingEntry(entryNonce: entryNonce),
            var state = entry.progressiveFileState
        else {
            throw BridgeWorktreeProductConstructionError.invalidated
        }
        try state.append(window)
        entry.progressiveFileState = state
        entriesByNonce[entryNonce] = entry
        emit(.fileWindowAppended, entry: entry)
    }

    private func enqueueFileSnapshotRead(
        for lease: BridgeSharedFileSnapshotConsumerLease,
        cursor: BridgeSharedFileSnapshotCursor,
        cancellationState: BridgeProgressiveFileConstructionState.ReadCancellationState,
        continuation: CheckedContinuation<BridgeSharedFileSnapshotRead, any Error>
    ) {
        guard var entry = entryForFileLease(lease) else {
            if isInvalidatedFileLease(lease) {
                continuation.resume(
                    throwing: BridgeWorktreeProductConstructionError.invalidated
                )
                return
            }
            continuation.resume(
                throwing: BridgeWorktreeProductConstructionError.invalidFileConsumerLease
            )
            return
        }
        switch entry.phase {
        case .building:
            guard var state = entry.progressiveFileState else {
                continuation.resume(throwing: BridgeWorktreeProductConstructionError.invalidated)
                return
            }
            state.enqueueRead(
                leaseNonce: lease.leaseNonce,
                cursor: cursor,
                cancellationState: cancellationState,
                continuation: continuation
            )
            entry.progressiveFileState = state
            entriesByNonce[entry.nonce] = entry
        case .ready(let artifact):
            guard case .fileSnapshot(let snapshot) = artifact else {
                continuation.resume(
                    throwing: BridgeWorktreeProductConstructionError.artifactKindMismatch
                )
                return
            }
            BridgeProgressiveFileConstructionState.resumeReadyRead(
                snapshot: snapshot,
                cursor: cursor,
                cancellationState: cancellationState,
                continuation: continuation
            )
        case .tombstone:
            continuation.resume(throwing: BridgeWorktreeProductConstructionError.invalidated)
        }
    }

    private func completeProgressiveFile(
        entryNonce: UInt64,
        result: Result<BridgeSharedFileSnapshotCompletion, any Error>
    ) {
        guard var entry = entriesByNonce[entryNonce] else { return }
        entry.isInFlight = false
        guard entry.mode == .progressiveFile, case .building = entry.phase else {
            emit(.staleCompletionDropped, entry: entry)
            removeEntry(entry)
            return
        }
        guard currentEpoch(for: entry.identity.key.worktree) == entry.identity.epoch,
            currentEntryNonceByIdentity[entry.identity] == entryNonce
        else {
            failFileReadWaiters(
                in: &entry,
                with: BridgeWorktreeProductConstructionError.invalidated
            )
            emit(.staleCompletionDropped, entry: entry)
            removeEntry(entry)
            return
        }

        switch result {
        case .failure(let error):
            failFileReadWaiters(in: &entry, with: error)
            entry.activeLeaseNonces.removeAll(keepingCapacity: false)
            emit(.buildFailed, entry: entry)
            removeEntry(entry)
        case .success(let completion):
            guard var state = entry.progressiveFileState else {
                failFileReadWaiters(
                    in: &entry,
                    with: BridgeWorktreeProductConstructionError.invalidated
                )
                removeEntry(entry)
                return
            }
            let snapshot: BridgeSharedFileSnapshotBuild
            do {
                snapshot = try state.makeCompletedSnapshot(completion: completion)
            } catch {
                failFileReadWaiters(in: &entry, with: error)
                entry.activeLeaseNonces.removeAll(keepingCapacity: false)
                emit(.buildFailed, entry: entry)
                removeEntry(entry)
                return
            }
            entry.progressiveFileState = nil
            guard !entry.activeLeaseNonces.isEmpty else {
                state.failPendingReads(with: CancellationError())
                removeEntry(entry)
                return
            }
            entry.phase = .ready(.fileSnapshot(snapshot))
            entriesByNonce[entryNonce] = entry
            emit(.buildReady, entry: entry)
            state.finishPendingReads(with: snapshot)
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

    private func cancelFileReadWaiter(leaseNonce: UInt64) {
        guard
            let entryNonce = entriesByNonce.values.first(where: {
                $0.progressiveFileState?.hasPendingRead(leaseNonce: leaseNonce) == true
            })?.nonce,
            var entry = entriesByNonce[entryNonce],
            var state = entry.progressiveFileState
        else { return }
        state.cancelPendingRead(leaseNonce: leaseNonce)
        entry.progressiveFileState = state
        entriesByNonce[entryNonce] = entry
    }

    private func failWaiters(in entry: inout Entry, with error: any Error) {
        let waiters = entry.waiters.values
        entry.waiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            entryNonceByWaiterNonce.removeValue(forKey: waiter.leaseNonce)
            waiter.continuation.resume(throwing: error)
        }
    }

    private func failFileReadWaiters(in entry: inout Entry, with error: any Error) {
        guard var state = entry.progressiveFileState else { return }
        state.failPendingReads(with: error)
        entry.progressiveFileState = state
    }

    private func currentProgressiveFileBuildingEntry(entryNonce: UInt64) -> Entry? {
        guard let entry = entriesByNonce[entryNonce],
            entry.mode == .progressiveFile,
            case .building = entry.phase,
            currentEpoch(for: entry.identity.key.worktree) == entry.identity.epoch,
            currentEntryNonceByIdentity[entry.identity] == entryNonce
        else { return nil }
        return entry
    }

    private func entryForFileLease(_ lease: BridgeSharedFileSnapshotConsumerLease) -> Entry? {
        guard let entry = entriesByNonce[lease.entryNonce],
            entry.mode == .progressiveFile,
            entry.identity.key == .file(lease.key),
            entry.identity.epoch == lease.epoch,
            entry.activeLeaseNonces.contains(lease.leaseNonce)
        else { return nil }
        return entry
    }

    private func isInvalidatedFileLease(_ lease: BridgeSharedFileSnapshotConsumerLease) -> Bool {
        if lease.epoch != currentEpoch(for: lease.key.owner.worktree) {
            return true
        }
        guard let entry = entriesByNonce[lease.entryNonce],
            entry.mode == .progressiveFile,
            entry.identity.key == .file(lease.key),
            entry.identity.epoch == lease.epoch,
            case .tombstone = entry.phase
        else { return false }
        return true
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

    private func makeFileLease(
        entry: Entry,
        leaseNonce: UInt64
    ) -> BridgeSharedFileSnapshotConsumerLease {
        guard case .file(let key) = entry.identity.key else {
            preconditionFailure("Progressive File entry has a non-File construction key")
        }
        return BridgeSharedFileSnapshotConsumerLease(
            key: key,
            epoch: entry.identity.epoch,
            entryNonce: entry.nonce,
            leaseNonce: leaseNonce
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
