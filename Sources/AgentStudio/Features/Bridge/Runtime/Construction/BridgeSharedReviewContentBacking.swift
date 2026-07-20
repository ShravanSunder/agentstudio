import AgentStudioGit
import CryptoKit
import Foundation

struct BridgeSharedReviewContentIdentity: Hashable, Sendable {
    let itemIdentity: String
    let role: BridgeContentHandle.Role
    let contentHash: String
}

struct BridgeSharedReviewCapturedContentDescriptor: Sendable {
    let fileName: String
    let byteCount: Int
    let declaredContentHash: String
    let declaredContentHashAlgorithm: String
    let integritySHA256: String
}

enum BridgeSharedReviewImmutableContentSource: Sendable {
    case gitObject(
        target: GitDiffTarget,
        path: String,
        declaredContentHash: String,
        declaredContentHashAlgorithm: String
    )
    case capturedFile(BridgeSharedReviewCapturedContentDescriptor)
}

enum BridgeSharedReviewContentBackingError: Error, Equatable, Sendable {
    case invalidated
    case missingLocator
    case digestMismatch
    case invalidBackingPath
    case fileReadFailed
    case fileWriteFailed
}

final class BridgeSharedReviewContentBacking: @unchecked Sendable {
    final class ReadLease: @unchecked Sendable {
        let source: BridgeSharedReviewImmutableContentSource
        private let backing: BridgeSharedReviewContentBacking
        private let lock = NSLock()
        private var isSettled = false

        fileprivate init(
            source: BridgeSharedReviewImmutableContentSource,
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
        var sourceByIdentity: [BridgeSharedReviewContentIdentity: BridgeSharedReviewImmutableContentSource]
        var isAcceptingReads: Bool
        var activeReadCount: Int
        var cleanupTask: Task<Void, Never>?
        var isCleanupComplete: Bool
        var cleanupWaiters: [CheckedContinuation<Void, Never>]
        var uninstallOperations: [@Sendable () async -> Void]
    }

    let artifactIdentity: UUID
    let directoryURL: URL
    let capturedByteCount: Int
    private let lock = NSLock()
    private var state: State

    init(
        artifactIdentity: UUID,
        directoryURL: URL,
        sourceByIdentity: [BridgeSharedReviewContentIdentity: BridgeSharedReviewImmutableContentSource],
        capturedByteCount: Int
    ) {
        self.artifactIdentity = artifactIdentity
        self.directoryURL = directoryURL
        self.capturedByteCount = capturedByteCount
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
    ) throws -> BridgeSharedReviewImmutableContentSource {
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

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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
        let directoryURL = self.directoryURL
        let uninstallOperations = state.uninstallOperations
        state.uninstallOperations.removeAll(keepingCapacity: false)
        // Cleanup must not run on the construction coordinator actor.
        // swiftlint:disable:next no_task_detached
        state.cleanupTask = Task.detached { [self] in
            for uninstallOperation in uninstallOperations {
                await uninstallOperation()
            }
            try? FileManager.default.removeItem(at: directoryURL)
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
