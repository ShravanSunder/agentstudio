import Foundation

package enum SessionsAgentState: String, Sendable, Codable, Equatable {
    case unknown
    case running
    case needsYou
    case done
}

package enum SessionsEvidenceOrigin: String, Sendable, Codable, Equatable, CaseIterable {
    case estimated
    case agentReported
    case reported

    var precedence: Int {
        switch self {
        case .estimated: 0
        case .agentReported: 1
        case .reported: 2
        }
    }
}

package enum SessionsEvidenceFreshness: String, Sendable, Codable, Equatable {
    case live
    case late
    case historical
}

package enum SessionsEvidenceSubject: Sendable, Codable, Equatable, Hashable {
    case root
    case tool(String)
    case subagent(String)

    var kind: String {
        switch self {
        case .root: "root"
        case .tool: "tool"
        case .subagent: "subagent"
        }
    }

    var identifier: String? {
        switch self {
        case .root: nil
        case .tool(let identifier), .subagent(let identifier): identifier
        }
    }

    var storageKey: String {
        switch self {
        case .root: "root"
        case .tool(let identifier): "tool:\(identifier)"
        case .subagent(let identifier): "subagent:\(identifier)"
        }
    }
}

package enum SessionsEvidenceKind: Sendable, Codable, Equatable {
    case activityStarted
    case completed
    case aborted
    case needsYouOpened(requestId: String, explanation: String?)
    case needsYouResolved(requestId: String)

    var storageKind: String {
        switch self {
        case .activityStarted: "activityStarted"
        case .completed: "completed"
        case .aborted: "aborted"
        case .needsYouOpened: "needsYouOpened"
        case .needsYouResolved: "needsYouResolved"
        }
    }
}

package struct SessionsEvidenceRecord: Sendable, Codable, Equatable {
    package let occurrenceId: UUID
    package let conversationId: UUID
    package let bindingGenerationId: UUID
    package let sourceGenerationId: UUID
    package let turnId: String?
    package let subject: SessionsEvidenceSubject
    package let kind: SessionsEvidenceKind
    package let origin: SessionsEvidenceOrigin
    package let freshness: SessionsEvidenceFreshness
    package let occurredAt: Date

}

package struct SessionsReductionInput: Sendable, Equatable {
    package let conversationId: UUID
    package let bindingGenerationId: UUID
    package let currentTurnId: String?
    package let evidence: [SessionsEvidenceRecord]
    package let endedSourceGenerationIds: Set<UUID>

    package init(
        conversationId: UUID,
        bindingGenerationId: UUID,
        currentTurnId: String?,
        evidence: [SessionsEvidenceRecord],
        endedSourceGenerationIds: Set<UUID>
    ) {
        self.conversationId = conversationId
        self.bindingGenerationId = bindingGenerationId
        self.currentTurnId = currentTurnId
        self.evidence = evidence
        self.endedSourceGenerationIds = endedSourceGenerationIds
    }
}

package enum SessionsAttentionDisposition: String, Sendable, Codable, Equatable {
    case current
    case resolved
    case stale
}

package struct SessionsAttentionProjection: Sendable, Codable, Equatable {
    package let id: UUID
    package let requestId: String
    package let explanation: String?
    package let sourceGenerationId: UUID
    package let turnId: String?
    package let subject: SessionsEvidenceSubject
    package let origin: SessionsEvidenceOrigin
    package let freshness: SessionsEvidenceFreshness
    package let disposition: SessionsAttentionDisposition
    package let openedOccurrenceId: UUID
    package let openedAt: Date
}

package struct SessionsResultProjection: Sendable, Codable, Equatable {
    package let id: UUID
    package let turnId: String
    package let subject: SessionsEvidenceSubject
    package let completionOccurrenceId: UUID
    package let origin: SessionsEvidenceOrigin
    package let freshness: SessionsEvidenceFreshness
}

package struct SessionsProjection: Sendable, Equatable {
    package let state: SessionsAgentState
    package let stateOrigin: SessionsEvidenceOrigin?
    package let currentAttention: [SessionsAttentionProjection]
    package let staleAttention: [SessionsAttentionProjection]
    package let results: [SessionsResultProjection]
    package let historicalOccurrenceIds: [UUID]
}

package enum SessionsBindTransition: Sendable, Codable, Equatable {
    case qualifiedSessionStart(occurrenceId: UUID)
    case explicitModelBind(occurrenceId: UUID)
    case unqualified(occurrenceId: UUID)

    var occurrenceId: UUID {
        switch self {
        case .qualifiedSessionStart(let occurrenceId),
            .explicitModelBind(let occurrenceId),
            .unqualified(let occurrenceId):
            occurrenceId
        }
    }

    var admittedOrigin: SessionsEvidenceOrigin? {
        switch self {
        case .qualifiedSessionStart: .reported
        case .explicitModelBind: .agentReported
        case .unqualified: nil
        }
    }
}

package struct SessionsExplicitModelBindInput: Sendable, Equatable {
    package let paneId: UUID
    package let providerIdentifier: String
    package let providerVersion: String
    package let providerMode: String
    package let providerConversationId: String
    package let sourceId: String
    package let sourceGenerationId: UUID
    package let occurrenceId: UUID
    package let reportedAt: Date

    package init(
        provider: SessionsProviderIdentity,
        source: SessionsBindingSourceIdentity,
        reportedAt: Date
    ) {
        paneId = source.paneId
        providerIdentifier = provider.providerIdentifier
        providerVersion = provider.exactVersion
        providerMode = provider.operatingMode
        providerConversationId = source.providerConversationId
        sourceId = source.sourceId
        sourceGenerationId = source.sourceGenerationId
        occurrenceId = source.occurrenceId
        self.reportedAt = reportedAt
    }
}

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

package enum SessionsReportContext: Sendable, Codable, Equatable {
    case currentPaneBinding(paneId: UUID)
    case sourceGeneration(paneId: UUID, sourceGenerationId: UUID)
    case unattributed(paneId: UUID)

    var paneId: UUID {
        switch self {
        case .currentPaneBinding(let paneId), .sourceGeneration(let paneId, _), .unattributed(let paneId):
            paneId
        }
    }
}

package struct SessionsMessageMutation: Sendable, Codable, Equatable {
    package let context: SessionsReportContext
    package let text: String
    package let freshness: SessionsEvidenceFreshness
    package let receivedAt: Date

    package init(
        context: SessionsReportContext,
        text: String,
        freshness: SessionsEvidenceFreshness = .live,
        receivedAt: Date
    ) {
        self.context = context
        self.text = text
        self.freshness = freshness
        self.receivedAt = receivedAt
    }
}

package struct SessionsEvidenceMutation: Sendable, Codable, Equatable {
    package let context: SessionsReportContext
    package let occurrenceId: UUID
    package let turnId: String?
    package let subject: SessionsEvidenceSubject
    package let kind: SessionsEvidenceKind
    package let origin: SessionsEvidenceOrigin
    package let freshness: SessionsEvidenceFreshness
    package let occurredAt: Date
    package let sourceCursor: String?

    init(
        context: SessionsReportContext,
        occurrenceId: UUID,
        turnId: String?,
        subject: SessionsEvidenceSubject,
        kind: SessionsEvidenceKind,
        origin: SessionsEvidenceOrigin,
        freshness: SessionsEvidenceFreshness,
        occurredAt: Date,
        sourceCursor: String?
    ) {
        self.context = context
        self.occurrenceId = occurrenceId
        self.turnId = turnId
        self.subject = subject
        self.kind = kind
        self.origin = origin
        self.freshness = freshness
        self.occurredAt = occurredAt
        self.sourceCursor = sourceCursor
    }

    package init(
        admittedContext: SessionsAdmittedEvidenceContext,
        occurrenceId: UUID,
        turnId: String?,
        subject: SessionsEvidenceSubject,
        kind: SessionsEvidenceKind,
        occurredAt: Date,
        sourceCursor: String?
    ) {
        context = admittedContext.reportContext
        self.occurrenceId = occurrenceId
        self.turnId = turnId
        self.subject = subject
        self.kind = kind
        origin = admittedContext.origin
        freshness = admittedContext.freshness
        self.occurredAt = occurredAt
        self.sourceCursor = sourceCursor
    }
}

/// A deliberate report carries the freshness of the route that admitted it. A
/// late report is one the CLI spooled while the app was unreachable, so it may
/// land after the binding it was written against has already ended.
package struct SessionsDeliberateNeedsYouMutation: Sendable, Codable, Equatable {
    package let paneId: UUID
    package let explanation: String
    package let freshness: SessionsEvidenceFreshness
    package let reportedAt: Date

    package init(
        paneId: UUID,
        explanation: String,
        freshness: SessionsEvidenceFreshness = .live,
        reportedAt: Date
    ) {
        self.paneId = paneId
        self.explanation = explanation
        self.freshness = freshness
        self.reportedAt = reportedAt
    }
}

package struct SessionsClearDeliberateNeedsYouMutation: Sendable, Codable, Equatable {
    package let paneId: UUID
    package let freshness: SessionsEvidenceFreshness
    package let clearedAt: Date

    package init(
        paneId: UUID,
        freshness: SessionsEvidenceFreshness = .live,
        clearedAt: Date
    ) {
        self.paneId = paneId
        self.freshness = freshness
        self.clearedAt = clearedAt
    }
}

package struct SessionsDeliberateDoneMutation: Sendable, Codable, Equatable {
    package let paneId: UUID
    package let freshness: SessionsEvidenceFreshness
    package let reportedAt: Date

    package init(
        paneId: UUID,
        freshness: SessionsEvidenceFreshness = .live,
        reportedAt: Date
    ) {
        self.paneId = paneId
        self.freshness = freshness
        self.reportedAt = reportedAt
    }
}

package struct SessionsSourceEndMutation: Sendable, Codable, Equatable {
    package let paneId: UUID
    package let sourceGenerationId: UUID
    package let endedAt: Date

    package init(paneId: UUID, sourceGenerationId: UUID, endedAt: Date) {
        self.paneId = paneId
        self.sourceGenerationId = sourceGenerationId
        self.endedAt = endedAt
    }
}

package struct SessionsMessageAcknowledgmentMutation: Sendable, Codable, Equatable {
    package let occurrenceId: UUID
    package let acknowledgedAt: Date

    package init(occurrenceId: UUID, acknowledgedAt: Date) {
        self.occurrenceId = occurrenceId
        self.acknowledgedAt = acknowledgedAt
    }
}

package enum SessionsLossReason: String, Sendable, Codable, Equatable {
    case paneQueueFull
    case globalQueueFull
}

package struct SessionsLiveLossMutation: Sendable, Codable, Equatable {
    package let paneId: UUID
    package let eventKind: String
    package let reason: SessionsLossReason
    package let occurredAt: Date
}

package enum SessionsMutation: Sendable, Codable, Equatable {
    case bind(SessionsBindMutation)
    case message(SessionsMessageMutation)
    case recordEvidence(SessionsEvidenceMutation)
    case deliberateNeedsYou(SessionsDeliberateNeedsYouMutation)
    case clearDeliberateNeedsYou(SessionsClearDeliberateNeedsYouMutation)
    case deliberateDone(SessionsDeliberateDoneMutation)
    case sourceEnded(SessionsSourceEndMutation)
    case acknowledgeMessage(SessionsMessageAcknowledgmentMutation)
    case recordLiveLoss(SessionsLiveLossMutation)
    case prepareForLaunch(Date)
}

package enum SessionsBindingStatus: String, Sendable, Codable, Equatable {
    case active
    case ended
}

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
}

package enum SessionsBindingOutcome: Sendable, Codable, Equatable {
    case established(SessionsBindingRecord)
    case replaced(SessionsBindingRecord, SessionsBindingRecord)
    case unchanged(SessionsBindingRecord)
}

package enum SessionsMessageAttribution: String, Sendable, Codable, Equatable {
    case attributed
    case unattributed
}

package enum SessionsSeenDisposition: String, Sendable, Codable, Equatable {
    case unseen
    case seen
}

package struct SessionsMessageRecord: Sendable, Codable, Equatable {
    package let occurrenceId: UUID
    package let paneId: UUID
    package let conversationId: UUID?
    package let bindingGenerationId: UUID?
    package let sourceGenerationId: UUID?
    package let text: String
    package let attribution: SessionsMessageAttribution
    package let freshness: SessionsEvidenceFreshness
    package let disposition: SessionsSeenDisposition
    package let reportedAt: Date
}

package struct SessionsResultRecord: Sendable, Codable, Equatable {
    package let id: UUID
    package let conversationId: UUID
    package let bindingGenerationId: UUID
    package let sourceGenerationId: UUID
    package let turnId: String
    package let subject: SessionsEvidenceSubject
    package let completionOccurrenceId: UUID
    package let origin: SessionsEvidenceOrigin
    package let freshness: SessionsEvidenceFreshness
    package let disposition: SessionsSeenDisposition
    package let seenAt: Date?
    package let createdAt: Date
    package let updatedAt: Date
}

package enum SessionsMutationOutcome: Sendable, Codable, Equatable {
    case binding(SessionsBindingOutcome)
    case messageSaved(occurrenceId: UUID, attribution: SessionsMessageAttribution)
    case evidenceRecorded(occurrenceId: UUID)
    case historical(occurrenceId: UUID)
    case attentionRecorded(requestId: String, occurrenceId: UUID)
    case attentionCleared(requestId: String)
    case resultRecorded(resultId: UUID, occurrenceId: UUID)
    case sourceEnded(sourceGenerationId: UUID)
    case messageAcknowledged(occurrenceId: UUID, changed: Bool)
    case lossRecorded(id: UUID)
    case launchPrepared(activeSourcesEnded: Int)
}

package struct SessionsLaunchPreparationOutcome: Sendable, Equatable {
    package let activeSourcesEnded: Int
}

package struct SessionsSnapshotCursor: Sendable, Equatable {
    package let snapshotRevision: Int64
    package let commitRevision: Int64
    package let occurrenceId: UUID

    package init(snapshotRevision: Int64, commitRevision: Int64, occurrenceId: UUID) {
        self.snapshotRevision = snapshotRevision
        self.commitRevision = commitRevision
        self.occurrenceId = occurrenceId
    }
}

package struct SessionsSnapshotPage: Sendable, Equatable {
    package let limit: Int
    package let after: SessionsSnapshotCursor?

    package init(limit: Int, after: SessionsSnapshotCursor?) {
        self.limit = limit
        self.after = after
    }
}

package enum SessionsSnapshotQuery: Sendable, Equatable {
    case pane(UUID, page: SessionsSnapshotPage)
    case unattributed(page: SessionsSnapshotPage)

    package init(paneId: UUID, page: SessionsSnapshotPage) {
        self = .pane(paneId, page: page)
    }
}

package struct SessionsSnapshot: Sendable, Equatable {
    package let revision: Int64
    package let currentBinding: SessionsBindingRecord?
    package let state: SessionsAgentState
    package let stateOrigin: SessionsEvidenceOrigin?
    package let messages: [SessionsMessageRecord]
    package let currentAttention: [SessionsAttentionProjection]
    package let staleAttention: [SessionsAttentionProjection]
    package let results: [SessionsResultRecord]
    package let historicalOccurrenceIds: [UUID]
    package let losses: [SessionsLossRecord]
    package let nextCursor: SessionsSnapshotCursor?
}

package enum SessionsRepositoryError: Error, Sendable, Equatable {
    case bindingRequired(UUID)
    case bindingConflict(UUID)
    case correlationConflict(UUID)
    case occurrenceConflict(UUID)
    case messageNotFound(UUID)
    case sourceNotFound(UUID)
    case attentionNotFound(UUID)
    case invalidStoredValue(String)
    case invalidPageLimit(Int)
    case staleSnapshotCursor(expectedRevision: Int64, actualRevision: Int64)
    case ingestionFinished
    case paneQueueFull(UUID)
    case globalQueueFull
}
