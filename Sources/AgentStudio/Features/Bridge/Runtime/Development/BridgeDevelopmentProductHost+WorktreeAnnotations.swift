import Foundation

extension BridgeDevelopmentProductHost {
    struct WorktreeAnnotationCommandHandlerDependencies {
        let store: WorktreeAnnotationServiceActor?
        let outputCoordinator: WorktreeAnnotationOutputCoordinatorActor?
        let originatingWorkspaceID: String?
        let source: BridgeDevelopmentProductSource
        let fileMetadataSource: BridgePaneProductFileMetadataSource
        let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
        let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    }

    static func makeWorktreeAnnotationProjectionSource(
        _ dependencies: WorktreeAnnotationCommandHandlerDependencies
    ) -> BridgeAnnotationProjectionSource {
        guard let service = dependencies.store else { return .unavailable }
        let sourceResolver = WorktreeAnnotationSourceCapture.resolver(
            fileMetadataSource: dependencies.fileMetadataSource,
            reviewPublicationCoordinator: dependencies.reviewPublicationCoordinator,
            reviewContentLoaderCache: dependencies.reviewContentLoaderCache
        )
        return BridgeAnnotationProjectionSource(
            service: service,
            sourceResolver: sourceResolver,
            worktreeID: dependencies.source.worktreeID.uuidString.lowercased(),
            currentSourceGeneration: sourceResolver.currentSourceGeneration
        )
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
        ) async -> BridgeProductWorktreeAnnotationCommandOutcomeDTO
    {
        guard let store = dependencies.store else {
            return { _, surface, correlation, _ in
                BridgeProductWorktreeAnnotationCommandOutcomeDTO(
                    .init(
                        requestID: correlation.requestId,
                        surface: surface,
                        sessionID: nil,
                        status: .failed(.unavailable)
                    )
                )
            }
        }
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

}
