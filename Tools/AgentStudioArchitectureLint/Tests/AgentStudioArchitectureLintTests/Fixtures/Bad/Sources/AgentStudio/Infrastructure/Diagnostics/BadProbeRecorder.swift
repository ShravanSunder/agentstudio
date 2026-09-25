typealias BadPeriodicSnapshotReporter = @MainActor @Sendable () -> Void

@MainActor
final class BadSnapshotReporter {}

final class BadProbeRecorder {
    func tick(reporters: [BadPeriodicSnapshotReporter]) {
        Task { @MainActor in
            for reporter in reporters {
                reporter()
            }
        }
    }

    func flush() async {
        await MainActor.run {}
    }
}
