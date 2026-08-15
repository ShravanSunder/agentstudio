import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import WebKit

package actor BridgeDevelopmentProductHost {
    struct FileNavigationPublication: Equatable {
        let bindingRevision: Int
        let source: BridgeProductFileSourceIdentity
    }

    private struct ProductProviderDependencies {
        let applyReviewComparisonUpdate:
            @MainActor @Sendable (
                BridgeProductReviewComparisonUpdateRequest,
                BridgeProductAdmissionContext
            ) async -> Void
        let fileMetadataSource: BridgePaneProductFileMetadataSource
        let initialPresentation: BridgePaneProductPresentationSnapshot
        let refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
        let reviewContentLoaderCache: BridgeReviewContentLoaderCache
        let reviewMetadataSource: BridgePaneProductReviewMetadataSource
        let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
        let reviewSourceProvider: any BridgeReviewSourceProvider
        let reviewComparisonTargetProjection: BridgeReviewComparisonTargetProjection
    }

    private let constructionCoordinator: BridgeWorktreeProductConstructionCoordinator
    let contributionTargetCommit:
        @MainActor @Sendable (WorkspaceReviewContributionTarget) -> BridgePaneStateMutationResult
    private let committedCallTarget: BridgeDevelopmentProductCommittedCallTarget
    var activeReviewComparisonTask: Task<Void, Never>?
    var activeReviewComparisonTaskGeneration: BridgeReviewGeneration?
    private var bootstrapTransitionTail: Task<Void, Never>?
    private let gitReadScheduler: BridgeGitReadScheduler
    private var navigationBindingRevision = 0
    private var navigationIntent: BridgeDevelopmentProductBootstrapRequest.NavigationIntent?
    private let paneSessionId: String
    let productAdmission: BridgeProductAdmissionContext
    let productAdmissionGate: BridgeProductAdmissionGate
    let productProvider: BridgePaneProductSchemeProvider
    private let productSessionOwner: BridgePaneProductSessionOwner
    let refreshAdmissionCoordinator: BridgePaneRefreshAdmissionCoordinator
    private let repoId: UUID
    private let reviewedSubjectLabel: String?
    private let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    var paneState: BridgePaneState
    private let reviewPipeline: BridgeReviewPipeline
    let reviewProvider: any BridgeReviewSourceProvider
    let reviewComparisonTargetProjection: BridgeReviewComparisonTargetProjection
    let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    private let reviewSharedConstructionBinder: BridgePaneReviewSharedConstructionBinder?
    private let schemeHandler: BridgeSchemeHandler
    var isShutdown = false
    var nextReviewGeneration: BridgeReviewGeneration = 1
    private var publishedFileNavigation: FileNavigationPublication?
    private let worktreeId: UUID

    package init(
        source: BridgeDevelopmentProductSource,
        contributionTargetCommit:
            @escaping @MainActor @Sendable (WorkspaceReviewContributionTarget) ->
            BridgePaneStateMutationResult
    ) async throws {
        try await self.init(
            source: source,
            contributionTargetCommit: contributionTargetCommit,
            makeReviewProvider: { repositoryPath, gitReadContext in
                BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repositoryPath,
                    gitReadContext: gitReadContext
                )
            }
        )
    }

    package init(
        source: BridgeDevelopmentProductSource,
        contributionTargetCommit:
            @escaping @MainActor @Sendable (WorkspaceReviewContributionTarget) ->
            BridgePaneStateMutationResult,
        makeReviewProvider: @Sendable (URL, BridgeGitReadContext) -> any BridgeReviewSourceProvider
    ) async throws {
        let source = try Self.validatedFilesystemSource(source)
        let paneId = source.paneID
        let repoId = source.repoID
        let gitReadScheduler = BridgeGitReadScheduler(topology: .recoveryBaseline)
        let gitReadContext = BridgeGitReadContext(
            scheduler: gitReadScheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(source.worktreeRoot)),
            scopeKey: BridgeGitReadScopeKey(token: paneId.uuidString)
        )
        let reviewProvider = makeReviewProvider(source.worktreeRoot, gitReadContext)
        let reviewInitialization = try await Self.makeReviewInitialization(
            state: source.paneState,
            provider: reviewProvider
        )

        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let reviewSharedConstructionBinder = Self.makeReviewSharedConstructionBinder(
            coordinator: constructionCoordinator,
            pipeline: reviewInitialization.pipeline,
            provider: reviewProvider,
            repositoryPath: source.worktreeRoot
        )
        let fileMetadataSource = Self.makeFileMetadataSource(
            source: source,
            gitReadContext: gitReadContext,
            constructionCoordinator: constructionCoordinator
        )
        let reviewMetadataSource = BridgePaneProductReviewMetadataSource()
        let reviewContentLoaderCache = BridgeReviewContentLoaderCache(provider: reviewProvider)
        let reviewPublicationCoordinator = await MainActor.run {
            BridgeReviewPublicationCoordinator()
        }
        let committedCallTarget = await MainActor.run {
            BridgeDevelopmentProductCommittedCallTarget()
        }
        let refreshAdmissionCoordinator = await Self.makeRefreshAdmissionCoordinator(
            initialReviewTarget: reviewInitialization.initialTarget,
            repositoryDefaultTarget: reviewInitialization.defaultTarget
        )
        let refreshWorkAdmissionSource = await MainActor.run {
            refreshAdmissionCoordinator.workAdmissionSource
        }
        let initialPresentation = await refreshAdmissionCoordinator.productPresentationSnapshot
        let providerDependencies = ProductProviderDependencies(
            applyReviewComparisonUpdate: { request, productAdmission in
                await committedCallTarget.applyReviewComparisonUpdate(
                    request,
                    productAdmission: productAdmission
                )
            },
            fileMetadataSource: fileMetadataSource,
            initialPresentation: initialPresentation,
            refreshWorkAdmissionSource: refreshWorkAdmissionSource,
            reviewContentLoaderCache: reviewContentLoaderCache,
            reviewMetadataSource: reviewMetadataSource,
            reviewPublicationCoordinator: reviewPublicationCoordinator,
            reviewSourceProvider: reviewProvider,
            reviewComparisonTargetProjection: reviewInitialization.comparisonTargetProjection
        )
        let productProvider = Self.makeProductProvider(
            dependencies: providerDependencies
        )
        let productAdmissionGate = BridgeProductAdmissionGate()
        guard let productAdmission = productAdmissionGate.acquire() else {
            throw BridgeDevelopmentProductHostError.shutdown
        }
        let productSessionOwner = try BridgePaneProductSessionOwner(
            paneSessionId: paneId.uuidString,
            provider: productProvider,
            productAdmissionGate: productAdmissionGate
        )

        self.constructionCoordinator = constructionCoordinator
        self.contributionTargetCommit = contributionTargetCommit
        self.committedCallTarget = committedCallTarget
        self.gitReadScheduler = gitReadScheduler
        self.paneSessionId = paneId.uuidString
        self.productAdmission = productAdmission
        self.productAdmissionGate = productAdmissionGate
        self.productProvider = productProvider
        self.productSessionOwner = productSessionOwner
        self.refreshAdmissionCoordinator = refreshAdmissionCoordinator
        self.repoId = repoId
        self.reviewedSubjectLabel = source.reviewedSubjectLabel
        self.reviewContentLoaderCache = reviewContentLoaderCache
        self.paneState = source.paneState
        self.reviewPipeline = reviewInitialization.pipeline
        self.reviewProvider = reviewProvider
        self.reviewComparisonTargetProjection = reviewInitialization.comparisonTargetProjection
        self.reviewPublicationCoordinator = reviewPublicationCoordinator
        self.reviewSharedConstructionBinder = reviewSharedConstructionBinder
        self.schemeHandler = Self.makeSchemeHandler(
            paneId: paneId,
            source: source,
            productSessionOwner: productSessionOwner
        )
        self.worktreeId = source.worktreeID
        await connectProductCallbacks(
            committedCallTarget: committedCallTarget,
            fileMetadataSource: fileMetadataSource
        )
    }

    package func issueBootstrap(
        for request: BridgeDevelopmentProductBootstrapRequest
    ) async throws -> Data {
        guard !isShutdown else { throw BridgeDevelopmentProductHostError.shutdown }
        let precedingTransition = bootstrapTransitionTail
        let transition = Task { [weak self] () throws -> Data in
            if let precedingTransition {
                await precedingTransition.value
            }
            try Task.checkCancellation()
            guard let self else { throw BridgeDevelopmentProductHostError.shutdown }
            return try await self.performBootstrapTransition(for: request)
        }
        bootstrapTransitionTail = Task {
            _ = try? await transition.value
        }
        return try await withTaskCancellationHandler {
            try await transition.value
        } onCancel: {
            transition.cancel()
        }
    }

    private func performBootstrapTransition(
        for request: BridgeDevelopmentProductBootstrapRequest
    ) async throws -> Data {
        guard !isShutdown else { throw BridgeDevelopmentProductHostError.shutdown }
        try validateBootstrapTransition(request)
        let candidate = try await productSessionOwner.prepareCandidate(
            productAdmission: productAdmission
        )
        guard
            await productSessionOwner.activatePreparedCandidate(
                candidate,
                productAdmission: productAdmission
            ) == .activated
        else {
            throw BridgeDevelopmentProductHostError.sessionActivationFailed
        }
        let reviewPublication = try await prepareReviewPublicationIfNeeded(
            for: request.navigationIntent
        )
        navigationIntent = request.navigationIntent
        navigationBindingRevision += 1
        await publishNavigation(
            request.navigationIntent,
            bindingRevision: navigationBindingRevision,
            bootstrap: candidate.bootstrap,
            reviewPublication: reviewPublication
        )
        return try BridgeDevelopmentProductBootstrapEnvelope.encode(candidate)
    }

    package func route(
        _ request: URLRequest
    ) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        schemeHandler.reply(for: request)
    }

    package func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true
        let transitionTail = bootstrapTransitionTail
        await transitionTail?.value
        bootstrapTransitionTail = nil
        let reviewComparisonTask = activeReviewComparisonTask
        reviewComparisonTask?.cancel()
        await reviewComparisonTask?.value
        activeReviewComparisonTask = nil
        activeReviewComparisonTaskGeneration = nil
        await MainActor.run {
            refreshAdmissionCoordinator.close()
            productAdmissionGate.close()
        }
        let publicationDrain = await MainActor.run {
            reviewPublicationCoordinator.close()
        }
        _ = await productSessionOwner.retire(reason: .paneDisposal)
        async let providerDrain: Void = productProvider.closeAndDrain()
        await reviewContentLoaderCache.closeAndDrain()
        await providerDrain
        await publicationDrain.releaseAndWait()
        await constructionCoordinator.shutdown()
        await gitReadScheduler.shutdown()
    }

    private func validateBootstrapTransition(
        _ request: BridgeDevelopmentProductBootstrapRequest
    ) throws {
        switch request.reason {
        case .initial:
            break
        case .workerReplacement:
            guard request.paneSessionId == paneSessionId else {
                throw BridgeDevelopmentProductHostError.replacementPaneNotFound
            }
            guard request.navigationIntent == navigationIntent else {
                throw BridgeDevelopmentProductHostError.replacementNavigationChanged
            }
        }
    }

    private func publishNavigation(
        _ navigationIntent: BridgeDevelopmentProductBootstrapRequest.NavigationIntent,
        bindingRevision: Int,
        bootstrap: BridgeProductSessionBootstrap,
        reviewPublication: BridgeReviewCommittedPublication?
    ) async {
        let navigationCommand: BridgeProductNavigationCommand
        switch navigationIntent {
        case .activateContext(let commandId, let surface):
            navigationCommand = .activateContext(
                commandId: commandId,
                bindingRevision: bindingRevision,
                surface: surface
            )
        case .activateFileTarget:
            return
        case .activateReviewTarget:
            guard let reviewPublication,
                let reviewCommand = Self.bindReviewNavigationCommand(
                    intent: navigationIntent,
                    publication: reviewPublication,
                    bindingRevision: bindingRevision
                )
            else { return }
            navigationCommand = reviewCommand
        }
        let request = BridgePaneSurfaceSelectionRequest(
            navigationCommand: navigationCommand,
            paneSessionId: bootstrap.paneSessionId,
            workerInstanceId: bootstrap.workerInstanceId
        )
        _ = await productProvider.publishPaneSurfaceSelectionRequest(
            request,
            productAdmission: productAdmission,
            streamAbsenceDisposition: .retainForReplay
        )
    }

    private func publishFileNavigationIfNeeded(
        _ source: BridgeProductFileSourceIdentity
    ) async {
        guard
            let bindingRevision = Self.nextFileNavigationBindingRevision(
                currentBindingRevision: navigationBindingRevision,
                previouslyPublishedBindingRevision: publishedFileNavigation?.bindingRevision,
                previouslyPublishedSource: publishedFileNavigation?.source,
                acceptedSource: source
            )
        else { return }
        guard !isShutdown,
            let navigationIntent,
            let navigationCommand = Self.bindFileNavigationCommand(
                intent: navigationIntent,
                source: source,
                bindingRevision: bindingRevision
            ),
            let bootstrap = await productSessionOwner.activeBootstrap()
        else { return }
        let request = BridgePaneSurfaceSelectionRequest(
            navigationCommand: navigationCommand,
            paneSessionId: bootstrap.paneSessionId,
            workerInstanceId: bootstrap.workerInstanceId
        )
        guard
            await productProvider.publishPaneSurfaceSelectionRequest(
                request,
                productAdmission: productAdmission,
                streamAbsenceDisposition: .retainForReplay
            )
        else { return }
        navigationBindingRevision = Self.navigationBindingRevisionAfterFilePublish(
            currentBindingRevision: navigationBindingRevision,
            publishedRequestBindingRevision: bindingRevision
        )
        publishedFileNavigation = Self.fileNavigationPublicationAfterCommit(
            currentPublication: publishedFileNavigation,
            completedPublication: FileNavigationPublication(
                bindingRevision: bindingRevision,
                source: source
            )
        )
    }

    static func fileNavigationPublicationAfterCommit(
        currentPublication: FileNavigationPublication?,
        completedPublication: FileNavigationPublication
    ) -> FileNavigationPublication {
        guard let currentPublication,
            currentPublication.bindingRevision >= completedPublication.bindingRevision
        else {
            return completedPublication
        }
        return currentPublication
    }

    static func navigationBindingRevisionAfterFilePublish(
        currentBindingRevision: Int,
        publishedRequestBindingRevision: Int
    ) -> Int {
        max(currentBindingRevision, publishedRequestBindingRevision)
    }

    static func nextFileNavigationBindingRevision(
        currentBindingRevision: Int,
        previouslyPublishedBindingRevision: Int?,
        previouslyPublishedSource: BridgeProductFileSourceIdentity?,
        acceptedSource: BridgeProductFileSourceIdentity
    ) -> Int? {
        guard previouslyPublishedSource != acceptedSource else {
            guard previouslyPublishedBindingRevision != currentBindingRevision else { return nil }
            return currentBindingRevision
        }
        guard let previouslyPublishedBindingRevision else { return currentBindingRevision }
        return max(currentBindingRevision, previouslyPublishedBindingRevision + 1)
    }

    private func prepareReviewPublicationIfNeeded(
        for navigationIntent: BridgeDevelopmentProductBootstrapRequest.NavigationIntent
    ) async throws -> BridgeReviewCommittedPublication? {
        let requiresReviewPublication: Bool
        switch navigationIntent {
        case .activateContext(_, .review), .activateReviewTarget:
            requiresReviewPublication = true
        case .activateContext(_, .file), .activateFileTarget:
            requiresReviewPublication = false
        }
        guard requiresReviewPublication else { return nil }
        if let activePublication = await MainActor.run(body: {
            reviewPublicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        }) {
            return activePublication
        }

        let target = try Self.reviewTarget(from: paneState)
        let initialGeneration = nextReviewGeneration
        await MainActor.run {
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: target,
                reviewGeneration: initialGeneration.rawValue
            )
        }
        await publishCurrentPanePresentation()
        let preparedPublication: BridgeReviewPreparedPublication
        do {
            preparedPublication = try await constructReviewPublication(
                target: target,
                reviewGeneration: initialGeneration
            )
        } catch {
            await failReviewComparisonAttempt(initialGeneration, failureKind: "publication_failed")
            throw error
        }
        let committedPublication: BridgeReviewCommittedPublication? = await MainActor.run {
            () -> BridgeReviewCommittedPublication? in
            guard
                let token = reviewPublicationCoordinator.stage(
                    preparedPublication,
                    productAdmission: productAdmission
                )
            else { return nil }
            guard
                case .committed(let committedPublication) = reviewPublicationCoordinator.commit(
                    token,
                    productAdmission: productAdmission,
                    captureCommittedPresentation: { package in
                        refreshAdmissionCoordinator.settleReviewComparisonAttempt(
                            reviewGeneration: package.reviewGeneration.rawValue,
                            displayedSnapshotIdentity: BridgePaneReviewDisplayedSnapshotIdentity(
                                packageId: package.packageId,
                                reviewGeneration: package.reviewGeneration.rawValue,
                                revision: package.revision
                            )
                        )
                        return refreshAdmissionCoordinator.productPresentationSnapshot
                    },
                    presentCommitted: { _ in }
                )
            else {
                _ = reviewPublicationCoordinator.rejectReservation(
                    token,
                    productAdmission: productAdmission
                )
                return nil
            }
            return committedPublication
        }
        guard let committedPublication else {
            await failReviewComparisonAttempt(initialGeneration, failureKind: "publication_failed")
            throw BridgeDevelopmentProductHostError.reviewPublicationFailed
        }
        nextReviewGeneration = committedPublication.package.reviewGeneration
        await publishCurrentPanePresentation()
        return committedPublication
    }

    func constructReviewPublication(
        target: WorkspaceReviewContributionTarget,
        reviewGeneration: BridgeReviewGeneration
    ) async throws -> BridgeReviewPreparedPublication {
        let pipelineRequest = try await makeDevelopmentReviewPipelineRequest(
            generatedAt: Int64(Date().timeIntervalSince1970 * 1000),
            reviewGeneration: reviewGeneration,
            target: target
        )
        let constructionResult: BridgeReviewPackageConstructionResult
        if let reviewSharedConstructionBinder {
            let binding = try await reviewSharedConstructionBinder.acquire(pipelineRequest)
            constructionResult = BridgeReviewPackageConstructionResult(
                result: binding.result,
                artifactPin: binding.artifactPin
            )
        } else {
            constructionResult = BridgeReviewPackageConstructionResult(
                result: try await reviewPipeline.loadPackage(pipelineRequest),
                artifactPin: nil
            )
        }
        do {
            try Task.checkCancellation()
        } catch {
            await constructionResult.releaseArtifactPin()
            throw error
        }
        let result = constructionResult.result
        guard
            let preparedPublication = await BridgeReviewPreparedPublication.prepare(
                BridgeReviewPublicationCandidate(
                    package: result.package,
                    delta: nil,
                    contentHandles: result.registeredContentHandles,
                    artifactPin: constructionResult.artifactPin
                )
            )
        else {
            await constructionResult.releaseArtifactPin()
            throw BridgeDevelopmentProductHostError.reviewPublicationFailed
        }
        return preparedPublication
    }

    private func makeDevelopmentReviewPipelineRequest(
        generatedAt: Int64,
        reviewGeneration: BridgeReviewGeneration,
        target: WorkspaceReviewContributionTarget
    ) async throws -> BridgeReviewPipelineRequest {
        let baseEndpoint = BridgeSourceEndpoint(
            endpointId: "development-base",
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId,
            label: Self.label(for: target),
            createdAtUnixMilliseconds: generatedAt,
            contentSetHash: nil,
            providerIdentity: Self.label(for: target)
        )
        let headEndpoint = BridgeSourceEndpoint(
            endpointId: "development-working-tree",
            kind: .workingTree,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Working tree",
            createdAtUnixMilliseconds: generatedAt,
            contentSetHash: nil,
            providerIdentity: "working-tree:\(worktreeId.uuidString)"
        )
        let request = BridgeReviewPipelineRequest(
            packageId: "development-package-\(UUIDv7.generate().uuidString)",
            query: BridgeReviewQuery(
                queryId: "development-query-\(UUIDv7.generate().uuidString)",
                queryKind: .compare,
                repoId: repoId,
                worktreeId: worktreeId,
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId,
                comparisonSemantics: .workingTreeDelta,
                pathScope: [],
                fileTarget: nil,
                viewFilter: BridgeViewFilter(
                    showHiddenFiles: true,
                    showBinaryFiles: true,
                    showLargeFiles: true
                ),
                grouping: BridgeChangeGrouping(kind: .flat),
                provenanceFilter: BridgeProvenanceFilter()
            ),
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            checkpointIds: [],
            reviewGeneration: reviewGeneration,
            generatedAtUnixMilliseconds: generatedAt
        )
        let capture = try await reviewProvider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: target,
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                reviewGenerationValue: reviewGeneration.rawValue
            )
        )
        return try BridgeResolvedContributionRequestBuilder.build(
            request: request,
            symbolicTarget: target,
            capture: capture,
            reviewedSubjectLabel: reviewedSubjectLabel
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

    static func loadReviewComparisonDefaultTarget(
        from reviewProvider: any BridgeReviewSourceProvider
    ) async throws -> BridgeReviewComparisonDefaultTargetIdentity? {
        do {
            return try await reviewProvider.resolveReviewDefaultTarget()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
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

    static func bindReviewNavigationCommand(
        intent: BridgeDevelopmentProductBootstrapRequest.NavigationIntent,
        publication: BridgeReviewCommittedPublication,
        bindingRevision: Int
    ) -> BridgeProductNavigationCommand? {
        guard case .activateReviewTarget(let commandId, let target) = intent else {
            return nil
        }
        let package = publication.package
        return .activateReviewTarget(
            commandId: commandId,
            bindingRevision: bindingRevision,
            source: BridgeProductNavigationReviewSource(
                generation: package.reviewGeneration.rawValue,
                metadataSourceId: package.query.queryId,
                packageId: package.packageId
            ),
            target: target
        )
    }

    static func bindFileNavigationCommand(
        intent: BridgeDevelopmentProductBootstrapRequest.NavigationIntent,
        source: BridgeProductFileSourceIdentity,
        bindingRevision: Int
    ) -> BridgeProductNavigationCommand? {
        guard case .activateFileTarget(let commandId, let target) = intent else {
            return nil
        }
        return .activateFileTarget(
            commandId: commandId,
            bindingRevision: bindingRevision,
            source: BridgeProductNavigationFileSource(
                sourceId: source.sourceId,
                subscriptionGeneration: source.subscriptionGeneration
            ),
            target: target
        )
    }

    private static func makeProductProvider(
        dependencies: ProductProviderDependencies
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
            recordReviewPublicationApplication: { publicationId, productAdmission in
                dependencies.reviewPublicationCoordinator.recordWorkerApplication(
                    publicationId: publicationId,
                    productAdmission: productAdmission
                )
            },
            markReviewItemViewed: { _, _ in },
            applyReviewComparisonUpdate: dependencies.applyReviewComparisonUpdate,
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

    private static func makeSchemeHandler(
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

    private func connectProductCallbacks(
        committedCallTarget: BridgeDevelopmentProductCommittedCallTarget,
        fileMetadataSource: BridgePaneProductFileMetadataSource
    ) async {
        await MainActor.run {
            committedCallTarget.host = self
        }
        await fileMetadataSource.setSourceAcceptedObserver { [weak self] source in
            await self?.publishFileNavigationIfNeeded(source)
        }
    }

    private static func validatedFilesystemSource(
        _ source: BridgeDevelopmentProductSource
    ) throws -> BridgeDevelopmentProductSource {
        var isDirectory: ObjCBool = false
        let rootExists = FileManager.default.fileExists(
            atPath: source.worktreeRoot.path,
            isDirectory: &isDirectory
        )
        let gitAuthorityExists = FileManager.default.fileExists(
            atPath: source.worktreeRoot.appending(path: ".git").path
        )
        guard rootExists, isDirectory.boolValue, gitAuthorityExists else {
            throw BridgeDevelopmentProductHostError.invalidWorktree
        }
        guard case .workspace(let rootPath, let baseline)? = source.paneState.source else {
            throw BridgeDevelopmentProductHostError.invalidPaneSource
        }
        let restoredRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        guard restoredRoot.path == source.worktreeRoot.path,
            baseline?.contributionTarget != nil
        else {
            throw BridgeDevelopmentProductHostError.invalidPaneSource
        }
        return source
    }

    static func reviewTarget(
        from paneState: BridgePaneState
    ) throws -> WorkspaceReviewContributionTarget {
        guard case .workspace(_, let baseline)? = paneState.source,
            let reviewTarget = baseline?.contributionTarget
        else {
            throw BridgeDevelopmentProductHostError.invalidContributionTarget
        }
        return reviewTarget
    }

    private static func label(for target: WorkspaceReviewContributionTarget) -> String {
        switch target {
        case .localDefaultBranch(let branchName, _):
            branchName
        case .branch(let name, _):
            name
        case .originDefaultBranch(let remoteName, let branchName, _):
            "\(remoteName)/\(branchName)"
        case .commit(let oid):
            oid
        case .ref(let name, _):
            name
        }
    }
}

@MainActor
private final class BridgeDevelopmentProductCommittedCallTarget {
    weak var host: BridgeDevelopmentProductHost?

    func applyReviewComparisonUpdate(
        _ request: BridgeProductReviewComparisonUpdateRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        await host?.applyCommittedReviewComparisonUpdate(
            request,
            productAdmission: productAdmission
        )
    }
}
