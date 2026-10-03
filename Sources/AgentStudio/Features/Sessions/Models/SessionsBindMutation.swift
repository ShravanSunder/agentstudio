import Foundation

package struct SessionsBindMutation: Sendable, Codable, Equatable {
    package let paneId: UUID
    package let providerIdentifier: String
    package let providerVersion: String
    package let providerMode: String
    package let providerConversationId: String
    package let sourceId: String
    package let sourceGenerationId: UUID
    package let transition: SessionsBindTransition
    package let freshness: SessionsEvidenceFreshness
    package let reportedAt: Date

    package let startedFromHistoricalReport: Bool

    package init(
        paneId: UUID, providerIdentifier: String, providerVersion: String, providerMode: String,
        providerConversationId: String, sourceId: String, sourceGenerationId: UUID,
        transition: SessionsBindTransition, freshness: SessionsEvidenceFreshness, reportedAt: Date,
        startedFromHistoricalReport: Bool = false
    ) {
        self.paneId = paneId
        self.providerIdentifier = providerIdentifier
        self.providerVersion = providerVersion
        self.providerMode = providerMode
        self.providerConversationId = providerConversationId
        self.sourceId = sourceId
        self.sourceGenerationId = sourceGenerationId
        self.transition = transition
        self.freshness = freshness
        self.reportedAt = reportedAt
        self.startedFromHistoricalReport = startedFromHistoricalReport
    }

    package func recordingHistoricalStart() -> Self {
        Self(
            paneId: paneId, providerIdentifier: providerIdentifier, providerVersion: providerVersion,
            providerMode: providerMode, providerConversationId: providerConversationId, sourceId: sourceId,
            sourceGenerationId: sourceGenerationId, transition: transition, freshness: .historical,
            reportedAt: reportedAt, startedFromHistoricalReport: true)
    }

    package static func explicitModelBind(
        _ input: SessionsExplicitModelBindInput
    ) -> Self {
        Self(
            paneId: input.paneId,
            providerIdentifier: input.providerIdentifier,
            providerVersion: input.providerVersion,
            providerMode: input.providerMode,
            providerConversationId: input.providerConversationId,
            sourceId: input.sourceId,
            sourceGenerationId: input.sourceGenerationId,
            transition: .explicitModelBind(occurrenceId: input.occurrenceId),
            freshness: .live,
            reportedAt: input.reportedAt
        )
    }
}
