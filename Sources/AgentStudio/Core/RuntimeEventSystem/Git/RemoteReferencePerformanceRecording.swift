import AgentStudioInfrastructure

package struct RemoteReferencePerformanceSnapshot: Equatable, Sendable {
    package var demandChanged: UInt64 = 0
    package var demandCleared: UInt64 = 0
    package var admissionAdmitted: UInt64 = 0
    package var admissionCapacityDeferred: UInt64 = 0
    package var stagingStarted: UInt64 = 0
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

    package var isEmpty: Bool { self == Self() }
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

    package mutating func takeSnapshot() -> RemoteReferencePerformanceSnapshot {
        defer { snapshot = RemoteReferencePerformanceSnapshot() }
        return snapshot
    }
}

package protocol RemoteReferencePerformanceRecording: Sendable {
    func recordRemoteReferencePerformanceSnapshot(_ snapshot: RemoteReferencePerformanceSnapshot)
}

extension AgentStudioPerformanceTraceRecorder: RemoteReferencePerformanceRecording {
    package func recordRemoteReferencePerformanceSnapshot(_ snapshot: RemoteReferencePerformanceSnapshot) {
        guard !snapshot.isEmpty else { return }
        record(
            .remoteReferenceRefresh,
            attributes: [
                "agentstudio.performance.remote_reference.demand.changed.count": Self.remoteReferenceTraceInteger(
                    snapshot.demandChanged),
                "agentstudio.performance.remote_reference.demand.cleared.count": Self.remoteReferenceTraceInteger(
                    snapshot.demandCleared),
                "agentstudio.performance.remote_reference.admission.admitted.count": Self.remoteReferenceTraceInteger(
                    snapshot.admissionAdmitted),
                "agentstudio.performance.remote_reference.admission.capacity_deferred.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.admissionCapacityDeferred),
                "agentstudio.performance.remote_reference.execution.staging_started.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.stagingStarted),
                "agentstudio.performance.remote_reference.execution.staging_completed.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.stagingCompleted),
                "agentstudio.performance.remote_reference.execution.promotion_started.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.promotionStarted),
                "agentstudio.performance.remote_reference.execution.promotion_completed.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.promotionCompleted),
                "agentstudio.performance.remote_reference.execution.failed.count": Self.remoteReferenceTraceInteger(
                    snapshot.executionFailed),
                "agentstudio.performance.remote_reference.execution.cancelled.count": Self.remoteReferenceTraceInteger(
                    snapshot.executionCancelled),
                "agentstudio.performance.remote_reference.validation.current.count": Self.remoteReferenceTraceInteger(
                    snapshot.validationCurrent),
                "agentstudio.performance.remote_reference.validation.obsolete.count": Self.remoteReferenceTraceInteger(
                    snapshot.validationObsolete),
                "agentstudio.performance.remote_reference.publication.local_accepted.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.publicationLocalAccepted),
                "agentstudio.performance.remote_reference.publication.promoted.count": Self.remoteReferenceTraceInteger(
                    snapshot.publicationPromoted),
                "agentstudio.performance.remote_reference.publication.invalidated.count":
                    Self.remoteReferenceTraceInteger(
                        snapshot.publicationInvalidated),
                "agentstudio.performance.remote_reference.cleanup.succeeded.count": Self.remoteReferenceTraceInteger(
                    snapshot.cleanupSucceeded),
                "agentstudio.performance.remote_reference.cleanup.failed.count": Self.remoteReferenceTraceInteger(
                    snapshot.cleanupFailed),
            ]
        )
    }

    private static func remoteReferenceTraceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(value > UInt64(Int.max) ? Int.max : Int(value))
    }
}
