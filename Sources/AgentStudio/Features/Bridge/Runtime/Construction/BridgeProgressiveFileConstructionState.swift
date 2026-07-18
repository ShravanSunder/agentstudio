import Foundation

struct BridgeProgressiveFileConstructionState {
    final class ReadCancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func cancel() {
            lock.withLock { cancelled = true }
        }
    }

    private struct PendingRead {
        let cursor: BridgeSharedFileSnapshotCursor
        let cancellationState: ReadCancellationState
        let continuation: CheckedContinuation<BridgeSharedFileSnapshotRead, any Error>
    }

    private struct PendingPreparationRead {
        let cancellationState: ReadCancellationState
        let continuation: CheckedContinuation<BridgeSharedFileSnapshotPreparation, any Error>
    }

    private var preparation: BridgeSharedFileSnapshotPreparation?
    private var windows: [BridgeSharedFileSnapshotWindow] = []
    private var nextWindowStartIndex = 0
    private var didAppendFinalWindow = false
    private var pendingReadsByLeaseNonce: [UInt64: PendingRead] = [:]
    private var pendingPreparationReadsByLeaseNonce: [UInt64: PendingPreparationRead] = [:]

    private(set) var retainedWindowByteCount = 0

    var retainedByteCount: Int {
        (preparation?.retainedByteCount ?? 0) + retainedWindowByteCount
    }

    var pendingReadCount: Int {
        pendingReadsByLeaseNonce.count + pendingPreparationReadsByLeaseNonce.count
    }

    mutating func publishPreparation(
        _ preparation: BridgeSharedFileSnapshotPreparation
    ) throws -> Set<UInt64> {
        guard self.preparation == nil else {
            throw BridgeWorktreeProductConstructionError.preparationAlreadyPublished
        }
        guard preparation.retainedByteCount >= 0 else {
            throw BridgeWorktreeProductConstructionError.invalidRetainedByteCount
        }
        self.preparation = preparation
        var deliveredLeaseNonces = Set<UInt64>()
        let pendingReads = pendingPreparationReadsByLeaseNonce
        pendingPreparationReadsByLeaseNonce.removeAll(keepingCapacity: false)
        for (leaseNonce, pendingRead) in pendingReads {
            if pendingRead.cancellationState.isCancelled {
                pendingRead.continuation.resume(throwing: CancellationError())
            } else {
                deliveredLeaseNonces.insert(leaseNonce)
                pendingRead.continuation.resume(returning: preparation)
            }
        }
        return deliveredLeaseNonces
    }

    mutating func enqueuePreparationRead(
        leaseNonce: UInt64,
        cancellationState: ReadCancellationState,
        continuation: CheckedContinuation<BridgeSharedFileSnapshotPreparation, any Error>
    ) -> Bool {
        guard !cancellationState.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return false
        }
        if let preparation {
            continuation.resume(returning: preparation)
            return true
        }
        guard pendingPreparationReadsByLeaseNonce[leaseNonce] == nil else {
            continuation.resume(
                throwing: BridgeWorktreeProductConstructionError.fileReadAlreadyPending
            )
            return false
        }
        pendingPreparationReadsByLeaseNonce[leaseNonce] = PendingPreparationRead(
            cancellationState: cancellationState,
            continuation: continuation
        )
        return false
    }

    func hasPendingPreparationRead(leaseNonce: UInt64) -> Bool {
        pendingPreparationReadsByLeaseNonce[leaseNonce] != nil
    }

    mutating func cancelPendingPreparationRead(leaseNonce: UInt64) {
        pendingPreparationReadsByLeaseNonce.removeValue(forKey: leaseNonce)?.continuation.resume(
            throwing: CancellationError()
        )
    }

    mutating func append(_ window: BridgeSharedFileSnapshotWindow) throws {
        guard preparation != nil else {
            throw BridgeWorktreeProductConstructionError.preparationRequired
        }
        guard !didAppendFinalWindow else {
            throw BridgeWorktreeProductConstructionError.fileWindowAfterFinal
        }
        guard window.ordinal == windows.count,
            window.startIndex == nextWindowStartIndex,
            window.discoveredRowCount == window.startIndex + window.rows.count,
            window.retainedByteCount >= 0
        else {
            throw BridgeWorktreeProductConstructionError.noncontiguousFileWindow
        }

        windows.append(window)
        nextWindowStartIndex = window.discoveredRowCount
        retainedWindowByteCount += window.retainedByteCount
        didAppendFinalWindow = window.isFinalWindow

        let readyLeaseNonces = pendingReadsByLeaseNonce.compactMap { leaseNonce, pendingRead in
            pendingRead.cursor.nextWindowOrdinal < windows.count ? leaseNonce : nil
        }
        for leaseNonce in readyLeaseNonces {
            guard let pendingRead = pendingReadsByLeaseNonce.removeValue(forKey: leaseNonce) else {
                continue
            }
            if pendingRead.cancellationState.isCancelled {
                pendingRead.continuation.resume(throwing: CancellationError())
            } else {
                pendingRead.continuation.resume(
                    returning: .window(windows[pendingRead.cursor.nextWindowOrdinal])
                )
            }
        }
    }

    mutating func enqueueRead(
        leaseNonce: UInt64,
        cursor: BridgeSharedFileSnapshotCursor,
        cancellationState: ReadCancellationState,
        continuation: CheckedContinuation<BridgeSharedFileSnapshotRead, any Error>
    ) {
        guard cursor.nextWindowOrdinal >= 0,
            cursor.nextWindowOrdinal <= windows.count
        else {
            continuation.resume(
                throwing: BridgeWorktreeProductConstructionError.invalidFileSnapshotCursor
            )
            return
        }
        guard !cancellationState.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        if cursor.nextWindowOrdinal < windows.count {
            continuation.resume(returning: .window(windows[cursor.nextWindowOrdinal]))
            return
        }
        guard pendingReadsByLeaseNonce[leaseNonce] == nil else {
            continuation.resume(
                throwing: BridgeWorktreeProductConstructionError.fileReadAlreadyPending
            )
            return
        }
        pendingReadsByLeaseNonce[leaseNonce] = PendingRead(
            cursor: cursor,
            cancellationState: cancellationState,
            continuation: continuation
        )
    }

    func hasPendingRead(leaseNonce: UInt64) -> Bool {
        pendingReadsByLeaseNonce[leaseNonce] != nil
    }

    mutating func cancelPendingRead(leaseNonce: UInt64) {
        pendingReadsByLeaseNonce.removeValue(forKey: leaseNonce)?.continuation.resume(
            throwing: CancellationError()
        )
    }

    mutating func failPendingReads(with error: any Error) {
        let pendingPreparationReads = pendingPreparationReadsByLeaseNonce.values
        pendingPreparationReadsByLeaseNonce.removeAll(keepingCapacity: false)
        for pendingRead in pendingPreparationReads {
            pendingRead.continuation.resume(throwing: error)
        }
        let pendingReads = pendingReadsByLeaseNonce.values
        pendingReadsByLeaseNonce.removeAll(keepingCapacity: false)
        for pendingRead in pendingReads {
            pendingRead.continuation.resume(throwing: error)
        }
    }

    func makeCompletedSnapshot(
        completion: BridgeSharedFileSnapshotCompletion
    ) throws -> BridgeSharedFileSnapshotBuild {
        guard let preparation,
            didAppendFinalWindow,
            completion.retainedNonwindowByteCount >= 0
        else {
            throw BridgeWorktreeProductConstructionError.finalFileWindowRequired
        }
        return BridgeSharedFileSnapshotBuild(
            preparation: preparation,
            orderedWindows: windows,
            retainedByteCount: retainedByteCount + completion.retainedNonwindowByteCount
        )
    }

    mutating func finishPendingReads(with snapshot: BridgeSharedFileSnapshotBuild) {
        let pendingReads = pendingReadsByLeaseNonce.values
        pendingReadsByLeaseNonce.removeAll(keepingCapacity: false)
        for pendingRead in pendingReads {
            if pendingRead.cancellationState.isCancelled {
                pendingRead.continuation.resume(throwing: CancellationError())
            } else {
                pendingRead.continuation.resume(returning: .completed(snapshot))
            }
        }
    }

    static func resumeReadyRead(
        snapshot: BridgeSharedFileSnapshotBuild,
        cursor: BridgeSharedFileSnapshotCursor,
        cancellationState: ReadCancellationState,
        continuation: CheckedContinuation<BridgeSharedFileSnapshotRead, any Error>
    ) {
        guard !cancellationState.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard cursor.nextWindowOrdinal >= 0,
            cursor.nextWindowOrdinal <= snapshot.orderedWindows.count
        else {
            continuation.resume(
                throwing: BridgeWorktreeProductConstructionError.invalidFileSnapshotCursor
            )
            return
        }
        if cursor.nextWindowOrdinal < snapshot.orderedWindows.count {
            continuation.resume(
                returning: .window(snapshot.orderedWindows[cursor.nextWindowOrdinal])
            )
        } else {
            continuation.resume(returning: .completed(snapshot))
        }
    }
}
