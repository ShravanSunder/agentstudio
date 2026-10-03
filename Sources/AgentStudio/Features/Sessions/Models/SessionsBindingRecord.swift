import AgentStudioCore
import Foundation

/// One pane's binding generation and the evidence kept for the next restore.
/// `endedAt` is bookkeeping; only `providerEndedAt` means the provider reported an end.
package struct SessionsBindingRecord: Sendable, Codable, Equatable {
    package let bindingGenerationId: UUID
    package let paneId: UUID
    package let conversationId: UUID
    package let providerIdentifier: String
    package let providerConversationId: String
    package let sourceGenerationId: UUID
    package let transitionOccurrenceId: UUID
    package let origin: SessionsEvidenceOrigin
    package let status: SessionsBindingStatus
    package let startedAt: Date
    package let endedAt: Date?
    package let providerEndReason: ProviderEndReason?
    package let providerEndReasonText: String?
    package let providerEndedAt: Date?
    package let startedFromHistoricalReport: Bool
    package let evidenceUnordered: Bool
    package let unorderedFenceSequence: Int64?

}
