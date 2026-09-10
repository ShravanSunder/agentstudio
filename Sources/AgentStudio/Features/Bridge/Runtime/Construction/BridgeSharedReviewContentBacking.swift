import AgentStudioGit
import Foundation

struct BridgeSharedReviewContentIdentity: Hashable, Sendable {
    let itemIdentity: String
    let role: BridgeContentHandle.Role
    let contentHash: String
}

enum BridgeSharedReviewContentSource: Sendable {
    case gitTarget(
        target: GitDiffTarget,
        path: String,
        declaredContentHash: String,
        declaredContentHashAlgorithm: String
    )
}

enum BridgeSharedReviewContentBackingError: Error, Equatable, Sendable {
    case invalidated
    case missingLocator
    case digestMismatch
}

final class BridgeSharedReviewContentBacking: @unchecked Sendable {
    final class ReadLease: @unchecked Sendable {
        let source: BridgeSharedReviewContentSource
        private let backing: BridgeSharedReviewContentBacking
        private let lock = NSLock()
        private var isSettled = false

        fileprivate init(
            source: BridgeSharedReviewContentSource,
            backing: BridgeSharedReviewContentBacking
        ) {
            self.source = source
            self.backing = backing
        }

        func settle() {
            let shouldSettle = lock.withLock { () -> Bool in
                guard !isSettled else { return false }
                isSettled = true
                return true
            }
            guard shouldSettle else { return }
            backing.settleRead()
        }
    }

    private struct State {
        var sourceByIdentity: [BridgeSharedReviewContentIdentity: BridgeSharedReviewContentSource]
        var isAcceptingReads: Bool
        var activeReadCount: Int
        var cleanupTask: Task<Void, Never>?
        var isCleanupComplete: Bool
        var cleanupWaiters: [CheckedContinuation<Void, Never>]
        var uninstallOperations: [@Sendable () async -> Void]
    }

    let artifactIdentity: UUID
    let retainedByteCount: Int
    private let lock = NSLock()
    private var state: State

    init(
        artifactIdentity: UUID,
        sourceByIdentity: [BridgeSharedReviewContentIdentity: BridgeSharedReviewContentSource]
    ) {
        self.artifactIdentity = artifactIdentity
        retainedByteCount = sourceByIdentity.reduce(0) { partialResult, entry in
            let identity = entry.key
            let sourceByteCount: Int
            switch entry.value {
            case .gitTarget(_, let path, let declaredContentHash, let declaredContentHashAlgorithm):
                sourceByteCount =
                    path.utf8.count
                    + declaredContentHash.utf8.count
                    + declaredContentHashAlgorithm.utf8.count
            }
            return partialResult
                + identity.itemIdentity.utf8.count
                + identity.role.rawValue.utf8.count
                + identity.contentHash.utf8.count
                + sourceByteCount
                + 96
        }
        state = State(
            sourceByIdentity: sourceByIdentity,
            isAcceptingReads: true,
            activeReadCount: 0,
            cleanupTask: nil,
            isCleanupComplete: false,
            cleanupWaiters: [],
            uninstallOperations: []
        )
    }

    var locatorCount: Int {
        lock.withLock { state.isAcceptingReads ? state.sourceByIdentity.count : 0 }
    }

    var uninstallOperationCount: Int {
        lock.withLock { state.uninstallOperations.count }
    }

    func source(
        for identity: BridgeSharedReviewContentIdentity
    ) throws -> BridgeSharedReviewContentSource {
        try lock.withLock {
            guard state.isAcceptingReads else {
                throw BridgeSharedReviewContentBackingError.invalidated
            }
            guard let source = state.sourceByIdentity[identity] else {
                throw BridgeSharedReviewContentBackingError.missingLocator
            }
            return source
        }
    }

    func acquireRead(
        for identity: BridgeSharedReviewContentIdentity
    ) throws -> ReadLease {
        try lock.withLock {
            guard state.isAcceptingReads else {
                throw BridgeSharedReviewContentBackingError.invalidated
            }
            guard let source = state.sourceByIdentity[identity] else {
                throw BridgeSharedReviewContentBackingError.missingLocator
            }
            state.activeReadCount += 1
            return ReadLease(source: source, backing: self)
        }
    }

    func invalidate() {
        lock.withLock {
            guard state.isAcceptingReads else { return }
            state.isAcceptingReads = false
            state.sourceByIdentity.removeAll(keepingCapacity: false)
            if state.activeReadCount == 0 {
                scheduleCleanupLocked()
            }
        }
    }

    func registerUninstallOperation(
        _ operation: @escaping @Sendable () async -> Void
    ) -> Bool {
        lock.withLock {
            guard state.isAcceptingReads else { return false }
            state.uninstallOperations.append(operation)
            return true
        }
    }

    func waitUntilInvalidationCleanupCompletes() async {
        if lock.withLock({ state.isCleanupComplete }) { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                guard !state.isCleanupComplete else { return true }
                state.cleanupWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    private func settleRead() {
        lock.withLock {
            precondition(state.activeReadCount > 0)
            state.activeReadCount -= 1
            if !state.isAcceptingReads, state.activeReadCount == 0 {
                scheduleCleanupLocked()
            }
        }
    }

    private func scheduleCleanupLocked() {
        guard state.cleanupTask == nil else { return }
        let uninstallOperations = state.uninstallOperations
        state.uninstallOperations.removeAll(keepingCapacity: false)
        // Cleanup must not run on the construction coordinator actor.
        // swiftlint:disable:next no_task_detached
        state.cleanupTask = Task.detached { [self] in
            for uninstallOperation in uninstallOperations {
                await uninstallOperation()
            }
            completeCleanup()
        }
    }

    private func completeCleanup() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            state.isCleanupComplete = true
            let waiters = state.cleanupWaiters
            state.cleanupWaiters.removeAll(keepingCapacity: false)
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }
}
