import Foundation
import Observation

@MainActor
@Observable
final class SessionRuntimeAtom {
    private(set) var statuses: [UUID: SessionRuntimeStatus] = [:]

    func status(for paneId: UUID) -> SessionRuntimeStatus {
        statuses[paneId] ?? .initializing
    }

    func panes(withStatus status: SessionRuntimeStatus) -> [UUID] {
        statuses.filter { $0.value == status }.map(\.key)
    }

    var runningCount: Int {
        statuses.values.filter { $0 == .running }.count
    }

    func initializeSession(_ paneId: UUID) {
        statuses[paneId] = .initializing
    }

    func markRunning(_ paneId: UUID) {
        statuses[paneId] = .running
    }

    func markExited(_ paneId: UUID) {
        statuses[paneId] = .exited
    }

    func markUnhealthy(_ paneId: UUID) {
        statuses[paneId] = .unhealthy
    }

    func removeSession(_ paneId: UUID) {
        statuses.removeValue(forKey: paneId)
    }

    func sync(withPaneIds paneIds: Set<UUID>) {
        let trackedIds = Set(statuses.keys)

        for id in trackedIds.subtracting(paneIds) {
            statuses.removeValue(forKey: id)
        }

        for id in paneIds.subtracting(trackedIds) {
            statuses[id] = .initializing
        }
    }
}
