import AgentStudioCore

package protocol SessionResumeResolving: Sendable {
    func resumeEvidence(for input: ResumeEvidenceInput) async -> ResumeEvidence
}

package struct SessionsResumeResolver: SessionResumeResolving {
    private let repository: SessionsRepository
    package init(repository: SessionsRepository) { self.repository = repository }

    @concurrent nonisolated package func resumeEvidence(for input: ResumeEvidenceInput) async -> ResumeEvidence {
        guard let snapshot = try? await repository.snapshot(.pane(input.paneId, page: .init(limit: 1, after: nil))),
            let binding = snapshot.currentBinding
        else { return .unknown(.noObservation) }
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
