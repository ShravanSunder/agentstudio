import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation

/// Whether one projected provider event earned a Sessions mutation, and the
/// reported reason when it did not.
private enum SessionsProviderEventAdmissionOutcome: Sendable {
    case admitted(SessionsMutation)
    case rejected(IPCSessionEventDisposition)
}

/// Bridges the IPC session methods to Sessions ingestion. It owns only the
/// wire-to-domain mapping: ordering, replay and reduction stay in Sessions, and
/// nothing here touches MainActor.
struct AgentStudioIPCSessionsAdapter: AppIPCSessionsPort {
    private let ingestion: SessionsIngestion
    private let providerRegistry: SessionsProviderAdapterRegistry
    private let admissionFreshness: SessionsEvidenceFreshness
    private let now: @Sendable () -> Date

    /// The live IPC server admits messages as `.live`. The offline spool drainer
    /// composes a second adapter over the same ingestion with `.late`, so one
    /// mapping serves both routes and freshness stays a composition input.
    init(
        ingestion: SessionsIngestion,
        providerRegistry: SessionsProviderAdapterRegistry,
        admissionFreshness: SessionsEvidenceFreshness = .live,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ingestion = ingestion
        self.providerRegistry = providerRegistry
        self.admissionFreshness = admissionFreshness
        self.now = now
    }

    func recordDeliberateReport(
        paneId: UUID,
        params: IPCSessionReportParams
    ) async throws -> IPCSessionReportResult {
        let reportedAt = now()
        let mutation: SessionsMutation =
            switch params.kind {
            case .needsYou:
                .deliberateNeedsYou(
                    SessionsDeliberateNeedsYouMutation(
                        paneId: paneId,
                        explanation: params.explanation ?? "",
                        reportedAt: reportedAt
                    )
                )
            case .clearNeedsYou:
                .clearDeliberateNeedsYou(
                    SessionsClearDeliberateNeedsYouMutation(paneId: paneId, clearedAt: reportedAt)
                )
            case .done:
                .deliberateDone(
                    SessionsDeliberateDoneMutation(paneId: paneId, reportedAt: reportedAt)
                )
            }
        do {
            _ = try await ingestion.submit(correlationId: params.correlationId, mutation: mutation)
        } catch {
            throw Self.portError(from: error)
        }
        let snapshot = try await paneSnapshot(paneId: paneId)
        return IPCSessionReportResult(
            paneId: paneId,
            state: Self.agentState(snapshot.state),
            origin: Self.evidenceOrigin(snapshot.stateOrigin),
            requestId: snapshot.currentAttention.first?.requestId,
            correlationId: params.correlationId
        )
    }

    func recordAgentMessage(
        paneId: UUID,
        params: IPCSessionMessageParams
    ) async throws -> IPCSessionMessageResult {
        // Attribution is decided before submission so one correlation always
        // carries one semantic fingerprint. A binding that changes between
        // retries surfaces as a correlation conflict, which R-09 requires,
        // rather than quietly rewriting the retained outcome.
        let snapshot = try await paneSnapshot(paneId: paneId)
        let hasLiveBinding = snapshot.currentBinding?.status == .active
        let context: SessionsReportContext =
            hasLiveBinding ? .currentPaneBinding(paneId: paneId) : .unattributed(paneId: paneId)
        let outcome: SessionsMutationOutcome
        do {
            outcome = try await ingestion.submit(
                correlationId: params.correlationId,
                mutation: .message(
                    SessionsMessageMutation(
                        context: context,
                        text: params.text,
                        freshness: admissionFreshness,
                        receivedAt: now()
                    )
                )
            )
        } catch {
            throw Self.portError(from: error)
        }
        guard case .messageSaved(let occurrenceId, let attribution) = outcome else {
            throw AppIPCSessionsError(reason: .validationRejected)
        }
        return IPCSessionMessageResult(
            paneId: paneId,
            occurrenceId: occurrenceId,
            attributed: attribution == .attributed,
            correlationId: params.correlationId
        )
    }

    func recordProviderEvent(
        paneId: UUID,
        params: IPCSessionEventParams
    ) async throws -> IPCSessionEventResult {
        let admission = try providerAdmission(
            paneId: paneId,
            params: params,
            snapshot: try await paneSnapshot(paneId: paneId)
        )
        guard case .admitted(let mutation) = admission else {
            guard case .rejected(let disposition) = admission else {
                throw AppIPCSessionsError(reason: .validationRejected)
            }
            return IPCSessionEventResult(
                paneId: paneId,
                disposition: disposition,
                correlationId: params.correlationId
            )
        }
        do {
            _ = try await ingestion.submit(correlationId: params.correlationId, mutation: mutation)
        } catch {
            throw Self.portError(from: error)
        }
        return IPCSessionEventResult(
            paneId: paneId,
            disposition: .admitted,
            correlationId: params.correlationId
        )
    }

    func readSessionState(
        paneId: UUID,
        params: IPCSessionQueryParams
    ) async throws -> IPCSessionQueryResult {
        let snapshot = try await paneSnapshot(paneId: paneId)
        return IPCSessionQueryResult(
            paneId: paneId,
            state: Self.agentState(snapshot.state),
            origin: Self.evidenceOrigin(snapshot.stateOrigin),
            needsYou: snapshot.currentAttention.first.map {
                IPCSessionAttentionProjection(requestId: $0.requestId, explanation: $0.explanation)
            },
            messages: snapshot.messages.map {
                IPCSessionMessageProjection(
                    occurrenceId: $0.occurrenceId,
                    text: $0.text,
                    seen: $0.disposition == .seen,
                    receivedAt: $0.reportedAt
                )
            },
            sourceHealth: Self.sourceHealth(snapshot.currentBinding)
        )
    }
}

extension AgentStudioIPCSessionsAdapter {
    fileprivate func paneSnapshot(paneId: UUID) async throws -> SessionsSnapshot {
        do {
            return try await ingestion.snapshot(
                .pane(
                    paneId,
                    page: SessionsSnapshotPage(
                        limit: IPCSessionSchemaLimits.maximumQueryMessageCount,
                        after: nil
                    )
                )
            )
        } catch {
            throw Self.portError(from: error)
        }
    }

    /// A session start binds the pane; every other name records evidence
    /// against the pane's existing source generation. Both routes admit only an
    /// exactly qualified provider identity.
    fileprivate func providerAdmission(
        paneId: UUID,
        params: IPCSessionEventParams,
        snapshot: SessionsSnapshot
    ) throws -> SessionsProviderEventAdmissionOutcome {
        let provider = SessionsProviderIdentity(
            providerIdentifier: params.provider.identifier,
            exactVersion: params.provider.version,
            operatingMode: params.provider.mode
        )
        let capability = Self.capability(for: params.event.name)
        let qualification = providerRegistry.qualification(
            providerIdentifier: provider.providerIdentifier,
            exactVersion: provider.exactVersion,
            operatingMode: provider.operatingMode,
            capability: capability
        )
        guard case .qualified = qualification else {
            return .rejected(Self.rejectedDisposition(qualification))
        }
        let occurredAt = now()
        guard params.event.name != .sessionStart else {
            let admission = SessionsQualifiedSessionStartAdmission(
                provider: provider,
                source: SessionsBindingSourceIdentity(
                    paneId: paneId,
                    providerConversationId: params.event.conversationId,
                    sourceId: params.event.conversationId,
                    sourceGenerationId: UUIDv7.generate(),
                    occurrenceId: params.event.occurrenceId
                ),
                freshness: .live,
                reportedAt: occurredAt
            )
            guard let bind = providerRegistry.qualifiedSessionStartBind(admission) else {
                return .rejected(.unqualified)
            }
            return .admitted(.bind(bind))
        }
        guard let binding = snapshot.currentBinding, binding.status == .active else {
            throw AppIPCSessionsError(reason: .bindingRequired)
        }
        guard
            let admitted = providerRegistry.admitProviderEvidence(
                SessionsProviderEvidenceAdmission(
                    provider: provider,
                    capability: capability,
                    paneId: paneId,
                    sourceGenerationId: binding.sourceGenerationId,
                    freshness: .live
                )
            )
        else {
            return .rejected(.unqualified)
        }
        return .admitted(
            .recordEvidence(
                SessionsEvidenceMutation(
                    admittedContext: admitted,
                    occurrenceId: params.event.occurrenceId,
                    turnId: params.event.turnId,
                    subject: Self.subject(for: params.event),
                    kind: try Self.evidenceKind(for: params.event),
                    occurredAt: occurredAt,
                    sourceCursor: nil
                )
            )
        )
    }

    /// An absent profile means no capability of this provider is known at all;
    /// a present profile that omits the capability is a known refusal.
    fileprivate static func rejectedDisposition(
        _ qualification: SessionsProviderQualification
    ) -> IPCSessionEventDisposition {
        switch qualification {
        case .qualified, .unavailable: .unqualified
        case .unverified: .unknownCapability
        }
    }

    fileprivate static func capability(
        for name: IPCSessionEventName
    ) -> SessionsProviderCapability {
        switch name {
        case .sessionStart: .sessionStart
        case .sessionEnd: .sessionEnd
        case .turnStart: .turnStart
        case .turnDone: .turnDone
        case .turnAbort: .turnAbort
        case .permission: .permission
        case .question: .question
        case .elicitation: .elicitation
        case .toolActivity: .toolActivity
        case .subagentActivity: .subagentActivity
        }
    }

    fileprivate static func subject(for event: IPCSessionEventIdentity) -> SessionsEvidenceSubject {
        if let toolId = event.toolId { return .tool(toolId) }
        if let subagentId = event.subagentId { return .subagent(subagentId) }
        return .root
    }

    fileprivate static func evidenceKind(
        for event: IPCSessionEventIdentity
    ) throws -> SessionsEvidenceKind {
        switch event.name {
        case .turnStart, .toolActivity, .subagentActivity:
            return .activityStarted
        case .turnDone, .sessionEnd:
            return .completed
        case .turnAbort:
            return .aborted
        case .permission, .question, .elicitation:
            guard let requestId = event.requestId else {
                throw AppIPCSessionsError(reason: .validationRejected)
            }
            return .needsYouOpened(requestId: requestId, explanation: nil)
        case .sessionStart:
            throw AppIPCSessionsError(reason: .validationRejected)
        }
    }

    fileprivate static func agentState(_ state: SessionsAgentState) -> IPCSessionAgentState {
        switch state {
        case .unknown: .unknown
        case .running: .running
        case .needsYou: .needsYou
        case .done: .done
        }
    }

    fileprivate static func evidenceOrigin(
        _ origin: SessionsEvidenceOrigin?
    ) -> IPCSessionEvidenceOrigin {
        switch origin {
        case .none: .unknown
        case .estimated: .estimated
        case .agentReported: .agentReported
        case .reported: .reported
        }
    }

    fileprivate static func sourceHealth(
        _ binding: SessionsBindingRecord?
    ) -> IPCSessionSourceHealth {
        guard let binding else { return .unbound }
        return binding.status == .active ? .live : .ended
    }

    fileprivate static func portError(from error: any Error) -> any Error {
        guard let repositoryError = error as? SessionsRepositoryError else { return error }
        switch repositoryError {
        case .bindingRequired, .sourceNotFound, .attentionNotFound:
            return AppIPCSessionsError(reason: .bindingRequired)
        case .correlationConflict, .occurrenceConflict:
            return AppIPCSessionsError(reason: .correlationConflict)
        case .ingestionFinished, .paneQueueFull, .globalQueueFull:
            return AppIPCSessionsError(reason: .ingestionUnavailable)
        case .bindingConflict, .messageNotFound, .invalidStoredValue, .invalidPageLimit,
            .staleSnapshotCursor:
            return AppIPCSessionsError(reason: .validationRejected)
        }
    }
}
