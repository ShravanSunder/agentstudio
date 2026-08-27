import AgentStudioInfrastructure
import Foundation

package enum DarwinFSEventIngressSource: Sendable {
    case local
    case sharedExact
    case sharedUncertainty
}

package enum DarwinFSEventIngressDisposition: Sendable {
    case accepted
    case dropped
    case terminated
}

package struct DarwinFSEventIngressDispositionSnapshot: Equatable, Sendable {
    package let acceptedBatchCount: Int
    package let acceptedPathCount: Int
    package let droppedBatchCount: Int
    package let droppedPathCount: Int
    package let terminatedBatchCount: Int
    package let terminatedPathCount: Int

    package static let zero = Self(
        acceptedBatchCount: 0,
        acceptedPathCount: 0,
        droppedBatchCount: 0,
        droppedPathCount: 0,
        terminatedBatchCount: 0,
        terminatedPathCount: 0
    )
}

package struct DarwinFSEventIngressPerformanceSnapshot: Equatable, Sendable {
    package let localRawCallbackBatchCount: Int
    package let localRawCallbackEventCount: Int
    package let sharedRawCallbackBatchCount: Int
    package let sharedRawCallbackEventCount: Int
    package let sharedExactSubscriberCount: Int
    package let sharedUncertaintySubscriberCount: Int
    package let sharedFullRefreshEmissionCount: Int
    package let localIngress: DarwinFSEventIngressDispositionSnapshot
    package let sharedExactIngress: DarwinFSEventIngressDispositionSnapshot
    package let sharedUncertaintyIngress: DarwinFSEventIngressDispositionSnapshot
    package let overflowDrainCount: Int
    package let overflowRecoveryCount: Int
    package let overflowRetainedPathCount: Int
    package let overflowCoarseRecoveryCount: Int

    package static let zero = Self(
        localRawCallbackBatchCount: 0,
        localRawCallbackEventCount: 0,
        sharedRawCallbackBatchCount: 0,
        sharedRawCallbackEventCount: 0,
        sharedExactSubscriberCount: 0,
        sharedUncertaintySubscriberCount: 0,
        sharedFullRefreshEmissionCount: 0,
        localIngress: .zero,
        sharedExactIngress: .zero,
        sharedUncertaintyIngress: .zero,
        overflowDrainCount: 0,
        overflowRecoveryCount: 0,
        overflowRetainedPathCount: 0,
        overflowCoarseRecoveryCount: 0
    )

    package var traceAttributes: [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.filesystem.ingress.local_raw_callback.batch.count": .int(
                localRawCallbackBatchCount
            ),
            "agentstudio.performance.filesystem.ingress.local_raw_callback.event.count": .int(
                localRawCallbackEventCount
            ),
            "agentstudio.performance.filesystem.ingress.shared_raw_callback.batch.count": .int(
                sharedRawCallbackBatchCount
            ),
            "agentstudio.performance.filesystem.ingress.shared_raw_callback.event.count": .int(
                sharedRawCallbackEventCount
            ),
            "agentstudio.performance.filesystem.ingress.shared_exact_subscriber.count": .int(
                sharedExactSubscriberCount
            ),
            "agentstudio.performance.filesystem.ingress.shared_uncertainty_subscriber.count": .int(
                sharedUncertaintySubscriberCount
            ),
            "agentstudio.performance.filesystem.ingress.shared_full_refresh_emission.count": .int(
                sharedFullRefreshEmissionCount
            ),
            "agentstudio.performance.filesystem.ingress.overflow.drain.count": .int(overflowDrainCount),
            "agentstudio.performance.filesystem.ingress.overflow.recovery.count": .int(
                overflowRecoveryCount
            ),
            "agentstudio.performance.filesystem.ingress.overflow.retained_path.count": .int(
                overflowRetainedPathCount
            ),
            "agentstudio.performance.filesystem.ingress.overflow.coarse_recovery.count": .int(
                overflowCoarseRecoveryCount
            ),
        ]
        Self.appendIngressAttributes(localIngress, source: "local", to: &attributes)
        Self.appendIngressAttributes(sharedExactIngress, source: "shared_exact", to: &attributes)
        Self.appendIngressAttributes(
            sharedUncertaintyIngress,
            source: "shared_uncertainty",
            to: &attributes
        )
        return attributes
    }

    private static func appendIngressAttributes(
        _ snapshot: DarwinFSEventIngressDispositionSnapshot,
        source: String,
        to attributes: inout [String: AgentStudioTraceValue]
    ) {
        let prefix = "agentstudio.performance.filesystem.ingress.\(source)"
        attributes["\(prefix).accepted.batch.count"] = .int(snapshot.acceptedBatchCount)
        attributes["\(prefix).accepted.path.count"] = .int(snapshot.acceptedPathCount)
        attributes["\(prefix).dropped.batch.count"] = .int(snapshot.droppedBatchCount)
        attributes["\(prefix).dropped.path.count"] = .int(snapshot.droppedPathCount)
        attributes["\(prefix).terminated.batch.count"] = .int(snapshot.terminatedBatchCount)
        attributes["\(prefix).terminated.path.count"] = .int(snapshot.terminatedPathCount)
    }
}

package final class DarwinFSEventIngressPerformanceAccumulator: @unchecked Sendable {
    private struct MutableDispositionCounters {
        var acceptedBatchCount = 0
        var acceptedPathCount = 0
        var droppedBatchCount = 0
        var droppedPathCount = 0
        var terminatedBatchCount = 0
        var terminatedPathCount = 0

        mutating func record(_ disposition: DarwinFSEventIngressDisposition, pathCount: Int) {
            switch disposition {
            case .accepted:
                acceptedBatchCount += 1
                acceptedPathCount += pathCount
            case .dropped:
                droppedBatchCount += 1
                droppedPathCount += pathCount
            case .terminated:
                terminatedBatchCount += 1
                terminatedPathCount += pathCount
            }
        }

        var snapshot: DarwinFSEventIngressDispositionSnapshot {
            DarwinFSEventIngressDispositionSnapshot(
                acceptedBatchCount: acceptedBatchCount,
                acceptedPathCount: acceptedPathCount,
                droppedBatchCount: droppedBatchCount,
                droppedPathCount: droppedPathCount,
                terminatedBatchCount: terminatedBatchCount,
                terminatedPathCount: terminatedPathCount
            )
        }
    }

    private struct MutableCounters {
        var localRawCallbackBatchCount = 0
        var localRawCallbackEventCount = 0
        var sharedRawCallbackBatchCount = 0
        var sharedRawCallbackEventCount = 0
        var sharedExactSubscriberCount = 0
        var sharedUncertaintySubscriberCount = 0
        var sharedFullRefreshEmissionCount = 0
        var localIngress = MutableDispositionCounters()
        var sharedExactIngress = MutableDispositionCounters()
        var sharedUncertaintyIngress = MutableDispositionCounters()
        var overflowDrainCount = 0
        var overflowRecoveryCount = 0
        var overflowRetainedPathCount = 0
        var overflowCoarseRecoveryCount = 0

        var snapshot: DarwinFSEventIngressPerformanceSnapshot {
            DarwinFSEventIngressPerformanceSnapshot(
                localRawCallbackBatchCount: localRawCallbackBatchCount,
                localRawCallbackEventCount: localRawCallbackEventCount,
                sharedRawCallbackBatchCount: sharedRawCallbackBatchCount,
                sharedRawCallbackEventCount: sharedRawCallbackEventCount,
                sharedExactSubscriberCount: sharedExactSubscriberCount,
                sharedUncertaintySubscriberCount: sharedUncertaintySubscriberCount,
                sharedFullRefreshEmissionCount: sharedFullRefreshEmissionCount,
                localIngress: localIngress.snapshot,
                sharedExactIngress: sharedExactIngress.snapshot,
                sharedUncertaintyIngress: sharedUncertaintyIngress.snapshot,
                overflowDrainCount: overflowDrainCount,
                overflowRecoveryCount: overflowRecoveryCount,
                overflowRetainedPathCount: overflowRetainedPathCount,
                overflowCoarseRecoveryCount: overflowCoarseRecoveryCount
            )
        }
    }

    private let lock = NSLock()
    private var counters = MutableCounters()

    package func recordLocalRawCallback(eventCount: Int) {
        lock.withLock {
            counters.localRawCallbackBatchCount += 1
            counters.localRawCallbackEventCount += eventCount
        }
    }

    package func recordSharedRawCallback(eventCount: Int) {
        lock.withLock {
            counters.sharedRawCallbackBatchCount += 1
            counters.sharedRawCallbackEventCount += eventCount
        }
    }

    package func recordSharedFanout(
        exactSubscriberCount: Int,
        uncertaintySubscriberCount: Int,
        fullRefreshEmissionCount: Int
    ) {
        lock.withLock {
            counters.sharedExactSubscriberCount += exactSubscriberCount
            counters.sharedUncertaintySubscriberCount += uncertaintySubscriberCount
            counters.sharedFullRefreshEmissionCount += fullRefreshEmissionCount
        }
    }

    package func recordIngress(
        source: DarwinFSEventIngressSource,
        disposition: DarwinFSEventIngressDisposition,
        pathCount: Int
    ) {
        lock.withLock {
            switch source {
            case .local: counters.localIngress.record(disposition, pathCount: pathCount)
            case .sharedExact: counters.sharedExactIngress.record(disposition, pathCount: pathCount)
            case .sharedUncertainty:
                counters.sharedUncertaintyIngress.record(disposition, pathCount: pathCount)
            }
        }
    }

    package func recordOverflowDrain(
        recoveryCount: Int,
        retainedPathCount: Int,
        coarseRecoveryCount: Int
    ) {
        lock.withLock {
            counters.overflowDrainCount += 1
            counters.overflowRecoveryCount += recoveryCount
            counters.overflowRetainedPathCount += retainedPathCount
            counters.overflowCoarseRecoveryCount += coarseRecoveryCount
        }
    }

    package func snapshotAndReset() -> DarwinFSEventIngressPerformanceSnapshot {
        lock.withLock {
            let snapshot = counters.snapshot
            counters = MutableCounters()
            return snapshot
        }
    }
}
