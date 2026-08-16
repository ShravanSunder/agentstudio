import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@testable import AgentStudioBridge

func makeCreateRootDraftProps() -> WorktreeAnnotationSQLiteRepository.CreateRootDraftProps {
    .init(
        admission: .implicitOrSingle,
        repositoryID: "repo-1",
        worktreeID: "worktree-1",
        originatingWorkspaceID: "workspace-1",
        sourceFingerprint: .init(
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: "source-1",
            reviewComparisonOrigin: nil
        ),
        origin: .session,
        body: "Draft",
        editToken: "editor-1",
        now: Date(timeIntervalSince1970: 2)
    )
}

func makeLocatedRootDraftProps() -> WorktreeAnnotationSQLiteRepository.CreateRootDraftProps {
    .init(
        admission: .implicitOrSingle,
        repositoryID: "repo-1",
        worktreeID: "worktree-1",
        originatingWorkspaceID: "workspace-1",
        sourceFingerprint: makeSourceFingerprint(identity: "source-original"),
        origin: .located(
            .init(
                repositoryRelativePath: "Sources/Feature.swift",
                startLine: 2,
                endLine: 2,
                sourceRole: .file,
                diffSide: nil,
                sourceIdentity: "source-original",
                selectedExcerpt: "selected line",
                contextBefore: "before",
                contextAfter: "after"
            )
        ),
        body: "Draft",
        editToken: "editor-1",
        now: Date(timeIntervalSince1970: 2)
    )
}

func makeSourceFingerprint(identity: String) -> WorktreeAnnotationSourceFingerprint {
    .init(
        repositoryID: "repo-1",
        worktreeID: "worktree-1",
        fileSourceIdentity: identity,
        reviewComparisonOrigin: nil
    )
}

func makeLocatedCommittedDetail() throws -> WorktreeAnnotationSessionDetail {
    let repository = try makeAnnotationRepository()
    return try repository.createRootDraft(makeLocatedRootDraftProps())
}

func makeSourceUpdatedDetail(
    from detail: WorktreeAnnotationSessionDetail,
    fingerprint: WorktreeAnnotationSourceFingerprint
) -> WorktreeAnnotationSessionDetail {
    WorktreeAnnotationSessionDetail(
        session: WorktreeAnnotationSession(
            id: detail.session.id,
            repositoryID: detail.session.repositoryID,
            worktreeID: detail.session.worktreeID,
            originatingWorkspaceID: detail.session.originatingWorkspaceID,
            lifecycle: detail.session.lifecycle,
            sourceRelationship: .applicable,
            acceptedSourceFingerprint: fingerprint,
            semanticRevision: detail.session.semanticRevision + 1,
            createdAt: detail.session.createdAt,
            updatedAt: Date(timeIntervalSince1970: 3),
            completedAt: detail.session.completedAt
        ),
        threads: detail.threads
    )
}

func makeCommittedDetail() throws -> WorktreeAnnotationSessionDetail {
    let repository = try makeAnnotationRepository()
    return try repository.createRootDraft(makeCreateRootDraftProps())
}

func makeAnnotationRepository() throws -> WorktreeAnnotationSQLiteRepository {
    let repository = WorktreeAnnotationSQLiteRepository(
        databaseWriter: try SQLiteDatabaseFactory.makeInMemoryQueue()
    )
    try WorkspaceLocalMigrations.migrate(repository.databaseWriter)
    return repository
}
