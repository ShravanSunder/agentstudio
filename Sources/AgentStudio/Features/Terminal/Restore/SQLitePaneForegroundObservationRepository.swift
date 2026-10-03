import AgentStudioCore
import Foundation
import GRDB
import Synchronization

/// Sole writer of foreground evidence. Retirement is a launch-lifetime fence:
/// pane UUIDs are never reused and later launches enumerate canonical live panes.
package actor SQLitePaneForegroundObservationRepository: PaneForegroundObservationRepository {
    private let access: any ForegroundObservationSQLiteAccess
    private let observerLaunchId: UUID
    private let paneSessions: @Sendable () async throws -> [UUID: ZmxSessionID]
    private let retirementFence = ForegroundRetirementFence()

    package init(
        access: any ForegroundObservationSQLiteAccess, observerLaunchId: UUID,
        paneSessions: @escaping @Sendable () async throws -> [UUID: ZmxSessionID] = { [:] }
    ) {
        self.access = access
        self.observerLaunchId = observerLaunchId
        self.paneSessions = paneSessions
    }

    package func eligiblePanes() async throws -> [ForegroundPaneBinding] {
        let sessions = try await paneSessions()
        let retired = retirementFence.snapshot()
        return try await access.read { database in
            try sessions.compactMap { paneId, sessionId in
                guard !retired.contains(paneId) else { return nil }
                let row = try Self.latestBinding(paneId: paneId, in: database)
                // A sweep end is bookkeeping only; a provider end stops relaunch demand.
                if let row, (row["provider_ended_at"] as String?) != nil { return nil }
                return ForegroundPaneBinding(
                    paneId: paneId, sessionId: sessionId,
                    bindingGenerationId: row.flatMap { UUID(uuidString: $0["binding_generation_id"]) })
            }
        }
    }

    package func admit(_ observation: PaneForegroundObservation) async throws -> ObservationAdmission {
        guard observation.observerLaunchId == observerLaunchId else { return .olderLook }
        guard let identity = try? ZmxSessionIdentity.decode(observation.sessionIdentity),
            ForegroundObservationRow.canStore(identity: identity, sequence: observation.sequence)
        else { return .invalidIdentity }
        let retirementFence = retirementFence
        return try await access.write { database in
            try Task.checkCancellation()
            return try retirementFence.withAdmission { retired in
                guard !retired.contains(observation.paneId) else { return .retiredPane }
                let binding = try Self.latestBinding(paneId: observation.paneId, in: database)
                let generation = binding.flatMap { UUID(uuidString: $0["binding_generation_id"]) }
                guard generation == observation.bindingGenerationId else { return .bindingChanged }
                if let previous = try Row.fetchOne(
                    database,
                    sql:
                        "SELECT observer_launch_id, sequence FROM terminal_pane_foreground_observation WHERE pane_id = ?",
                    arguments: [observation.paneId.uuidString])
                {
                    let previousLaunch: String = previous["observer_launch_id"]
                    let previousSequence: Int64 = previous["sequence"]
                    if previousLaunch == observation.observerLaunchId.uuidString
                        && previousSequence >= Int64(observation.sequence)
                    {
                        return .olderLook
                    }
                }
                try ForegroundObservationRow.write(observation, identity: identity, in: database)
                return .admitted
            }
        }
    }

    package func load(paneId: UUID) async throws -> PaneForegroundObservation? {
        guard !retirementFence.contains(paneId) else { return nil }
        let observation = try await access.read { try ForegroundObservationRow.load(paneId: paneId, in: $0) }
        return retirementFence.contains(paneId) ? nil : observation
    }

    package func retire(paneId: UUID) async throws {
        retirementFence.retire(paneId)
        try await access.write { database in
            try database.execute(
                sql: "DELETE FROM terminal_pane_foreground_observation WHERE pane_id = ?",
                arguments: [paneId.uuidString])
        }
    }

    private static func latestBinding(paneId: UUID, in database: Database) throws -> Row? {
        // Match the Sessions read's first establishing commit, including sweep-ended bindings.
        try Row.fetchOne(
            database,
            sql: """
                SELECT binding.binding_generation_id, binding.provider_ended_at
                FROM sessions_pane_binding AS binding
                JOIN sessions_operation AS establishment
                  ON establishment.binding_generation_id = binding.binding_generation_id
                 AND establishment.outcome_kind IN ('bindingEstablished', 'bindingReplaced')
                WHERE binding.pane_id = ?
                GROUP BY binding.binding_generation_id
                ORDER BY MIN(establishment.commit_revision) DESC LIMIT 1
                """, arguments: [paneId.uuidString])
    }
}

/// Shared reference lets a queued database transaction inspect the live fence,
/// rather than a copied actor snapshot taken before retirement.
private final class ForegroundRetirementFence: Sendable {
    private let retiredPanes = Mutex<Set<UUID>>([])
    func snapshot() -> Set<UUID> { retiredPanes.withLock { $0 } }
    func contains(_ paneId: UUID) -> Bool { retiredPanes.withLock { $0.contains(paneId) } }
    func retire(_ paneId: UUID) { retiredPanes.withLock { _ = $0.insert(paneId) } }
    func withAdmission(_ operation: (Set<UUID>) throws -> ObservationAdmission) rethrows -> ObservationAdmission {
        try retiredPanes.withLock { try operation($0) }
    }
}
