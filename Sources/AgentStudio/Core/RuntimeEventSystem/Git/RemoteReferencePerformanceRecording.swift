import AgentStudioInfrastructure

package struct RemoteReferencePerformanceSnapshot: Equatable, Sendable {
    package struct Settlement: Equatable, Sendable {
        package let physicalActive: UInt64
        package let pendingTotal: UInt64
        package let pendingFuture: UInt64
        package let pendingReady: UInt64
        package let pendingCapacity: UInt64
        package let pendingActiveFollowUp: UInt64
        package let pendingUnclassified: UInt64
        package let deadlineOverdue: UInt64
        package let deadlineNextMilliseconds: Double
    }

    package var demandChanged: UInt64 = 0
    package var demandCleared: UInt64 = 0
    package var admissionAdmitted: UInt64 = 0
    package var admissionCapacityDeferred: UInt64 = 0
    package var stagingStarted: UInt64 = 0
    package var automaticWithoutDemandStarted: UInt64 = 0
    package var explicitAdmitted: UInt64 = 0
    package var explicitSettledCompleted: UInt64 = 0
    package var explicitSettledFailed: UInt64 = 0
    package var explicitSettledObsolete: UInt64 = 0
    package var explicitSettledCancelled: UInt64 = 0
    package var stagingCompleted: UInt64 = 0
    package var promotionStarted: UInt64 = 0
    package var promotionCompleted: UInt64 = 0
    package var executionFailed: UInt64 = 0
    package var executionCancelled: UInt64 = 0
    package var validationCurrent: UInt64 = 0
    package var validationObsolete: UInt64 = 0
    package var publicationLocalAccepted: UInt64 = 0
    package var publicationPromoted: UInt64 = 0
    package var publicationInvalidated: UInt64 = 0
    package var cleanupSucceeded: UInt64 = 0
    package var cleanupFailed: UInt64 = 0
    package var settlement: Settlement?

    package var isEmpty: Bool {
        var countersOnly = self
        countersOnly.settlement = nil
        return countersOnly == Self() && settlement == nil
    }
}

package struct RemoteReferencePerformanceAccumulator: Sendable {
    private var snapshot = RemoteReferencePerformanceSnapshot()

    package init() {}

    package mutating func increment(
        _ keyPath: WritableKeyPath<RemoteReferencePerformanceSnapshot, UInt64>
    ) {
        if snapshot[keyPath: keyPath] < .max {
            snapshot[keyPath: keyPath] += 1
        }
    }

    package mutating func takeSnapshot(
        settlement: RemoteReferencePerformanceSnapshot.Settlement? = nil
    ) -> RemoteReferencePerformanceSnapshot {
        snapshot.settlement = settlement
        defer { snapshot = RemoteReferencePerformanceSnapshot() }
        return snapshot
    }

    package mutating func recordExplicitSettlement(
        _ outcome: RepositoryFactSourceUpdateOutcome,
        count: Int
    ) {
        guard count > 0 else { return }
        let keyPath: WritableKeyPath<RemoteReferencePerformanceSnapshot, UInt64> =
            switch outcome {
            case .completed: \.explicitSettledCompleted
            case .failed: \.explicitSettledFailed
            case .obsolete: \.explicitSettledObsolete
            case .cancelled: \.explicitSettledCancelled
            }
        for _ in 0..<count { increment(keyPath) }
    }
}

package protocol RemoteReferencePerformanceRecording: Sendable {
    func recordRemoteReferencePerformanceSnapshot(_ snapshot: RemoteReferencePerformanceSnapshot)
}

extension AgentStudioPerformanceTraceRecorder: RemoteReferencePerformanceRecording {
    package func recordRemoteReferencePerformanceSnapshot(_ snapshot: RemoteReferencePerformanceSnapshot) {
        guard !snapshot.isEmpty else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.remote_reference.demand.changed.count": Self.remoteReferenceTraceInteger(
                snapshot.demandChanged),
            "agentstudio.performance.remote_reference.demand.cleared.count": Self.remoteReferenceTraceInteger(
                snapshot.demandCleared),
            "agentstudio.performance.remote_reference.admission.admitted.count": Self.remoteReferenceTraceInteger(
                snapshot.admissionAdmitted),
            "agentstudio.performance.remote_reference.admission.capacity_deferred.count":
                Self.remoteReferenceTraceInteger(snapshot.admissionCapacityDeferred),
            "agentstudio.performance.remote_reference.execution.staging_started.count":
                Self.remoteReferenceTraceInteger(snapshot.stagingStarted),
            "agentstudio.performance.remote_reference.execution.automatic_without_demand_started.count":
                Self.remoteReferenceTraceInteger(snapshot.automaticWithoutDemandStarted),
            "agentstudio.performance.remote_reference.explicit.admitted.count":
                Self.remoteReferenceTraceInteger(snapshot.explicitAdmitted),
            "agentstudio.performance.remote_reference.explicit.settled_completed.count":
                Self.remoteReferenceTraceInteger(snapshot.explicitSettledCompleted),
            "agentstudio.performance.remote_reference.explicit.settled_failed.count":
                Self.remoteReferenceTraceInteger(snapshot.explicitSettledFailed),
            "agentstudio.performance.remote_reference.explicit.settled_obsolete.count":
                Self.remoteReferenceTraceInteger(snapshot.explicitSettledObsolete),
            "agentstudio.performance.remote_reference.explicit.settled_cancelled.count":
                Self.remoteReferenceTraceInteger(snapshot.explicitSettledCancelled),
            "agentstudio.performance.remote_reference.execution.staging_completed.count":
                Self.remoteReferenceTraceInteger(snapshot.stagingCompleted),
            "agentstudio.performance.remote_reference.execution.promotion_started.count":
                Self.remoteReferenceTraceInteger(snapshot.promotionStarted),
            "agentstudio.performance.remote_reference.execution.promotion_completed.count":
                Self.remoteReferenceTraceInteger(snapshot.promotionCompleted),
            "agentstudio.performance.remote_reference.execution.failed.count": Self.remoteReferenceTraceInteger(
                snapshot.executionFailed),
            "agentstudio.performance.remote_reference.execution.cancelled.count": Self.remoteReferenceTraceInteger(
                snapshot.executionCancelled),
            "agentstudio.performance.remote_reference.validation.current.count": Self.remoteReferenceTraceInteger(
                snapshot.validationCurrent),
            "agentstudio.performance.remote_reference.validation.obsolete.count": Self.remoteReferenceTraceInteger(
                snapshot.validationObsolete),
            "agentstudio.performance.remote_reference.publication.local_accepted.count":
                Self.remoteReferenceTraceInteger(snapshot.publicationLocalAccepted),
            "agentstudio.performance.remote_reference.publication.promoted.count": Self.remoteReferenceTraceInteger(
                snapshot.publicationPromoted),
            "agentstudio.performance.remote_reference.publication.invalidated.count":
                Self.remoteReferenceTraceInteger(snapshot.publicationInvalidated),
            "agentstudio.performance.remote_reference.cleanup.succeeded.count": Self.remoteReferenceTraceInteger(
                snapshot.cleanupSucceeded),
            "agentstudio.performance.remote_reference.cleanup.failed.count": Self.remoteReferenceTraceInteger(
                snapshot.cleanupFailed),
        ]
        if let settlement = snapshot.settlement {
            attributes.merge(
                Self.remoteReferenceSettlementAttributes(settlement),
                uniquingKeysWith: { _, current in current }
            )
        }
        record(
            .remoteReferenceRefresh,
            attributes: attributes
        )
    }

    private static func remoteReferenceSettlementAttributes(
        _ settlement: RemoteReferencePerformanceSnapshot.Settlement
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.remote_reference.settlement.physical.active.current":
                remoteReferenceTraceInteger(settlement.physicalActive),
            "agentstudio.performance.remote_reference.settlement.pending.total.current":
                remoteReferenceTraceInteger(settlement.pendingTotal),
            "agentstudio.performance.remote_reference.settlement.pending.future.current":
                remoteReferenceTraceInteger(settlement.pendingFuture),
            "agentstudio.performance.remote_reference.settlement.pending.ready.current":
                remoteReferenceTraceInteger(settlement.pendingReady),
            "agentstudio.performance.remote_reference.settlement.pending.capacity.current":
                remoteReferenceTraceInteger(settlement.pendingCapacity),
            "agentstudio.performance.remote_reference.settlement.pending.active_follow_up.current":
                remoteReferenceTraceInteger(settlement.pendingActiveFollowUp),
            "agentstudio.performance.remote_reference.settlement.pending.unclassified.current":
                remoteReferenceTraceInteger(settlement.pendingUnclassified),
            "agentstudio.performance.remote_reference.settlement.deadline.overdue.current":
                remoteReferenceTraceInteger(settlement.deadlineOverdue),
            "agentstudio.performance.remote_reference.settlement.deadline.next_ms":
                .double(settlement.deadlineNextMilliseconds),
        ]
    }

    private static func remoteReferenceTraceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(value > UInt64(Int.max) ? Int.max : Int(value))
    }
}
