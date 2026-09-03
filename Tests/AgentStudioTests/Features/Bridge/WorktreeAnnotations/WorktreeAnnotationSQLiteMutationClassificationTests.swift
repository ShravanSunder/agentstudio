import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation SQLite mutation classification")
struct WorktreeAnnotationMutationClassificationTests {
    @Test("topology, content, control, and no-op commits retain their canonical details")
    func primaryClassificationsRetainCanonicalDetails() throws {
        let repository = try makeRepository()
        let created = try repository.createRootDraft(classificationRootProps())
        let createdDetail = created.canonicalResult

        #expect(
            created.change
                == .catalog(
                    worktreeIDs: ["worktree-1"],
                    sessionChanges: [
                        .init(
                            worktreeID: "worktree-1",
                            sessionID: createdDetail.session.id,
                            semanticRevision: createdDetail.session.semanticRevision
                        )
                    ]
                )
        )

        let message = try #require(createdDetail.threads.first?.messages.first)
        let content = try repository.flushDraft(
            .init(
                sessionID: createdDetail.session.id,
                messageID: message.id,
                editToken: "classification-editor",
                expectedMessageRevision: message.semanticRevision,
                expectedDraftRevision: message.draft?.draftRevision,
                body: "Changed draft body",
                now: Date(timeIntervalSince1970: 2)
            )
        )
        #expect(
            content.change
                == .content(
                    sessionChanges: [
                        .init(
                            worktreeID: "worktree-1",
                            sessionID: content.canonicalResult.session.id,
                            semanticRevision: content.canonicalResult.session.semanticRevision
                        )
                    ]
                )
        )

        let thread = try #require(content.canonicalResult.threads.first?.thread)
        let noOp = try repository.setThreadResolution(
            .init(
                sessionID: content.canonicalResult.session.id,
                threadID: thread.id,
                resolution: .open,
                expectedThreadRevision: thread.semanticRevision,
                now: Date(timeIntervalSince1970: 3)
            )
        )
        #expect(noOp.change == .noChange)
        #expect(noOp.canonicalResult == content.canonicalResult)

        let control = try repository.setSessionLifecycle(
            .init(
                sessionID: noOp.canonicalResult.session.id,
                lifecycle: .completed,
                expectedSessionRevision: noOp.canonicalResult.session.semanticRevision,
                expectedOpenThreadCount: 1,
                confirmsUnresolvedWork: true,
                now: Date(timeIntervalSince1970: 4)
            )
        )
        #expect(
            control.change
                == .control(
                    worktreeIDs: ["worktree-1"],
                    reason: .discovery,
                    sessionChanges: [
                        .init(
                            worktreeID: "worktree-1",
                            sessionID: control.canonicalResult.session.id,
                            semanticRevision: control.canonicalResult.session.semanticRevision
                        )
                    ]
                )
        )
    }

    @Test("deleting an unsaved draft classifies catalog topology")
    func deletingUnsavedDraftClassifiesCatalogTopology() throws {
        let repository = try makeRepository()
        let created = try repository.createRootDraft(classificationRootProps())
        let message = try #require(created.canonicalResult.threads.first?.messages.first)

        let deleted = try repository.flushDraft(
            .init(
                sessionID: created.canonicalResult.session.id,
                messageID: message.id,
                editToken: "classification-editor",
                expectedMessageRevision: message.semanticRevision,
                expectedDraftRevision: message.draft?.draftRevision,
                body: "  \n",
                now: Date(timeIntervalSince1970: 2)
            )
        )

        #expect(deleted.canonicalResult.threads.isEmpty)
        guard case .catalog(let worktreeIDs, let sessionChanges) = deleted.change else {
            Issue.record("Expected a catalog-classified deletion")
            return
        }
        #expect(worktreeIDs == ["worktree-1"])
        #expect(sessionChanges.map(\.semanticRevision) == [deleted.canonicalResult.session.semanticRevision])
    }
}

private func classificationRootProps() -> WorktreeAnnotationSQLiteRepository.CreateRootDraftProps {
    .init(
        admission: .implicitOrSingle,
        repositoryID: "repo-1",
        worktreeID: "worktree-1",
        sourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-1"),
        origin: .session,
        body: "Initial draft",
        editToken: "classification-editor",
        now: Date(timeIntervalSince1970: 1)
    )
}
