extension BridgeWorktreeProductConstructionCoordinator {
    func nextFileSnapshotRead(
        for lease: BridgeSharedFileSnapshotConsumerLease,
        cursor: BridgeSharedFileSnapshotCursor
    ) async throws -> BridgeSharedFileSnapshotRead {
        try ensureOpen()
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

    func readFileSnapshotPreparation(
        for lease: BridgeSharedFileSnapshotConsumerLease
    ) async throws -> BridgeSharedFileSnapshotPreparation {
        try ensureOpen()
        try Task.checkCancellation()
        let cancellationState = BridgeProgressiveFileConstructionState.ReadCancellationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueueFileSnapshotPreparationRead(
                    for: lease,
                    cancellationState: cancellationState,
                    continuation: continuation
                )
            }
        } onCancel: {
            cancellationState.cancel()
            Task {
                await self.cancelFilePreparationReadWaiter(leaseNonce: lease.leaseNonce)
            }
        }
    }
}
