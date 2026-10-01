import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioSessions

@Suite("Session resume resolver")
struct SessionResumeResolverTests {
    @Test("a matching foreground look resumes the exact closed-provider id", arguments: ["claude-code", "codex"])
    func matchingLookIsCandidate(providerIdentifier: String) async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind(providerIdentifier: providerIdentifier)
        let observation = try fixture.observation(
            binding: binding, program: providerIdentifier == "codex" ? .codex : .claudeCode)
        let result = await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
        let provider = try #require(ResumeProvider(providerIdentifier: providerIdentifier))
        #expect(
            result
                == .interruptedCandidate(
                    ResumeInvocation(
                        provider: provider,
                        sessionId: try ProviderSessionId(rawValue: fixture.providerSessionId))))
    }

    @Test(
        "every reported end wins over historical, unordered and missing foreground evidence",
        arguments: [ProviderEndReason.personExit, .providerOther, .notGiven, .unrecognized])
    func reportedEndHasPrecedence(reason: ProviderEndReason) async throws {
        let fixture = try ResumeResolverFixture()
        _ = try await fixture.bind()
        try await fixture.setEvidenceFlags(historical: true, unordered: true)
        try await fixture.reportEnd(reason)
        #expect(await fixture.resolver.resumeEvidence(for: fixture.input(observation: nil)) == .knownExited(reason))
    }

    @Test("launch bookkeeping alone does not turn an interrupted agent into known exited")
    func sweepEndedBindingCanStillResume() async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        let observation = try fixture.observation(binding: binding)
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            _ = try await ingestion.prepareForLaunch(at: Date(timeIntervalSince1970: 2))
        }
        let snapshot = try await fixture.repository.snapshot(makeSessionsSnapshotQuery(paneId: fixture.paneId))
        #expect(snapshot.currentBinding?.status == .ended)
        #expect(snapshot.currentBinding?.providerEndedAt == nil)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .interruptedCandidate(
                    ResumeInvocation(
                        provider: .claudeCode,
                        sessionId: try ProviderSessionId(rawValue: fixture.providerSessionId))))
    }

    @Test("same-boot daemon loss is a reboot-equivalent only when no provider end was reported")
    func sameBootAbsenceCanResume() async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        let observation = try fixture.observation(binding: binding, bootId: fixture.launchBootId)
        let candidate = ResumeEvidence.interruptedCandidate(
            ResumeInvocation(
                provider: .claudeCode,
                sessionId: try ProviderSessionId(rawValue: fixture.providerSessionId)))
        #expect(await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation)) == candidate)
        try await fixture.reportEnd(.providerOther)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .knownExited(.providerOther))
    }

    @Test("no foreground look means unknown rather than resuming the last session in a folder")
    func noLookIsUnknown() async throws {
        let fixture = try ResumeResolverFixture()
        _ = try await fixture.bind()
        #expect(await fixture.resolver.resumeEvidence(for: fixture.input(observation: nil)) == .unknown(.noObservation))
    }

    @Test("a look from another binding or zmx session never resumes this binding", arguments: [false, true])
    func mismatchedObservationIsUnknown(otherSession: Bool) async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        let observation = try fixture.observation(
            binding: binding,
            generation: otherSession ? nil : UUIDv7.generate(), sessionId: otherSession ? .generateUUIDv7() : nil)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .unknown(.observationMismatch))
    }

    @Test(
        "shell, other, unknown and the wrong agent program cannot prove this agent was foreground",
        arguments: [ForegroundProgram.shell, .other, .unknown, .codex])
    func wrongProgramIsUnknown(program: ForegroundProgram) async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        let observation = try fixture.observation(binding: binding, program: program)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .unknown(.programNotAgent))
    }

    @Test("a historical start with a positive look still cannot resume")
    func historicalStartIsUnknown() async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        try await fixture.setEvidenceFlags(historical: true)
        let observation = try fixture.observation(binding: binding)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .unknown(.startedFromHistoricalReport))
    }

    @Test("an unordered start with a positive look still cannot resume")
    func unorderedEvidenceIsUnknown() async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        try await fixture.setEvidenceFlags(unordered: true)
        let observation = try fixture.observation(binding: binding)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .unknown(.evidenceUnordered))
    }

    @Test(
        "an option or malformed provider session id never reaches a resume argv",
        arguments: ["--last", "last in folder", "bad-id"])
    func malformedSessionIdIsUnknown(sessionId: String) async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind(sessionId: sessionId)
        let observation = try fixture.observation(binding: binding)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .unknown(.invalidSessionId))
    }

    @Test("a provider outside the closed command set remains unknown")
    func unsupportedProviderIsUnknown() async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind(providerIdentifier: "future-provider")
        let observation = try fixture.observation(binding: binding)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .unknown(.unknownProvider))
    }

    @Test(
        "same-boot liveness or an unavailable inventory cannot be treated as daemon death",
        arguments: [ZmxSessionInventory.unavailable(.timedOut), .unavailable(.unparsable)])
    func unverifiableDeathIsUnknown(inventory: ZmxSessionInventory) async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        let observation = try fixture.observation(binding: binding, bootId: fixture.launchBootId)
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation, inventory: inventory))
                == .unknown(.observationMismatch))
        #expect(
            await fixture.resolver.resumeEvidence(
                for: fixture.input(
                    observation: observation,
                    inventory: .complete([fixture.zmxSessionId: .alive(wrapperPid: 6000)])))
                == .unknown(.observationMismatch))
    }

    @Test("a later provider end does not mutate the previously decided value")
    func verdictIsAnImmutableValue() async throws {
        let fixture = try ResumeResolverFixture()
        let binding = try await fixture.bind()
        let observation = try fixture.observation(binding: binding)
        let decided = await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
        try await fixture.reportEnd(.personExit)
        #expect(
            decided
                == .interruptedCandidate(
                    ResumeInvocation(
                        provider: .claudeCode,
                        sessionId: try ProviderSessionId(rawValue: fixture.providerSessionId))))
        #expect(
            await fixture.resolver.resumeEvidence(for: fixture.input(observation: observation))
                == .knownExited(.personExit))
    }
}
