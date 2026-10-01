import AgentStudioCore
import Foundation
import GRDB

/// S2 RED compile-level stand-in; the migration and transaction admission are
/// intentionally absent until the Lead confirms the red result.
package actor SQLitePaneForegroundObservationRepository: PaneForegroundObservationRepository {
    package init(
        databaseWriter: any DatabaseWriter, observerLaunchId: UUID,
        paneSessions: @escaping @Sendable () async throws -> [UUID: ZmxSessionID] = { [:] }
    ) {}

    package func eligiblePanes() async throws -> [ForegroundPaneBinding] { throw ForegroundImplementationMissing.s2 }
    package func admit(_ observation: PaneForegroundObservation) async throws -> ObservationAdmission {
        throw ForegroundImplementationMissing.s2
    }
    package func load(paneId: UUID) async throws -> PaneForegroundObservation? {
        throw ForegroundImplementationMissing.s2
    }
    package func retire(paneId: UUID) async throws { throw ForegroundImplementationMissing.s2 }
}
