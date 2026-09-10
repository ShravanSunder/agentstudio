import Foundation

extension DarwinFSEventStreamClient {
    package func consumeActivityOverflowRecoveries() -> [FSEventActivityOverflowRecovery] {
        ingressBuffer.consumeActivityOverflowRecoveries()
    }

    package func consumeCoarseActivityOverflowWorktreeIds() -> Set<UUID> {
        ingressBuffer.consumeCoarseActivityOverflowWorktreeIds()
    }

    package func acknowledgeActivityProcessingFence(
        _ fenceID: FSEventActivityProcessingFenceID
    ) {
        ingressBuffer.acknowledgeActivityProcessingFence(fenceID)
    }

    package func beginActivityShutdown() {
        lifecycleLock.withLock {
            hasStoppedActivityAdmission = true
        }
        sharedExactItemObserverRegistry.stopActivityAdmission()
    }
}
