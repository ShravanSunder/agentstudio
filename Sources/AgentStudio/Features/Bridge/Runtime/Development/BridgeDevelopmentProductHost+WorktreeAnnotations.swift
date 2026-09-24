import Foundation

extension BridgeDevelopmentProductHost {
    struct WorktreeAnnotationCommandHandlerDependencies {
        let store: WorktreeAnnotationServiceActor?
        let outputCoordinator: WorktreeAnnotationOutputCoordinatorActor?
        let source: BridgeDevelopmentProductSource
        let fileMetadataSource: BridgeFileCollectionSource
        let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
        let reviewContentLoaderCache: BridgeReviewContentLoaderCache
        let reviewSourceProvider: any BridgeReviewSourceProvider
    }

    static func makeWorktreeAnnotationSourceResolver(
        _ dependencies: WorktreeAnnotationCommandHandlerDependencies
    ) -> WorktreeAnnotationSourceResolver {
        WorktreeAnnotationSourceCapture.resolver(
            fileMetadataSource: dependencies.fileMetadataSource,
            reviewScope: .review(
                repositoryID: dependencies.source.repoID.uuidString.lowercased(),
                worktreeID: dependencies.source.worktreeID.uuidString.lowercased()
            ),
            reviewPublicationCoordinator: dependencies.reviewPublicationCoordinator,
            reviewContentLoaderCache: dependencies.reviewContentLoaderCache,
            gitEvidenceSource: dependencies.reviewSourceProvider as? any WorktreeAnnotationGitEvidenceSource
        )
    }

    static func makeWorktreeAnnotationProjectionSource(
        _ dependencies: WorktreeAnnotationCommandHandlerDependencies
    ) -> BridgeAnnotationProjectionSource {
        guard let service = dependencies.store else { return .unavailable }
        let sourceResolver = makeWorktreeAnnotationSourceResolver(dependencies)
        return BridgeAnnotationProjectionSource(
            service: service,
            sourceResolver: sourceResolver,
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
        let adapter = WorktreeAnnotationTransportAdapter(
            store: store,
            contextID: dependencies.source.paneID.uuidString.lowercased(),
            sourceResolver: makeWorktreeAnnotationSourceResolver(dependencies),
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
