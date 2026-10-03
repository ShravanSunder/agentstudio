import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package protocol SessionResumeResolving: Sendable {
    func resumeEvidence(for input: ResumeEvidenceInput) async -> ResumeEvidence
}

package struct SessionsResumeResolver: SessionResumeResolving {
    private let repository: SessionsRepository
    /// Restore R3 "decide" cost phase: the real synchronous work is the
    /// classification below `classify`, after the one genuine suspension
    /// (`repository.snapshot`) has already resolved.
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    package init(repository: SessionsRepository, performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil) {
        self.repository = repository
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    @concurrent nonisolated package func resumeEvidence(for input: ResumeEvidenceInput) async -> ResumeEvidence {
        let snapshot = try? await repository.snapshot(.pane(input.paneId, page: .init(limit: 1, after: nil)))
        return timedForRestoreDecide { Self.classify(snapshot: snapshot, input: input) }
    }

    /// Times `body` as one "decide" execution when a recorder was injected.
    /// `classify` never awaits, so this is a real synchronous slice taken
    /// after the one genuine suspension (`repository.snapshot`) resolved.
    private func timedForRestoreDecide<T>(_ body: () -> T) -> T {
        guard let performanceTraceRecorder else { return body() }
        let start = ContinuousClock.now
        let executedOnMainThread = Thread.isMainThread
        let result = body()
        performanceTraceRecorder.recordRestorePhaseDuration(
            .restoreResumeDecide, duration: start.duration(to: .now), executedOnMainThread: executedOnMainThread)
        return result
    }

    /// Pure classification, no suspensions — everything `resumeEvidence`
    /// does once its one real await has already resolved.
    private static func classify(snapshot: SessionsSnapshot?, input: ResumeEvidenceInput) -> ResumeEvidence {
        guard let snapshot, let binding = snapshot.currentBinding else { return .unknown(.noObservation) }
        if binding.providerEndedAt != nil { return .knownExited(binding.providerEndReason ?? .notGiven) }
        if binding.startedFromHistoricalReport { return .unknown(.startedFromHistoricalReport) }
        if binding.evidenceUnordered { return .unknown(.evidenceUnordered) }
        guard let observation = input.observation else { return .unknown(.noObservation) }
        guard observation.paneId == input.paneId, observation.zmxSessionId == input.zmxSessionId,
            observation.bindingGenerationId == binding.bindingGenerationId,
            let identity = try? ZmxSessionIdentity.decode(observation.sessionIdentity)
        else { return .unknown(.observationMismatch) }
        guard let provider = ResumeProvider(providerIdentifier: binding.providerIdentifier) else {
            return .unknown(.unknownProvider)
        }
        guard observation.program == (provider == .claudeCode ? .claudeCode : .codex) else {
            return .unknown(.programNotAgent)
        }
        if identity.bootID == input.launchBootId {
            guard case .complete(let sessions) = input.inventory, sessions[input.zmxSessionId] == nil else {
                return .unknown(.observationMismatch)
            }
        }
        guard let sessionId = try? ProviderSessionId(rawValue: binding.providerConversationId) else {
            return .unknown(.invalidSessionId)
        }
        return .interruptedCandidate(ResumeInvocation(provider: provider, sessionId: sessionId))
    }
}
