import Foundation

struct SessionsBindSemanticIntent: Encodable {
    let paneId: UUID
    let providerIdentifier: String
    let providerVersion: String
    let providerMode: String
    let providerConversationId: String
    let sourceId: String
    let transition: SessionsBindTransition
    let resumeHint: String?
    let ownerPaneId: UUID?

    init(_ mutation: SessionsBindMutation) {
        paneId = mutation.paneId
        providerIdentifier = mutation.providerIdentifier
        providerVersion = mutation.providerVersion
        providerMode = mutation.providerMode
        providerConversationId = mutation.providerConversationId
        sourceId = mutation.sourceId
        transition = mutation.transition
        resumeHint = mutation.resumeHint
        ownerPaneId = mutation.ownerPaneId
    }
}

struct SessionsProviderEvidenceSemanticIntent: Encodable {
    let context: SessionsReportContext
    let occurrenceId: UUID
    let turnId: String?
    let subject: SessionsEvidenceSubject
    let kind: SessionsEvidenceKind
    let sourceCursor: String?
    let sourceOccurredAt: Date?
    let providerSignal: SessionProviderSignal?

    init(_ mutation: SessionsEvidenceMutation) {
        context = mutation.context
        occurrenceId = mutation.occurrenceId
        turnId = mutation.turnId
        subject = mutation.subject
        kind = mutation.kind
        sourceCursor = mutation.sourceCursor
        sourceOccurredAt = mutation.sourceOccurredAt
        providerSignal = mutation.providerSignal
    }
}
