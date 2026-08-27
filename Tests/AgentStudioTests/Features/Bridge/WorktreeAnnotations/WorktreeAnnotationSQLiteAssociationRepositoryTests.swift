import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation SQLite association repository")
struct WorktreeAnnotationSQLiteAssociationRepositoryTests {
    @Test("foreign discovery is repository scoped and excludes the current worktree")
    func foreignDiscoveryIsRepositoryScoped() throws {
        let repository = try makeRepository()
        let first = try repository.createRootDraft(
            .init(
                admission: .implicitOrSingle,
                repositoryID: "repo-1",
                worktreeID: "worktree-a",
                sourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-a"),
                origin: .session,
                body: "Foreign candidate",
                editToken: "foreign-editor",
                now: Date(timeIntervalSince1970: 1)
            )
        ).canonicalResult
        _ = try repository.createRootDraft(
            .init(
                admission: .implicitOrSingle,
                repositoryID: "repo-2",
                worktreeID: "worktree-c",
                sourceFingerprint: .init(
                    repositoryID: "repo-2",
                    worktreeID: "worktree-c",
                    fileSourceIdentity: "file-source-other",
                    reviewComparisonOrigin: nil
                ),
                origin: .session,
                body: "Other repository",
                editToken: "other-editor",
                now: Date(timeIntervalSince1970: 2)
            )
        )

        let candidates = try repository.discoverForeignLivingSessionCandidates(
            repositoryID: "repo-1",
            excludingWorktreeID: "worktree-b"
        )

        #expect(candidates.map(\.id) == [first.session.id])
        #expect(
            try repository.discoverForeignLivingSessionCandidates(
                repositoryID: "repo-1",
                excludingWorktreeID: "worktree-a"
            ).isEmpty
        )
    }

    @Test("association acceptance atomically moves the session and accepted evidence under exact fences")
    func associationAcceptanceIsAtomicAndFenced() throws {
        let repository = try makeRepository()
        let original = try repository.createRootDraft(
            .init(
                admission: .implicitOrSingle,
                repositoryID: "repo-1",
                worktreeID: "worktree-a",
                sourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-a"),
                acceptedReviewedSubject: try .init(
                    branchName: "feature/x",
                    reviewedHeadOID: "1111111111111111111111111111111111111111"
                ),
                origin: .session,
                body: "Move me",
                editToken: "move-editor",
                now: Date(timeIntervalSince1970: 1)
            )
        ).canonicalResult
        let currentEvidence = try WorktreeAnnotationReviewedSubjectEvidence(
            branchName: "feature/x",
            reviewedHeadOID: "2222222222222222222222222222222222222222"
        )

        let moved = try repository.acceptCurrentAssociation(
            .init(
                sessionID: original.session.id,
                expectedSessionRevision: original.session.semanticRevision,
                expectedRepositoryID: "repo-1",
                previousWorktreeID: "worktree-a",
                currentWorktreeID: "worktree-b",
                acceptedReviewedSubject: currentEvidence,
                acceptedSourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-b"),
                now: Date(timeIntervalSince1970: 2)
            )
        ).canonicalResult

        #expect(moved.previousWorktreeID == "worktree-a")
        #expect(moved.currentWorktreeID == "worktree-b")
        #expect(moved.detail.session.id == original.session.id)
        #expect(moved.detail.session.worktreeID == "worktree-b")
        #expect(moved.detail.session.acceptedReviewedSubject == currentEvidence)
        #expect(moved.detail.session.sourceRelationship == .applicable)
        #expect(moved.detail.session.semanticRevision == original.session.semanticRevision + 1)
        #expect(try repository.discoverSessions(worktreeID: "worktree-a").isEmpty)
        #expect(try repository.discoverSessions(worktreeID: "worktree-b").map(\.id) == [original.session.id])

        #expect(
            throws: WorktreeAnnotationRepositoryError.conflict(currentRevision: moved.detail.session.semanticRevision)
        ) {
            try repository.acceptCurrentAssociation(
                .init(
                    sessionID: original.session.id,
                    expectedSessionRevision: original.session.semanticRevision,
                    expectedRepositoryID: "repo-1",
                    previousWorktreeID: "worktree-a",
                    currentWorktreeID: "worktree-c",
                    acceptedReviewedSubject: currentEvidence,
                    acceptedSourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-c"),
                    now: Date(timeIntervalSince1970: 3)
                )
            )
        }
    }

    @Test("explicit new-session admission reuses the one current applicable session")
    func explicitNewSessionAdmissionRechecksCurrentWorktree() throws {
        let repository = try makeRepository()
        let first = try makeRootDraft(repository: repository)

        let secondRoot = try repository.createRootDraft(
            .init(
                admission: .newSession,
                repositoryID: "repo-1",
                worktreeID: "worktree-1",
                sourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-1"),
                origin: .session,
                body: "Second root, same session",
                editToken: "second-root-editor",
                now: Date(timeIntervalSince1970: 2)
            )
        ).canonicalResult

        #expect(secondRoot.session.id == first.session.id)
        #expect(secondRoot.threads.count == 2)
        #expect(try repository.discoverSessions(worktreeID: "worktree-1").count == 1)
    }
}

func makeRepository() throws -> WorktreeAnnotationSQLiteRepository {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    return WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
}

func makeSourceFingerprint(worktreeID: String) -> WorktreeAnnotationSourceFingerprint {
    WorktreeAnnotationSourceFingerprint(
        repositoryID: "repo-1",
        worktreeID: worktreeID,
        fileSourceIdentity: "file-source-1",
        reviewComparisonOrigin: nil
    )
}

func makeRootDraft(repository: WorktreeAnnotationSQLiteRepository) throws -> WorktreeAnnotationSessionDetail {
    try repository.createRootDraft(
        .init(
            admission: .implicitOrSingle,
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            sourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-1"),
            origin: .located(
                .init(
                    repositoryRelativePath: "Sources/Feature.swift",
                    startLine: 1,
                    endLine: 1,
                    sourceRole: .file,
                    diffSide: nil,
                    sourceIdentity: "file-source-1",
                    selectedExcerpt: "let value = 1",
                    contextBefore: nil,
                    contextAfter: nil
                )
            ),
            body: "Root draft",
            editToken: "editor-root",
            now: Date(timeIntervalSince1970: 1)
        )
    ).canonicalResult
}
