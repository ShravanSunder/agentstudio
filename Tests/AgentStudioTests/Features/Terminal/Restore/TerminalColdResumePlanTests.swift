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
        "known exited keeps R1's own notice lines untouched and still carries no resume",
        arguments: [ProviderEndReason.personExit, .providerOther, .notGiven, .unrecognized])
    func knownExitedKeepsR1sNoticeUntouched(reason: ProviderEndReason) throws {
        let base = try resumeReadinessBasePlan(resumeReadinessDescriptor())
        let plan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .knownExited(reason),
            providerIdentifier: "claude-code", providerSessionId: UUIDv7.generate().uuidString, to: base)
        #expect(plan.resume == nil)
        // F5 (review round 1, 2026-10-01; RS2, SR3): an empty outcome text
        // composes onto R1's own line, leaving it exactly as R1 wrote it --
        // never replacing it with an empty string.
        #expect(plan.notice.linesByCandidateIndex == base.notice.linesByCandidateIndex)
        #expect(plan.folderCandidates == base.folderCandidates)
        #expect(plan.attemptID == base.attemptID)
    }

    @Test("the R3 outcome composes onto R1's own notice line instead of replacing it")
    func outcomeComposesOntoR1sNoticeInsteadOfReplacingIt() throws {
        // Arrange -- three candidates, including the repository-main-folder
        // fallback line the review named explicitly, each carrying its own
        // distinct R1 text so a replacement (instead of a composition)
        // would be unmistakable.
        let base = TerminalColdRestorePlan(
            zmxExecutable: URL(fileURLWithPath: "/unused/zmx"),
            zmxDirectory: URL(fileURLWithPath: "/unused/zmx-root"),
            sessionID: try #require(ZmxSessionID(restoring: "as-f5-compose-test")),
            loginShell: URL(fileURLWithPath: "/bin/zsh"),
            folderCandidates: [
                URL(fileURLWithPath: "/tmp/saved"), URL(fileURLWithPath: "/tmp/repo-main"),
                URL(fileURLWithPath: "/tmp/home"),
            ],
            notice: ColdRestoreNotice(linesByCandidateIndex: [
                "Restored after restart",
                "Restored after restart (saved folder missing; using the repository's main folder)",
                "Restored after restart (saved and repository folders missing; using the home folder)",
            ]),
            replayFile: nil, resume: nil, attemptID: .generate())

        // Assert -- `.knownExited`: empty outcome text, R1 lines unchanged.
        let knownExited = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .knownExited(.personExit), providerIdentifier: "claude-code",
            providerSessionId: UUIDv7.generate().uuidString, to: base)
        #expect(knownExited.resume == nil)
        #expect(knownExited.notice.linesByCandidateIndex == base.notice.linesByCandidateIndex)

        // Assert -- `.interruptedCandidate`: "R1 line\noutcome" for every candidate.
        let text = UUIDv7.generate().uuidString
        let invocation = ResumeInvocation(provider: .codex, sessionId: try ProviderSessionId(rawValue: text))
        let interrupted = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .interruptedCandidate(invocation), providerIdentifier: "codex", providerSessionId: text, to: base)
        let interruptedOutcome = "Resumed Codex session \(text.prefix(8)) after restart"
        for (index, line) in interrupted.notice.linesByCandidateIndex.enumerated() {
            #expect(line == "\(base.notice.linesByCandidateIndex[index])\n\(interruptedOutcome)")
        }

        // Assert -- `.unknown`: "R1 line\noutcome" for every candidate.
        let unknown = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            .unknown(.noObservation), providerIdentifier: "codex", providerSessionId: text, to: base)
        let unknownOutcome = "Could not determine whether Codex session \(text.prefix(8)) exited; resume it manually."
        for (index, line) in unknown.notice.linesByCandidateIndex.enumerated() {
            #expect(line == "\(base.notice.linesByCandidateIndex[index])\n\(unknownOutcome)")
        }

        // Assert -- the unchecked notice: "R1 line\noutcome" for every candidate.
        let uncheckedAgentState = TerminalColdRestorePlanBuilder.applyingUncheckedAgentStateNotice(to: base)
        let uncheckedOutcome =
            "Agent state couldn't be checked before restore; if an agent was running here, resume it manually."
        for (index, line) in uncheckedAgentState.notice.linesByCandidateIndex.enumerated() {
            #expect(line == "\(base.notice.linesByCandidateIndex[index])\n\(uncheckedOutcome)")
        }
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
