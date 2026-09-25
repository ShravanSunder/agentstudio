typealias GoodPeriodicSnapshotReporter = @Sendable () -> Void

@MainActor
final class GoodPilotFixtureView {}

final class GoodProbeRecorder {
    func tick(reporters: [GoodPeriodicSnapshotReporter]) {
        for reporter in reporters {
            reporter()
        }
    }
}
