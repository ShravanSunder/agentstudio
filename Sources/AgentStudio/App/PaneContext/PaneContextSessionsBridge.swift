import AgentStudioCore
import AgentStudioSessions
import Foundation
import GRDB
import Synchronization

/// App owns the Core/Sessions join. The owners hold this adapter through their
/// callbacks; weak endpoints keep those callbacks from forming a retain cycle.
final class PaneContextSessionsBridge: SessionOpenAskReading, Sendable {
    private struct Endpoints {
        weak var service: PaneContextService?
        weak var ingestion: SessionsIngestion?
    }
    private let endpoints = Mutex(Endpoints())

    func connect(service: PaneContextService, ingestion: SessionsIngestion) {
        endpoints.withLock {
            $0.service = service
            $0.ingestion = ingestion
        }
    }

    // RED shells: the real owners and their transaction boundaries are already
    // connected; the integration tests expose each missing translation.
    func openAskSummaries() async -> [SessionsOpenAskUpdate] { [] }

    func receiveOpenAskSummary(_ update: PaneContextOpenAskUpdate) async {}

    func receiveAgentLine(work: AgentStudioCore.AgentLineWork?, bindingGenerationId: UUID) async {}

    func sessionEnded(bindingGenerationId: UUID) async {}

    func sessionSummary(paneId: PaneId) async throws -> SessionSummary? { nil }

    /// This existing repository read is the transaction seam, not a stand-in.
    static func currentBindingGeneration(paneId: PaneId, in database: Database) throws -> UUID? {
        try SessionsRepositoryStorage.currentBindingGeneration(paneId: paneId.uuid, in: database)
    }
}
