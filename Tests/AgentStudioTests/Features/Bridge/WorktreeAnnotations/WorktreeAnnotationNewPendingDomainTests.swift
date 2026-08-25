import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation New and Pending domain")
struct WorktreeAnnotationNewPendingDomainTests {
    @Test("default human saved revisions derive Pending without New")
    func defaultHumanSavedRevisionDerivesPending() throws {
        let message = messageFixture()

        let projection = try message.projectNewPendingState()

        #expect(message.authorKind == .human)
        #expect(message.viewedSavedRevision == nil)
        #expect(projection.attentionState == .notApplicable)
        #expect(!projection.isNew)
        #expect(projection.isPending)
        #expect(projection.isAllEligible)
    }

    @Test("human handled and draft states remain independent from attention")
    func humanHandledAndDraftStatesRemainIndependentFromAttention() throws {
        let handledProjection = try messageFixture(.init(handled: true)).projectNewPendingState()
        let draftProjection = try messageFixture(.init(draft: draftFixture())).projectNewPendingState()

        #expect(handledProjection.attentionState == .notApplicable)
        #expect(!handledProjection.isNew)
        #expect(!handledProjection.isPending)
        #expect(handledProjection.isAllEligible)
        #expect(draftProjection.attentionState == .notApplicable)
        #expect(!draftProjection.isNew)
        #expect(!draftProjection.isPending)
        #expect(!draftProjection.isAllEligible)
    }

    @Test("agent current revision derives exact New or viewed attention")
    func agentCurrentRevisionDerivesExactAttention() throws {
        let unseenProjection = try messageFixture(.init(authorKind: .agent)).projectNewPendingState()
        let viewedProjection = try messageFixture(
            .init(authorKind: .agent, viewedSavedRevision: 3)
        ).projectNewPendingState()
        let newerProjection = try messageFixture(
            .init(authorKind: .agent, viewedSavedRevision: 2)
        ).projectNewPendingState()

        #expect(unseenProjection.attentionState == .new)
        #expect(unseenProjection.isNew)
        #expect(!unseenProjection.isPending)
        #expect(unseenProjection.isAllEligible)
        #expect(viewedProjection.attentionState == .viewed)
        #expect(!viewedProjection.isNew)
        #expect(!viewedProjection.isPending)
        #expect(viewedProjection.isAllEligible)
        #expect(newerProjection.attentionState == .new)
        #expect(newerProjection.isNew)
    }

    @Test("author-specific invalid combinations fail closed")
    func authorSpecificInvalidCombinationsFailClosed() {
        #expect(throws: WorktreeAnnotationMessageStateValidationError.humanViewedRevision) {
            try messageFixture(.init(viewedSavedRevision: 3)).projectNewPendingState()
        }
        #expect(throws: WorktreeAnnotationMessageStateValidationError.agentDraft) {
            try messageFixture(.init(authorKind: .agent, draft: draftFixture())).projectNewPendingState()
        }
        #expect(throws: WorktreeAnnotationMessageStateValidationError.agentHandled) {
            try messageFixture(.init(authorKind: .agent, handled: true)).projectNewPendingState()
        }
        #expect(throws: WorktreeAnnotationMessageStateValidationError.agentCurrentRevisionMissing) {
            try messageFixture(
                .init(authorKind: .agent, savedBody: nil, savedRevision: nil)
            ).projectNewPendingState()
        }
        for invalidCurrentSavedRevision in [0, -1] {
            #expect(
                throws: WorktreeAnnotationMessageStateValidationError.agentCurrentRevisionIsNotPositive(
                    currentSavedRevision: invalidCurrentSavedRevision
                )
            ) {
                try messageFixture(
                    .init(
                        authorKind: .agent,
                        savedRevision: invalidCurrentSavedRevision
                    )
                ).projectNewPendingState()
            }
        }
        for invalidViewedSavedRevision in [0, -1] {
            #expect(
                throws: WorktreeAnnotationMessageStateValidationError.agentViewedRevisionIsNotPositive(
                    viewedSavedRevision: invalidViewedSavedRevision
                )
            ) {
                try messageFixture(
                    .init(
                        authorKind: .agent,
                        viewedSavedRevision: invalidViewedSavedRevision
                    )
                ).projectNewPendingState()
            }
        }
        #expect(
            throws: WorktreeAnnotationMessageStateValidationError.agentViewedRevisionIsNewerThanCurrent(
                viewedSavedRevision: 4,
                currentSavedRevision: 3
            )
        ) {
            try messageFixture(
                .init(authorKind: .agent, viewedSavedRevision: 4)
            ).projectNewPendingState()
        }
    }
}

private struct MessageFixtureProps {
    let authorKind: WorktreeAnnotationAuthorKind
    let savedBody: String?
    let savedRevision: Int?
    let draft: WorktreeAnnotationDraft?
    let handled: Bool
    let viewedSavedRevision: Int?

    init(
        authorKind: WorktreeAnnotationAuthorKind = .human,
        savedBody: String? = "Saved annotation",
        savedRevision: Int? = 3,
        draft: WorktreeAnnotationDraft? = nil,
        handled: Bool = false,
        viewedSavedRevision: Int? = nil
    ) {
        self.authorKind = authorKind
        self.savedBody = savedBody
        self.savedRevision = savedRevision
        self.draft = draft
        self.handled = handled
        self.viewedSavedRevision = viewedSavedRevision
    }
}

private func messageFixture(_ props: MessageFixtureProps = .init()) -> WorktreeAnnotationMessage {
    WorktreeAnnotationMessage(
        id: .generate(),
        threadID: .generate(),
        ordinal: 0,
        semanticRevision: 1,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        savedBody: props.savedBody,
        savedRevision: props.savedRevision,
        draft: props.draft,
        handled: props.handled,
        status: .editable,
        authorKind: props.authorKind,
        viewedSavedRevision: props.viewedSavedRevision
    )
}

private func draftFixture() -> WorktreeAnnotationDraft {
    .init(
        messageID: .generate(),
        activeEditToken: "edit-token",
        body: "Draft annotation",
        draftRevision: 1,
        updatedAt: Date(timeIntervalSince1970: 2)
    )
}
