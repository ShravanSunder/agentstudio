import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation source evaluator")
struct WorktreeAnnotationSourceEvaluatorTests {
    @Test("surface refresh merges its provenance without erasing the other surface")
    func surfaceRefreshMergesAcceptedFingerprintProvenance() throws {
        let reviewOrigin = WorktreeAnnotationReviewComparisonOrigin(
            symbolicTarget: #"{"kind":"branch","name":"main","basis":"merge_base"}"#,
            resolvedTargetOID: "target-oid",
            reviewedHeadOID: "head-oid",
            baseRole: "merge_base",
            baseOID: "base-oid"
        )
        let accepted = WorktreeAnnotationSourceFingerprint(
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: "file-old",
            reviewComparisonOrigin: reviewOrigin
        )
        let session = makeSourceEvaluationSession(fingerprint: accepted)

        let fileResult = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [],
                surface: .file,
                sourceEpoch: "1",
                currentFingerprint: .init(
                    repositoryID: "repo-1",
                    worktreeID: "worktree-1",
                    fileSourceIdentity: "file-new",
                    reviewComparisonOrigin: nil
                ),
                material: .available([])
            )
        )
        #expect(fileResult.acceptedSourceFingerprint?.fileSourceIdentity == "file-new")
        #expect(fileResult.acceptedSourceFingerprint?.reviewComparisonOrigin == reviewOrigin)

        let reviewResult = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: makeSourceEvaluationSession(
                    fingerprint: try #require(fileResult.acceptedSourceFingerprint)
                ),
                threads: [],
                surface: .review,
                sourceEpoch: "2",
                currentFingerprint: .init(
                    repositoryID: "repo-1",
                    worktreeID: "worktree-1",
                    fileSourceIdentity: "foreign-file-value",
                    reviewComparisonOrigin: reviewOrigin
                ),
                material: .available([])
            )
        )
        #expect(reviewResult.acceptedSourceFingerprint?.fileSourceIdentity == "file-new")
        #expect(reviewResult.acceptedSourceFingerprint?.reviewComparisonOrigin == reviewOrigin)
    }
    @Test("matching lineage stays applicable and exact source bytes retain their line")
    func matchingLineageProducesExactPlacement() throws {
        let session = makeSourceEvaluationSession()
        let thread = makeLocatedEvaluationThread(sessionID: session.id)
        let currentFingerprint = WorktreeAnnotationSourceFingerprint(
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: "file-source-2",
            reviewComparisonOrigin: nil
        )

        let result = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "file-epoch-2",
                currentFingerprint: currentFingerprint,
                material: .available([
                    .init(
                        path: "Sources/Feature.swift",
                        sourceRole: .file,
                        sourceIdentity: "file-source-2",
                        body: "before\nselected line\nafter\n"
                    )
                ])
            )
        )

        #expect(result.sourceRelationship == .applicable)
        #expect(result.acceptedSourceFingerprint == currentFingerprint)
        #expect(
            result.placements[thread.id]
                == .init(
                    placement: .exact,
                    currentPath: "Sources/Feature.swift",
                    currentStartLine: 2,
                    currentEndLine: 2,
                    currentSourceIdentity: "file-source-2"
                )
        )
    }

    @Test("File surface places Review head origins against current working-tree material")
    func fileSurfacePlacesReviewHeadOriginsAgainstCurrentFileMaterial() throws {
        let session = makeSourceEvaluationSession()
        let locatedThread = makeLocatedEvaluationThread(
            sessionID: session.id,
            sourceRole: .reviewHead,
            diffSide: .additions
        )
        let result = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [locatedThread],
                surface: .file,
                sourceEpoch: "file-epoch-2",
                currentFingerprint: .init(
                    repositoryID: "repo-1",
                    worktreeID: "worktree-1",
                    fileSourceIdentity: "file-source-2",
                    reviewComparisonOrigin: nil
                ),
                material: .available([
                    .init(
                        path: "Sources/Feature.swift",
                        sourceRole: .file,
                        sourceIdentity: "file-source-2",
                        body: "before\nselected line\nafter\n"
                    )
                ])
            )
        )

        #expect(result.placements[locatedThread.id]?.placement == .exact)
        #expect(result.placements[locatedThread.id]?.currentStartLine == 2)
        #expect(result.placements[locatedThread.id]?.currentSourceIdentity == "file-source-2")
    }

    @Test("File surface never maps Review base origins onto working-tree material")
    func fileSurfaceDoesNotPlaceReviewBaseOriginAgainstCurrentFileMaterial() throws {
        let session = makeSourceEvaluationSession()
        let thread = makeLocatedEvaluationThread(
            sessionID: session.id,
            sourceRole: .reviewBase,
            diffSide: .deletions
        )

        let result = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "file-epoch-2",
                currentFingerprint: .init(
                    repositoryID: "repo-1",
                    worktreeID: "worktree-1",
                    fileSourceIdentity: "file-source-2",
                    reviewComparisonOrigin: nil
                ),
                material: .available([
                    .init(
                        path: "Sources/Feature.swift",
                        sourceRole: .file,
                        sourceIdentity: "file-source-2",
                        body: "before\nselected line\nafter\n"
                    )
                ])
            )
        )

        #expect(result.placements[thread.id]?.placement == .outdated)
        #expect(result.placements[thread.id]?.currentPath == nil)
    }

    @Test("one context match relocates while duplicate matches remain outdated")
    func uniqueAndAmbiguousContextMatchesAreDistinguished() throws {
        let session = makeSourceEvaluationSession()
        let thread = makeLocatedEvaluationThread(sessionID: session.id)
        let currentFingerprint = WorktreeAnnotationSourceFingerprint(
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: "file-source-2",
            reviewComparisonOrigin: nil
        )
        let uniqueMaterial = WorktreeAnnotationSourceMaterial.available([
            .init(
                path: "Sources/RenamedFeature.swift",
                sourceRole: .file,
                sourceIdentity: "file-source-2",
                body: "prefix\nbefore\nselected line\nafter\nsuffix\n"
            )
        ])

        let relocated = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "file-epoch-2",
                currentFingerprint: currentFingerprint,
                material: uniqueMaterial
            )
        )
        let ambiguous = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "file-epoch-3",
                currentFingerprint: currentFingerprint,
                material: .available([
                    .init(
                        path: "Sources/First.swift",
                        sourceRole: .file,
                        sourceIdentity: "file-source-3",
                        body: "before\nselected line\nafter\n"
                    ),
                    .init(
                        path: "Sources/Second.swift",
                        sourceRole: .file,
                        sourceIdentity: "file-source-3",
                        body: "before\nselected line\nafter\n"
                    ),
                ])
            )
        )

        #expect(relocated.placements[thread.id]?.placement == .relocated)
        #expect(relocated.placements[thread.id]?.currentPath == "Sources/RenamedFeature.swift")
        #expect(relocated.placements[thread.id]?.currentStartLine == 3)
        #expect(ambiguous.placements[thread.id]?.placement == .outdated)
        #expect(ambiguous.placements[thread.id]?.currentPath == nil)
    }

    @Test("missing evidence is uncertain, different lineage detaches, and read failure is unavailable")
    func continuityAndUnavailablePlacementRemainIndependent() throws {
        let session = makeSourceEvaluationSession()
        let thread = makeLocatedEvaluationThread(sessionID: session.id)
        let missingEvidence = WorktreeAnnotationSourceFingerprint(
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: nil,
            reviewComparisonOrigin: nil
        )
        let differentLineage = WorktreeAnnotationSourceFingerprint(
            repositoryID: "repo-2",
            worktreeID: "worktree-2",
            fileSourceIdentity: "file-source-2",
            reviewComparisonOrigin: nil
        )

        let uncertain = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "missing",
                currentFingerprint: missingEvidence,
                material: .unavailable
            )
        )
        let detached = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "different",
                currentFingerprint: differentLineage,
                material: .unavailable
            )
        )
        let unavailable = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: [thread],
                surface: .file,
                sourceEpoch: "file-epoch-2",
                currentFingerprint: WorktreeAnnotationSourceFingerprint(
                    repositoryID: "repo-1",
                    worktreeID: "worktree-1",
                    fileSourceIdentity: "file-source-2",
                    reviewComparisonOrigin: nil
                ),
                material: .unavailable
            )
        )

        #expect(uncertain.sourceRelationship == .uncertain)
        #expect(uncertain.placements.isEmpty)
        #expect(detached.sourceRelationship == .detached)
        #expect(detached.placements.isEmpty)
        #expect(unavailable.sourceRelationship == .applicable)
        #expect(unavailable.placements[thread.id]?.placement == .unavailable)
    }
}

private func makeSourceEvaluationSession(
    fingerprint: WorktreeAnnotationSourceFingerprint = .init(
        repositoryID: "repo-1",
        worktreeID: "worktree-1",
        fileSourceIdentity: "file-source-1",
        reviewComparisonOrigin: nil
    )
) -> WorktreeAnnotationSession {
    WorktreeAnnotationSession(
        id: .generate(),
        repositoryID: "repo-1",
        worktreeID: "worktree-1",
        originatingWorkspaceID: nil,
        lifecycle: .living,
        sourceRelationship: .applicable,
        acceptedSourceFingerprint: fingerprint,
        semanticRevision: 1,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        completedAt: nil
    )
}

private func makeLocatedEvaluationThread(
    sessionID: WorktreeAnnotationSessionID,
    sourceRole: WorktreeAnnotationSourceRole = .file,
    diffSide: WorktreeAnnotationDiffSide? = nil
) -> WorktreeAnnotationThread {
    WorktreeAnnotationThread(
        id: .generate(),
        sessionID: sessionID,
        origin: .located(
            .init(
                repositoryRelativePath: "Sources/Feature.swift",
                startLine: 2,
                endLine: 2,
                sourceRole: sourceRole,
                diffSide: diffSide,
                sourceIdentity: "file-source-1",
                selectedExcerpt: "selected line",
                contextBefore: "before",
                contextAfter: "after"
            )
        ),
        resolution: .open,
        createdOrdinal: 0,
        semanticRevision: 0,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        resolvedAt: nil
    )
}
