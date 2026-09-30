import AgentStudioInfrastructure
import Foundation

private enum BridgePaneCommentBatchNotification: Sendable {
    case invalidation(Set<WorktreeAnnotationCatalogRange>)
    case resnapshot
    case unavailable

    func merging(displaced: Self) -> Self {
        switch (self, displaced) {
        case (.unavailable, _), (_, .unavailable): .unavailable
        case (.resnapshot, _), (_, .resnapshot): .resnapshot
        case (.invalidation(let newest), .invalidation(let older)):
            .invalidation(newest.union(older))
        }
    }
}

actor BridgePaneAnnotationNotificationSource {
    private struct AdmittedBatchScope: Sendable {
        let revision: Int
    }

    private let service: WorktreeAnnotationServiceActor?
    private let worktreeID: String
    private var batchNotificationByHandle: [String: AsyncStream<BridgePaneCommentBatchNotification>.Continuation] = [:]
    private var batchPublisherByHandle: [String: BridgeProductCommentCatalogPublisher] = [:]
    private var admittedBatchScopeByHandle: [String: AdmittedBatchScope] = [:]
    private var firstScopeWaiterByHandle: [String: AsyncStream<Void>.Continuation] = [:]
    private var firstScopeWaiterObserversByHandle: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var retiredBatchHandles: Set<String> = []
    private var pendingResnapshotHandles: Set<String> = []

    static let unavailable = BridgePaneAnnotationNotificationSource(
        service: nil,
        worktreeID: ""
    )

    init(
        service: WorktreeAnnotationServiceActor?,
        worktreeID: String
    ) {
        self.service = service
        self.worktreeID = worktreeID
    }

    func admittedWorktreeID() -> String? {
        service == nil ? nil : worktreeID
    }

    /// Mirrors one accepted E4 scope. The view handle remains the lifetime;
    /// the subject set is the interest captured by N10 behind the W4 barrier.
    func acceptBatchScope(
        handle: String,
        worktreeID scopedWorktreeID: String,
        scopeRevision: Int
    ) async throws {
        guard service != nil, scopedWorktreeID == worktreeID, !handle.isEmpty, scopeRevision > 0,
            !retiredBatchHandles.contains(handle)
        else {
            throw WorktreeAnnotationServiceError.unavailable
        }
        if let current = admittedBatchScopeByHandle[handle], scopeRevision <= current.revision {
            return
        }
        admittedBatchScopeByHandle[handle] = .init(revision: scopeRevision)
        firstScopeWaiterByHandle[handle]?.yield(())
        if let publisher = batchPublisherByHandle[handle] {
            _ = await publisher.acceptScope(revision: scopeRevision)
        }
    }

    func releaseProducerBatchScope(handle: String) async {
        admittedBatchScopeByHandle.removeValue(forKey: handle)
        firstScopeWaiterByHandle.removeValue(forKey: handle)?.finish()
        for observer in firstScopeWaiterObserversByHandle.removeValue(forKey: handle) ?? [] {
            observer.resume()
        }
        pendingResnapshotHandles.remove(handle)
        batchNotificationByHandle.removeValue(forKey: handle)?.finish()
        if let publisher = batchPublisherByHandle.removeValue(forKey: handle) {
            await publisher.retire()
        }
    }

    func retireBatchView(handle: String) async {
        retiredBatchHandles.insert(handle)
        await releaseProducerBatchScope(handle: handle)
    }

    /// Observation seam for callers that need to know E3 is waiting on E4.
    func waitUntilFirstBatchScopeIsNeeded(handle: String) async {
        if firstScopeWaiterByHandle[handle] != nil || retiredBatchHandles.contains(handle) { return }
        await withCheckedContinuation { continuation in
            firstScopeWaiterObserversByHandle[handle, default: []].append(continuation)
        }
    }

    func requestBatchResnapshot(handle: String) {
        guard admittedBatchScopeByHandle[handle] != nil else { return }
        guard let continuation = batchNotificationByHandle[handle] else {
            pendingResnapshotHandles.insert(handle)
            return
        }
        enqueueBatchNotification(.resnapshot, into: continuation)
    }

    /// N10 observes invalidations before its first current-row capture. Each
    /// complete range read installs through one publisher before the next read.
    func openBatch(
        handle: String,
        deliver: @Sendable (BridgeProductCommentCatalogBatch, BridgeProductBatchMode) async throws -> Void
    ) async throws {
        guard let service else {
            throw WorktreeAnnotationServiceError.unavailable
        }
        _ = try await waitForFirstAdmittedBatchScope(handle: handle)
        let capturedWorktreeID = worktreeID
        let observer = await service.registerCatalogInvalidationObserver(worktreeID: capturedWorktreeID)
        if Task.isCancelled {
            await service.removeCatalogInvalidationObserver(token: observer.token)
            throw CancellationError()
        }
        guard let admittedScope = admittedBatchScopeByHandle[handle] else {
            await service.removeCatalogInvalidationObserver(token: observer.token)
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let (notifications, notificationContinuation) = AsyncStream.makeStream(
            of: BridgePaneCommentBatchNotification.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        batchNotificationByHandle[handle] = notificationContinuation
        if pendingResnapshotHandles.remove(handle) != nil {
            enqueueBatchNotification(.resnapshot, into: notificationContinuation)
        }
        let forwarder = Task {
            for await invalidation in observer.stream {
                guard invalidation.worktreeID == capturedWorktreeID else {
                    enqueueBatchNotification(.unavailable, into: notificationContinuation)
                    break
                }
                enqueueBatchNotification(.invalidation(invalidation.ranges), into: notificationContinuation)
            }
        }
        let publisher = BridgeProductCommentCatalogPublisher(
            handle: handle,
            scopeRevision: admittedScope.revision,
            readCurrent: { range in
                try await service.captureCurrentCatalogRange(
                    worktreeID: capturedWorktreeID,
                    range: range
                )
            }
        )
        batchPublisherByHandle[handle] = publisher
        do {
            if let snapshot = try await publisher.captureSnapshot() {
                try await deliver(snapshot, .snapshot)
            }
            for await notification in notifications {
                try Task.checkCancellation()
                switch notification {
                case .resnapshot:
                    guard let snapshot = try await publisher.captureSnapshot() else { continue }
                    try await deliver(snapshot, .snapshot)
                case .invalidation(let ranges):
                    for range in ranges { await publisher.invalidate(range) }
                    while await publisher.pendingDirtyRangeCount() > 0 {
                        guard let batch = try await publisher.captureDirty() else {
                            throw WorktreeAnnotationServiceError.staleSourceEpoch
                        }
                        try await deliver(batch, .change)
                    }
                case .unavailable:
                    throw WorktreeAnnotationServiceError.unavailable
                }
            }
            batchNotificationByHandle.removeValue(forKey: handle)
            batchPublisherByHandle.removeValue(forKey: handle)
            notificationContinuation.finish()
            await service.removeCatalogInvalidationObserver(token: observer.token)
            forwarder.cancel()
            await forwarder.value
        } catch {
            batchNotificationByHandle.removeValue(forKey: handle)
            batchPublisherByHandle.removeValue(forKey: handle)
            notificationContinuation.finish()
            await service.removeCatalogInvalidationObserver(token: observer.token)
            forwarder.cancel()
            await forwarder.value
            throw error
        }
    }

    private func waitForFirstAdmittedBatchScope(handle: String) async throws -> AdmittedBatchScope {
        try Task.checkCancellation()
        guard !retiredBatchHandles.contains(handle) else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        if let admittedScope = admittedBatchScopeByHandle[handle] { return admittedScope }
        guard firstScopeWaiterByHandle[handle] == nil else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        firstScopeWaiterByHandle[handle] = continuation
        for observer in firstScopeWaiterObserversByHandle.removeValue(forKey: handle) ?? [] {
            observer.resume()
        }
        defer {
            firstScopeWaiterByHandle.removeValue(forKey: handle)
            continuation.finish()
        }
        var iterator = stream.makeAsyncIterator()
        while await iterator.next() != nil {
            try Task.checkCancellation()
            if let admittedScope = admittedBatchScopeByHandle[handle] { return admittedScope }
        }
        throw CancellationError()
    }

    private func enqueueBatchNotification(
        _ notification: BridgePaneCommentBatchNotification,
        into continuation: AsyncStream<BridgePaneCommentBatchNotification>.Continuation
    ) {
        if case .dropped(let displaced) = continuation.yield(notification) {
            _ = continuation.yield(notification.merging(displaced: displaced))
        }
    }
}
