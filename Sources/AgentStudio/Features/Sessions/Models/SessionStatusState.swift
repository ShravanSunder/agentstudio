import AgentStudioCore
import Foundation

package enum SessionBindingPhase: Sendable, Equatable {
    case bound(UUID)
    case ended(at: Date)
    case replaced(by: UUID, at: Date)
}

package enum SessionTurnPhase: Sendable, Equatable {
    case notStarted
    case working
    case done(at: Date, admittedAt: ContinuousClock.Instant)
    case interrupted(at: Date)
    case failed(SessionFailureSummary, at: Date)
}

package enum ProviderPromptKey: Sendable, Equatable, Hashable {
    case toolCall(String)
    case elicitation(String)
    case permission(Int64)
}

package struct SessionQuestion: Sendable, Equatable {
    package let question: String
    package let header: String
    package let options: [SessionQuestionOption]
    package let multiSelect: Bool
}

package struct SessionQuestionOption: Sendable, Equatable {
    package let label: String
    package let description: String
}

package struct ProviderPrompt: Sendable, Equatable {
    package let key: ProviderPromptKey
    package let reason: AskReason
    package let observedAt: Date
    package let summary: String?
    package let turnId: String?
    package let questions: [SessionQuestion]?
    package var absorbedPermission: Bool
}

package struct OpenAskSummary: Sendable, Equatable {
    package let sequence: Int64
    package let approval: Int
    package let question: Int
    package let blocked: Int
}

package enum AgentLineWork: Sendable, Equatable {
    case monitoring
}

package struct SessionStatusState: Sendable, Equatable {
    package var binding: SessionBindingPhase
    package var turn: SessionTurnPhase = .notStarted
    package var providerPrompts: [ProviderPromptKey: ProviderPrompt] = [:]
    package var openAsks = OpenAskSummary(sequence: 0, approval: 0, question: 0, blocked: 0)
    package var lineWork: AgentLineWork?
    package var seenAfterDone = false
}

package enum SessionStatusInput: Sendable, Equatable {
    case sessionStart(generation: UUID)
    case userPromptSubmit
    case toolActivity
    case subagentActivity
    case permission(toolName: String?, questions: [SessionQuestion]?)
    case question(toolCallId: String, questions: [SessionQuestion])
    case toolCompleted(toolCallId: String)
    case toolFailed(toolCallId: String)
    case elicitation(id: String?, occurrenceId: UUID, summary: String?)
    case elicitationResult(id: String?)
    case stop
    case stopFailure(SessionFailureSummary)
    case interrupt
    case sessionEnd
    case bindingReplaced(by: UUID)
    case openAsks(OpenAskSummary)
    case agentLine(AgentLineWork?)
    case paneViewed(ContinuousClock.Instant)
}

package struct SessionStatusEvent: Sendable, Equatable {
    package let input: SessionStatusInput
    package let sequence: Int64
    package let occurredAt: Date
    package let admittedAt: ContinuousClock.Instant
    package let turnId: String?
}

/// The off-main status seam. Its behavioral implementation follows the RED gate.
package enum SessionStatusReducer {
    package static func apply(_ event: SessionStatusEvent, to state: inout SessionStatusState) {}

    package static func status(of state: SessionStatusState) -> AgentSessionStatus {
        .unknown
    }
}
