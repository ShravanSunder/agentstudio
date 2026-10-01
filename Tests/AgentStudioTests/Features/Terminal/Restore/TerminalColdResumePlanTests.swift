import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

@Suite("Terminal cold resume plan")
struct TerminalColdResumePlanTests {
    @Test(
        "a candidate carries its exact invocation and provider-specific short-id notice",
        arguments: ["claude-code", "codex"])
    func candidateNoticeAndInvocation(providerIdentifier: String) throws {
        let descriptor = resumeReadinessDescriptor()
        let base = try resumeReadinessBasePlan(descriptor)
        let text = UUIDv7.generate().uuidString
        let provider = try #require(ResumeProvider(providerIdentifier: providerIdentifier))
        let invocation = ResumeInvocation(provider: provider, sessionId: try ProviderSessionId(rawValue: text))
        let plan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .interruptedCandidate(invocation),
            providerIdentifier: providerIdentifier, providerSessionId: text, to: base)
        let label = providerIdentifier == "codex" ? "Codex" : "Claude Code"
        #expect(plan.resume == invocation)
        #expect(
            plan.notice.linesByCandidateIndex.allSatisfy {
                $0.contains("Resumed \(label) session \(text.prefix(8)) after restart")
            })
        #expect(plan.folderCandidates == base.folderCandidates)
        #expect(plan.attemptID == base.attemptID)
        #expect(plan.sessionID == base.sessionID)
    }

    @Test(
        "known exited produces no resume and no one-line notice",
        arguments: [ProviderEndReason.personExit, .providerOther, .notGiven, .unrecognized])
    func knownExitedIsSilent(reason: ProviderEndReason) throws {
        let base = try resumeReadinessBasePlan(resumeReadinessDescriptor())
        let plan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .knownExited(reason),
            providerIdentifier: "claude-code", providerSessionId: UUIDv7.generate().uuidString, to: base)
        #expect(plan.resume == nil)
        let everyCandidateNoticeIsEmpty = plan.notice.linesByCandidateIndex.allSatisfy { $0.isEmpty }
        #expect(everyCandidateNoticeIsEmpty)
        #expect(plan.folderCandidates == base.folderCandidates)
        #expect(plan.attemptID == base.attemptID)
    }

    @Test(
        "every unknown reason keeps a shell and names the provider and short id",
        arguments: [
            ResumeUnknownReason.noObservation, .observationMismatch, .programNotAgent, .startedFromHistoricalReport,
            .evidenceUnordered, .invalidSessionId, .unknownProvider, .reportsNotTakenIn,
        ])
    func unknownNoticeHasAttribution(reason: ResumeUnknownReason) throws {
        let base = try resumeReadinessBasePlan(resumeReadinessDescriptor())
        let text = UUIDv7.generate().uuidString
        let plan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .unknown(reason),
            providerIdentifier: "codex", providerSessionId: text, to: base)
        #expect(plan.resume == nil)
        #expect(
            plan.notice.linesByCandidateIndex.allSatisfy { $0.contains("Codex") && $0.contains(String(text.prefix(8))) }
        )
        #expect(plan.notice.linesByCandidateIndex.allSatisfy { !$0.hasPrefix("Resumed ") })
        #expect(plan.attemptID == base.attemptID)
    }

    @Test("the resume argv runs inside an interactive login shell rather than the pre-handoff script shell")
    func commandEntersLoginShellForResume() throws {
        let descriptor = resumeReadinessDescriptor()
        let base = try resumeReadinessBasePlan(descriptor)
        let text = UUIDv7.generate().uuidString
        let invocation = ResumeInvocation(provider: .codex, sessionId: try ProviderSessionId(rawValue: text))
        let plan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .interruptedCandidate(invocation),
            providerIdentifier: "codex", providerSessionId: text, to: base)
        let command = ZmxBackend.buildColdRestoreCommand(plan)
        #expect(command.contains("-i -l -c"))
        #expect(command.contains("codex"))
        #expect(command.contains(text))
        #expect(command.contains("exec"))
    }
}
