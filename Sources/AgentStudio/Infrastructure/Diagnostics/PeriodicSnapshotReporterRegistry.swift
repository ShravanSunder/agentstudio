import Foundation
import Synchronization

final class PeriodicSnapshotReporterRegistry: Sendable {
    typealias Reporter = AgentStudioPerformanceTraceRecorder.PeriodicSnapshotReporter

    private let reporters = Mutex<[UUID: Reporter]>([:])

    func register(_ reporter: @escaping Reporter) -> UUID {
        let token = UUIDv7.generate()
        reporters.withLock { $0[token] = reporter }
        return token
    }

    func unregister(_ token: UUID) {
        reporters.withLock { $0.removeValue(forKey: token) }
    }

    func snapshot() -> [Reporter] {
        reporters.withLock { Array($0.values) }
    }
}
