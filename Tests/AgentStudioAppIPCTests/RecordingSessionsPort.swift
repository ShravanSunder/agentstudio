import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

/// Records the canonical pane each session registration resolved, so the
/// registration tests can prove targeting without a Sessions database.
actor RecordingSessionsPort: AppIPCSessionsPort {
    private(set) var reportPaneIds: [UUID] = []
    private(set) var messagePaneIds: [UUID] = []
    private(set) var eventPaneIds: [UUID] = []
    private(set) var queryPaneIds: [UUID] = []
    private(set) var reportedExplanations: [String?] = []
    private let occurrenceId = UUIDv7.generate()

    func recordDeliberateReport(
        paneId: UUID,
        params: IPCSessionReportParams
    ) async throws -> IPCSessionReportResult {
        reportPaneIds.append(paneId)
        reportedExplanations.append(params.explanation)
        return IPCSessionReportResult(
            paneId: paneId,
            state: params.kind == .done ? .done : .needsYou,
            origin: .agentReported,
            requestId: params.kind == .needsYou ? occurrenceId.uuidString : nil,
            correlationId: params.correlationId
        )
    }

    func recordAgentMessage(
        paneId: UUID,
        params: IPCSessionMessageParams
    ) async throws -> IPCSessionMessageResult {
        messagePaneIds.append(paneId)
        return IPCSessionMessageResult(
            paneId: paneId,
            occurrenceId: occurrenceId,
            attributed: false,
            correlationId: params.correlationId
        )
    }

    func recordProviderEvent(
        paneId: UUID,
        params: IPCSessionEventParams
    ) async throws -> IPCSessionEventResult {
        eventPaneIds.append(paneId)
        return IPCSessionEventResult(
            paneId: paneId,
            disposition: .unknownCapability,
            correlationId: params.correlationId
        )
    }

    func readSessionState(
        paneId: UUID,
        params: IPCSessionQueryParams
    ) async throws -> IPCSessionQueryResult {
        queryPaneIds.append(paneId)
        return IPCSessionQueryResult(
            paneId: paneId,
            state: .unknown,
            origin: .unknown,
            needsYou: nil,
            messages: [],
            sourceHealth: .unbound
        )
    }
}
