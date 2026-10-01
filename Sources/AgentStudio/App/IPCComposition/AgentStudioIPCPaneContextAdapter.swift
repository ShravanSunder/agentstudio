import AgentStudioAppIPC
import AgentStudioCore
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation

/// App owns wire-to-domain composition; no target lookup or service work runs
/// on MainActor. RED scaffold deliberately refuses until the real-path proofs
/// establish each mapping and connection settlement behavior.
struct AgentStudioIPCPaneContextAdapter: AppIPCPaneContextPort {
    private let service: PaneContextService
    private let ingestion: SessionsIngestion
    private let maximumEncodedReplyBytes: Int

    /// Test seam; lowers only. Production composition passes no cap.
    init(
        service: PaneContextService, ingestion: SessionsIngestion,
        maximumEncodedReplyBytes: Int = min(
            IPCFramePolicy.maximumResponseFrameBytes, AppPolicies.IPC.maximumQueuedOutputBytes - 1)
    ) {
        self.service = service
        self.ingestion = ingestion
        self.maximumEncodedReplyBytes = min(
            maximumEncodedReplyBytes,
            min(IPCFramePolicy.maximumResponseFrameBytes, AppPolicies.IPC.maximumQueuedOutputBytes - 1))
    }
    func sendMessage(paneId: UUID, params: IPCPaneMessageSendParams) async throws -> IPCPaneMessageSendResult {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func askMessage(
        paneId: UUID, params: IPCPaneMessageAskParams,
        connectionEndCause: @escaping @Sendable () -> AppIPCConnectionEndCause
    ) async throws -> IPCPaneAskOutcome {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func withdrawMessage(paneId: UUID, params: IPCPaneMessageWithdrawParams) async throws
        -> IPCPaneMessageWithdrawResult
    {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func readChanges(paneId: UUID, params: IPCPaneMessageChangesParams) async throws -> IPCPaneMessageChangesResult {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func setLine(paneId: UUID, params: IPCPaneLineSetParams) async throws -> IPCPaneOrderedWriteResult {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func setTitle(paneId: UUID, params: IPCPaneTitleSetParams) async throws -> IPCPaneOrderedWriteResult {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func claimEpoch(paneId: UUID, params: IPCPaneWriterClaimEpochParams) async throws -> IPCPaneEpochClaimResult {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
    func readContext(paneId: UUID, params: IPCPaneContextGetParams, replyEnvelopeOverheadBytes: Int) async throws
        -> IPCPaneContextGetResult
    {
        throw AppIPCPaneContextError(reason: .unavailable)
    }
}
