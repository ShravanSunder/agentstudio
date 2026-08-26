import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

struct BridgeDevelopmentProductProviderPreparationInput {
    let gitReadContext: BridgeGitReadContext
    let reviewInitialization: BridgeDevelopmentProductReviewInitialization
    let reviewProvider: any BridgeReviewSourceProvider
    let source: BridgeDevelopmentProductSource
    let worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor?
    let worktreeAnnotationStore: WorktreeAnnotationServiceActor?
}

struct BridgeDevelopmentProductProviderPreparation {
    let committedCallTarget: BridgeDevelopmentProductCommittedCallTarget
    let constructionCoordinator: BridgeWorktreeProductConstructionCoordinator
    let fileMetadataSource: BridgePaneProductFileMetadataSource
    let productAdmission: BridgeProductAdmissionContext
    let productAdmissionGate: BridgeProductAdmissionGate
    let productProvider: BridgePaneProductSchemeProvider
    let productSessionOwner: BridgePaneProductSessionOwner
    let refreshAdmissionCoordinator: BridgePaneRefreshAdmissionCoordinator
    let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    let reviewSharedConstructionBinder: BridgePaneReviewSharedConstructionBinder?
}

private struct BridgeDevelopmentProductProviderDependencies {
    let annotationOutputSource: BridgePaneProductWorktreeAnnotationOutputSource
    let annotationProjectionSource: BridgeAnnotationProjectionSource
    let annotationSource: BridgePaneAnnotationNotificationSource
    let applyWorktreeAnnotationCommand:
        @MainActor @Sendable (
            BridgeProductWorktreeAnnotationCommandRequest,
            BridgeProductSurface,
            BridgeProductControlCorrelation,
            BridgeProductAdmissionContext
        ) async -> BridgeProductWorktreeAnnotationCommandOutcomeDTO
    let applyReviewComparisonUpdate:
        @MainActor @Sendable (
            BridgeProductReviewComparisonUpdateRequest,
            BridgeProductAdmissionContext
        ) async -> Void
    let applyFileRefreshRetry: @MainActor @Sendable (BridgeProductAdmissionContext) async -> Void
    let fileMetadataSource: BridgePaneProductFileMetadataSource
    let initialPresentation: BridgePaneProductPresentationSnapshot
    let refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
    let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    let reviewMetadataSource: BridgePaneProductReviewMetadataSource
    let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    let reviewSourceProvider: any BridgeReviewSourceProvider
    let reviewComparisonTargetProjection: BridgeReviewComparisonTargetProjection
}

extension BridgeDevelopmentProductHost {
    static func makeProductProviderPreparation(
        _ input: BridgeDevelopmentProductProviderPreparationInput
    ) async throws -> BridgeDevelopmentProductProviderPreparation {
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let reviewSharedConstructionBinder = makeReviewSharedConstructionBinder(
            coordinator: constructionCoordinator,
            pipeline: input.reviewInitialization.pipeline,
            provider: input.reviewProvider,
            repositoryPath: input.source.worktreeRoot
        )
        let fileMetadataSource = makeFileMetadataSource(
            source: input.source,
            gitReadContext: input.gitReadContext,
            constructionCoordinator: constructionCoordinator
        )
        let reviewContentLoaderCache = BridgeReviewContentLoaderCache(
            provider: input.reviewProvider
        )
        let reviewPublicationCoordinator = await MainActor.run {
            BridgeReviewPublicationCoordinator()
        }
        let committedCallTarget = await MainActor.run {
            BridgeDevelopmentProductCommittedCallTarget()
        }
        let refreshAdmissionCoordinator = await makeRefreshAdmissionCoordinator(
            initialReviewTarget: input.reviewInitialization.initialTarget,
            repositoryDefaultTarget: input.reviewInitialization.defaultTarget
        )
        let refreshWorkAdmissionSource = await MainActor.run {
            refreshAdmissionCoordinator.workAdmissionSource
        }
        let initialPresentation = await refreshAdmissionCoordinator.productPresentationSnapshot
        let annotationHandlerDependencies = makeWorktreeAnnotationHandlerDependencies(
            input: input,
            fileMetadataSource: fileMetadataSource,
            reviewPublicationCoordinator: reviewPublicationCoordinator,
            reviewContentLoaderCache: reviewContentLoaderCache,
            reviewSourceProvider: input.reviewProvider
        )
        let annotationCommandHandler = await MainActor.run {
            makeWorktreeAnnotationCommandHandler(annotationHandlerDependencies)
        }
        let productProvider = makeProductProvider(
            dependencies: BridgeDevelopmentProductProviderDependencies(
                annotationOutputSource: BridgePaneProductWorktreeAnnotationOutputSource(
                    store: input.worktreeAnnotationStore
                ),
                annotationProjectionSource: makeWorktreeAnnotationProjectionSource(
                    annotationHandlerDependencies
                ),
                annotationSource: BridgePaneAnnotationNotificationSource(
                    service: input.worktreeAnnotationStore,
                    worktreeID: input.source.worktreeID.uuidString.lowercased()
                ),
                applyWorktreeAnnotationCommand: annotationCommandHandler,
                applyReviewComparisonUpdate: { request, productAdmission in
                    await committedCallTarget.applyReviewComparisonUpdate(
                        request,
                        productAdmission: productAdmission
                    )
                },
                applyFileRefreshRetry: committedCallTarget.applyFileRefreshRetry,
                fileMetadataSource: fileMetadataSource,
                initialPresentation: initialPresentation,
                refreshWorkAdmissionSource: refreshWorkAdmissionSource,
                reviewContentLoaderCache: reviewContentLoaderCache,
                reviewMetadataSource: BridgePaneProductReviewMetadataSource(),
                reviewPublicationCoordinator: reviewPublicationCoordinator,
                reviewSourceProvider: input.reviewProvider,
                reviewComparisonTargetProjection: input.reviewInitialization
                    .comparisonTargetProjection
            )
        )
        let productAdmissionGate = BridgeProductAdmissionGate()
        guard let productAdmission = productAdmissionGate.acquire() else {
            throw BridgeDevelopmentProductHostError.shutdown
        }
        let productSessionOwner = try BridgePaneProductSessionOwner(
            paneSessionId: input.source.paneID.uuidString,
            provider: productProvider,
            productAdmissionGate: productAdmissionGate,
            didRetireWorkerInstance: { workerInstanceId in
                await reviewPublicationCoordinator.retireDisplayWorker(
                    workerInstanceId: workerInstanceId
                )
            }
        )
        return BridgeDevelopmentProductProviderPreparation(
            committedCallTarget: committedCallTarget,
            constructionCoordinator: constructionCoordinator,
            fileMetadataSource: fileMetadataSource,
            productAdmission: productAdmission,
            productAdmissionGate: productAdmissionGate,
            productProvider: productProvider,
            productSessionOwner: productSessionOwner,
            refreshAdmissionCoordinator: refreshAdmissionCoordinator,
            reviewContentLoaderCache: reviewContentLoaderCache,
            reviewPublicationCoordinator: reviewPublicationCoordinator,
            reviewSharedConstructionBinder: reviewSharedConstructionBinder
        )
    }

    private static func makeWorktreeAnnotationHandlerDependencies(
        input: BridgeDevelopmentProductProviderPreparationInput,
        fileMetadataSource: BridgePaneProductFileMetadataSource,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator,
        reviewContentLoaderCache: BridgeReviewContentLoaderCache,
        reviewSourceProvider: any BridgeReviewSourceProvider
    ) -> WorktreeAnnotationCommandHandlerDependencies {
        .init(
            store: input.worktreeAnnotationStore,
            outputCoordinator: input.worktreeAnnotationOutputCoordinator,
            source: input.source,
            fileMetadataSource: fileMetadataSource,
            reviewPublicationCoordinator: reviewPublicationCoordinator,
            reviewContentLoaderCache: reviewContentLoaderCache,
            reviewSourceProvider: reviewSourceProvider
        )
    }

    private static func makeReviewSharedConstructionBinder(
        coordinator: BridgeWorktreeProductConstructionCoordinator,
        pipeline: BridgeReviewPipeline,
        provider: any BridgeReviewSourceProvider,
        repositoryPath: URL
    ) -> BridgePaneReviewSharedConstructionBinder? {
        guard provider is any BridgeSharedReviewConstructionSourceProvider else { return nil }
        return BridgePaneReviewSharedConstructionBinder(
            coordinator: coordinator,
            pipeline: pipeline,
            repositoryPath: repositoryPath
        )
    }

    @MainActor
    private static func makeRefreshAdmissionCoordinator(
        initialReviewTarget: WorkspaceReviewContributionTarget,
        repositoryDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity?
    ) -> BridgePaneRefreshAdmissionCoordinator {
        BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground,
            initialReviewComparison: BridgePaneReviewComparisonPresentation(
                activeTarget: initialReviewTarget,
                attempt: .pending(reviewGeneration: 0),
                displayedSnapshot: .absent,
                repositoryDefaultTarget: repositoryDefaultTarget
            )
        )
    }

    private static func makeProductProvider(
        dependencies: BridgeDevelopmentProductProviderDependencies
    ) -> BridgePaneProductSchemeProvider {
        let reviewContentSource = BridgePaneProductReviewContentSource(
            loaderCache: dependencies.reviewContentLoaderCache,
            acquireContentLease: { descriptor, productAdmission in
                dependencies.reviewPublicationCoordinator.acquireContentLease(
                    handleId: descriptor.descriptorId,
                    packageId: descriptor.packageId,
                    requestedGeneration: BridgeReviewGeneration(descriptor.reviewGeneration),
                    sourceIdentity: descriptor.sourceIdentity,
                    productAdmission: productAdmission
                )
            },
            settleContentLease: { lease in
                dependencies.reviewPublicationCoordinator.settleContentLease(lease)
            }
        )
        return BridgePaneProductSchemeProvider(
            annotationSource: dependencies.annotationSource,
            annotationOutputSource: dependencies.annotationOutputSource,
            annotationProjectionSource: dependencies.annotationProjectionSource,
            fileMetadataSource: dependencies.fileMetadataSource,
            reviewMetadataSource: dependencies.reviewMetadataSource,
            reviewContentSource: reviewContentSource,
            reviewPublicationReplay: { productAdmission in
                dependencies.reviewPublicationCoordinator.committedPublicationForReplay(
                    productAdmission: productAdmission
                )
            },
            isReviewPublicationCurrent: { publicationId, productAdmission in
                dependencies.reviewPublicationCoordinator.isCurrentPublication(
                    publicationId: publicationId,
                    productAdmission: productAdmission
                )
            },
            admitReviewPublicationInstallation: { request, correlation, productAdmission in
                dependencies.reviewPublicationCoordinator.admitDisplayInstallation(
                    expectedDisplayedPublicationId: request.expectedDisplayedPublicationId,
                    candidatePublicationId: request.candidatePublicationId,
                    workerInstanceId: correlation.workerInstanceId,
                    productAdmission: productAdmission
                )
            },
            recordReviewPublicationApplication: { publicationId, correlation, productAdmission in
                dependencies.reviewPublicationCoordinator.recordDisplayedApplication(
                    publicationId: publicationId,
                    workerInstanceId: correlation.workerInstanceId,
                    productAdmission: productAdmission
                )
            },
            markReviewItemViewed: { _, _ in },
            applyReviewComparisonUpdate: dependencies.applyReviewComparisonUpdate,
            applyFileRefreshRetry: dependencies.applyFileRefreshRetry,
            applyWorktreeAnnotationCommand: dependencies.applyWorktreeAnnotationCommand,
            authorizeReviewComparisonTargets:
                BridgePaneProductComparisonTargetQuerySource.makeAuthorization(
                    targetProjection: dependencies.reviewComparisonTargetProjection,
                    refreshWorkAdmissionSource: dependencies.refreshWorkAdmissionSource
                ),
            reviewComparisonTargetCatalogProducer: BridgeReviewComparisonTargetCatalogProducer(
                reviewSourceProvider: dependencies.reviewSourceProvider
            ),
            initialPanePresentation: dependencies.initialPresentation,
            refreshWorkAdmissionSource: dependencies.refreshWorkAdmissionSource
        )
    }

    private static func makeFileMetadataSource(
        source: BridgeDevelopmentProductSource,
        gitReadContext: BridgeGitReadContext,
        constructionCoordinator: BridgeWorktreeProductConstructionCoordinator
    ) -> BridgePaneProductFileMetadataSource {
        BridgePaneProductFileMetadataSource(
            authority: BridgePaneProductFileSourceAuthority(
                paneId: source.paneID,
                worktree: Worktree(
                    id: source.worktreeID,
                    repoId: source.repoID,
                    name: source.worktreeRoot.lastPathComponent,
                    path: source.worktreeRoot
                )
            ),
            gitReadContext: gitReadContext,
            constructionCoordinator: constructionCoordinator
        )
    }

    static func makeSchemeHandler(
        paneId: UUID,
        source: BridgeDevelopmentProductSource,
        productSessionOwner: BridgePaneProductSessionOwner
    ) -> BridgeSchemeHandler {
        BridgeSchemeHandler(
            paneId: paneId,
            appRootURL: source.worktreeRoot,
            telemetrySessionOwner: nil,
            productSessionRouter: productSessionOwner.schemeRouter
        )
    }
}
