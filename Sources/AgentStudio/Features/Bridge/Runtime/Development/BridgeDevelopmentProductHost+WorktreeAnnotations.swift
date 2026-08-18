import Foundation

extension BridgeDevelopmentProductHost {
    struct WorktreeAnnotationCommandHandlerDependencies {
        let store: WorktreeAnnotationStore?
        let outputCoordinator: WorktreeAnnotationOutputCoordinator?
        let originatingWorkspaceID: String?
        let source: BridgeDevelopmentProductSource
        let fileMetadataSource: BridgePaneProductFileMetadataSource
        let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
        let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    }

    @MainActor
    static func makeWorktreeAnnotationCommandHandler(
        _ dependencies: WorktreeAnnotationCommandHandlerDependencies
    )
        -> @MainActor @Sendable (
            BridgeProductWorktreeAnnotationCommandRequest,
            BridgeProductSurface,
            BridgeProductControlCorrelation,
            BridgeProductAdmissionContext
        ) async -> Void
    {
        guard let store = dependencies.store else { return { _, _, _, _ in } }
        let sourceResolver = WorktreeAnnotationSourceCapture.resolver(
            fileMetadataSource: dependencies.fileMetadataSource,
            reviewPublicationCoordinator: dependencies.reviewPublicationCoordinator,
            reviewContentLoaderCache: dependencies.reviewContentLoaderCache
        )
        let adapter = WorktreeAnnotationTransportAdapter(
            store: store,
            contextID: dependencies.source.paneID.uuidString.lowercased(),
            repositoryID: dependencies.source.repoID.uuidString.lowercased(),
            worktreeID: dependencies.source.worktreeID.uuidString.lowercased(),
            originatingWorkspaceID: dependencies.originatingWorkspaceID,
            sourceResolver: sourceResolver,
            outputCoordinator: dependencies.outputCoordinator,
            outputLabels: .init(
                sessionLabel: "Current review",
                worktreeLabel: dependencies.source.worktreeRoot.lastPathComponent,
                comparisonLabel: dependencies.source.reviewedSubjectLabel
            )
        )
        return { request, surface, correlation, productAdmission in
            await adapter.apply(
                request,
                surface: surface,
                correlation: correlation,
                productAdmission: productAdmission
            )
        }
    }

    @MainActor
    static func makeWorktreeAnnotationOutputCandidateQueryHandler(
        _ dependencies: WorktreeAnnotationCommandHandlerDependencies
    )
        -> @MainActor @Sendable (
            BridgeProductAnnotationCandidateQuery,
            BridgeProductSurface
        ) async throws -> WorktreeAnnotationOutputCandidatePage
    {
        guard let store = dependencies.store else {
            return { _, _ in throw WorktreeAnnotationStoreError.unavailable }
        }
        let contextID = dependencies.source.paneID.uuidString.lowercased()
        return { request, surface in
            let cursor: WorktreeAnnotationOutputCandidateCursor? =
                switch request.cursor {
                case .start:
                    nil
                case .after(let flatOrdinal, let messageID):
                    .init(flatOrdinal: flatOrdinal, messageID: .init(rawValue: messageID))
                }
            return try await store.fetchOutputCandidates(
                sessionID: .init(rawValue: request.sessionId),
                expectedSessionRevision: request.expectedSessionRevision,
                cursor: cursor,
                limit: request.limit,
                contextID: contextID,
                surface: surface
            )
        }
    }
}
