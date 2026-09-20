import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioSessions

@Suite("Sessions evidence reducer")
struct SessionsEvidenceReducerTests {
    @Test("reported root activity outranks identifier-free agent-reported completion")
    func reportedRootActivityOutranksIdentifierFreeCompletion() throws {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let rootActivity = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .activityStarted,
            origin: .reported,
            timestamp: 1
        )
        let identifierFreeCompletion = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            subject: .root,
            kind: .completed,
            origin: .agentReported,
            timestamp: 2
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-root",
                evidence: [rootActivity, identifierFreeCompletion],
                endedSourceGenerationIds: []
            )
        )

        #expect(projection.state == .running)
        #expect(projection.stateOrigin == .reported)
    }

    @Test("provider-identified subagent completion does not complete the root")
    func providerIdentifiedSubagentCompletionDoesNotCompleteRoot() {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let subagentCompletion = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            subject: .subagent("provider-child-1"),
            kind: .completed,
            origin: .reported,
            timestamp: 1
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-root",
                evidence: [subagentCompletion],
                endedSourceGenerationIds: []
            )
        )

        #expect(projection.state == .unknown)
        #expect(projection.results.map(\.subject) == [.subagent("provider-child-1")])
        #expect(!projection.results.contains { $0.subject == .root })
    }

    @Test("reported actionable evidence outranks matching completion")
    func actionableEvidenceOutranksCompletion() {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let completion = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .completed,
            origin: .reported,
            timestamp: 1
        )
        let attention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .needsYouOpened(requestId: "provider-request", explanation: "Choose one"),
            origin: .reported,
            timestamp: 2
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-root",
                evidence: [completion, attention],
                endedSourceGenerationIds: []
            )
        )

        #expect(projection.state == .needsYou)
        #expect(projection.stateOrigin == .reported)
        #expect(projection.currentAttention.map(\.requestId) == ["provider-request"])
        #expect(projection.results.count == 1)
    }

    @Test("clear and abort affect only matching identities")
    func clearAndAbortAffectOnlyMatchingIdentities() {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let otherSourceGenerationId = UUIDv7.generate()
        let matchingAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .needsYouOpened(requestId: "matching-request", explanation: nil),
            origin: .reported,
            timestamp: 1
        )
        let otherAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: otherSourceGenerationId,
            kind: .needsYouOpened(requestId: "other-request", explanation: nil),
            origin: .reported,
            timestamp: 2
        )
        let wrongClear = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .needsYouResolved(requestId: "other-request"),
            origin: .reported,
            timestamp: 3
        )
        let matchingClear = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .needsYouResolved(requestId: "matching-request"),
            origin: .reported,
            timestamp: 4
        )
        let abort = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            kind: .aborted,
            origin: .reported,
            timestamp: 5
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-root",
                evidence: [matchingAttention, otherAttention, wrongClear, matchingClear, abort],
                endedSourceGenerationIds: []
            )
        )

        #expect(projection.state == .needsYou)
        #expect(projection.currentAttention.map(\.requestId) == ["other-request"])
        #expect(projection.results.isEmpty)
    }

    @Test("old generation late evidence is history only")
    func oldGenerationLateEvidenceIsHistoryOnly() {
        let conversationId = UUIDv7.generate()
        let currentBindingGenerationId = UUIDv7.generate()
        let endedBindingGenerationId = UUIDv7.generate()
        let currentSourceGenerationId = UUIDv7.generate()
        let endedSourceGenerationId = UUIDv7.generate()
        let currentActivity = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: currentBindingGenerationId,
            sourceGenerationId: currentSourceGenerationId,
            kind: .activityStarted,
            origin: .reported,
            timestamp: 2
        )
        let lateCompletion = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: endedBindingGenerationId,
            sourceGenerationId: endedSourceGenerationId,
            kind: .completed,
            origin: .reported,
            freshness: .late,
            timestamp: 3
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: currentBindingGenerationId,
                currentTurnId: "turn-root",
                evidence: [currentActivity, lateCompletion],
                endedSourceGenerationIds: [endedSourceGenerationId]
            )
        )

        #expect(projection.state == .running)
        #expect(projection.results.isEmpty)
        #expect(projection.historicalOccurrenceIds == [lateCompletion.occurrenceId])
    }

    @Test("source loss stales provider attention and removes deliberate help from current state")
    func sourceLossStalesAttentionWithoutInventingCompletion() {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let providerSourceGenerationId = UUIDv7.generate()
        let deliberateSourceGenerationId = UUIDv7.generate()
        let providerAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: providerSourceGenerationId,
            kind: .needsYouOpened(requestId: "provider-request", explanation: nil),
            origin: .reported,
            timestamp: 1
        )
        let deliberateAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: deliberateSourceGenerationId,
            kind: .needsYouOpened(requestId: "agent-request", explanation: nil),
            origin: .agentReported,
            timestamp: 2
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-root",
                evidence: [providerAttention, deliberateAttention],
                endedSourceGenerationIds: [providerSourceGenerationId, deliberateSourceGenerationId]
            )
        )

        #expect(projection.state == .unknown)
        #expect(projection.currentAttention.isEmpty)
        #expect(projection.staleAttention.map(\.requestId) == ["provider-request"])
        #expect(projection.results.isEmpty)
    }

    @Test("matching clear preserves the same request in another turn or subject")
    func matchingClearIncludesTurnAndSubject() {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let oldRootAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: "turn-old",
            kind: .needsYouOpened(requestId: "reused-request", explanation: "old root"),
            origin: .reported,
            timestamp: 1
        )
        let currentRootAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: "turn-current",
            kind: .needsYouOpened(requestId: "reused-request", explanation: "current root"),
            origin: .reported,
            timestamp: 2
        )
        let currentChildAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: "turn-current",
            subject: .subagent("child-1"),
            kind: .needsYouOpened(requestId: "reused-request", explanation: "current child"),
            origin: .reported,
            timestamp: 3
        )
        let oldRootClear = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: "turn-old",
            kind: .needsYouResolved(requestId: "reused-request"),
            origin: .reported,
            timestamp: 4
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-current",
                evidence: [
                    oldRootAttention,
                    currentRootAttention,
                    currentChildAttention,
                    oldRootClear,
                ],
                endedSourceGenerationIds: []
            )
        )

        #expect(projection.state == .needsYou)
        #expect(projection.currentAttention.count == 2)
        #expect(Set(projection.currentAttention.map(\.subject)) == [.root, .subagent("child-1")])
        #expect(projection.currentAttention.allSatisfy { $0.turnId == "turn-current" })
    }

    @Test("later-arriving old-turn attention cannot override current root activity")
    func oldTurnAttentionIsHistoricalAgainstCurrentTurn() {
        let conversationId = UUIDv7.generate()
        let bindingGenerationId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let currentRootActivity = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: "turn-current",
            kind: .activityStarted,
            origin: .reported,
            timestamp: 1
        )
        let oldTurnAttention = makeSessionsEvidence(
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: "turn-old",
            kind: .needsYouOpened(requestId: "old-request", explanation: "arrived late"),
            origin: .reported,
            timestamp: 2
        )

        let projection = SessionsEvidenceReducer.reduce(
            SessionsReductionInput(
                conversationId: conversationId,
                bindingGenerationId: bindingGenerationId,
                currentTurnId: "turn-current",
                evidence: [currentRootActivity, oldTurnAttention],
                endedSourceGenerationIds: []
            )
        )

        #expect(projection.state == .running)
        #expect(projection.stateOrigin == .reported)
        #expect(projection.currentAttention.isEmpty)
        #expect(projection.historicalOccurrenceIds.contains(oldTurnAttention.occurrenceId))
    }
}
