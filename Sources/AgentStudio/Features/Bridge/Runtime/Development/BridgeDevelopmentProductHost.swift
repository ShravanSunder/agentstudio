import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import WebKit

package actor BridgeDevelopmentProductHost {
    private struct ProductProviderDependencies {
        let fileMetadataSource: BridgePaneProductFileMetadataSource
        let initialPresentation: BridgePaneProductPresentationSnapshot
        let refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
        let reviewContentLoaderCache: BridgeReviewContentLoaderCache
        let reviewMetadataSource: BridgePaneProductReviewMetadataSource
        let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    }

    private let constructionCoordinator: BridgeWorktreeProductConstructionCoordinator
    private var bootstrapTransitionTail: Task<Void, Never>?
    private let gitReadScheduler: BridgeGitReadScheduler
    private var navigationBindingRevision = 0
    private var navigationIntent: BridgeDevelopmentProductBootstrapRequest.NavigationIntent?
    private let paneSessionId: String
    private let productAdmission: BridgeProductAdmissionContext
    private let productAdmissionGate: BridgeProductAdmissionGate
    private let productProvider: BridgePaneProductSchemeProvider
    private let productSessionOwner: BridgePaneProductSessionOwner
    private let refreshAdmissionCoordinator: BridgePaneRefreshAdmissionCoordinator
    private let repoId: UUID
    private let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    private let reviewBase: String
    private let reviewPipeline: BridgeReviewPipeline
    private let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    private let reviewSharedConstructionBinder: BridgePaneReviewSharedConstructionBinder?
    private let schemeHandler: BridgeSchemeHandler
    private var isShutdown = false
    private var publishedFileNavigationBindingRevision: Int?
    private let worktreeId: UUID

    package init(source: BridgeDevelopmentProductSource) async throws {
        try await self.init(
            source: source,
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
        makeReviewProvider: @Sendable (URL, BridgeGitReadContext) -> any BridgeReviewSourceProvider
    ) async throws {
        let source = try Self.validatedFilesystemSource(source)
        let paneId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let paneSessionId = paneId.uuidString
        let gitReadScheduler = BridgeGitReadScheduler(topology: .recoveryBaseline)
        let gitReadContext = BridgeGitReadContext(
            scheduler: gitReadScheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(source.worktreeRoot)),
            scopeKey: BridgeGitReadScopeKey(token: paneSessionId)
        )
        let reviewProvider = makeReviewProvider(source.worktreeRoot, gitReadContext)
        let reviewPipeline = BridgeReviewPipeline(provider: reviewProvider)
        try await Self.validateReviewBase(
            source.reviewBase,
            provider: reviewProvider,
            repoId: repoId,
            worktreeId: worktreeId
        )

        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let reviewSharedConstructionBinder = Self.makeReviewSharedConstructionBinder(
            coordinator: constructionCoordinator,
            pipeline: reviewPipeline,
            provider: reviewProvider,
            repositoryPath: source.worktreeRoot
        )
        let fileMetadataSource = BridgePaneProductFileMetadataSource(
            authority: BridgePaneProductFileSourceAuthority(
                paneId: paneId,
                worktree: Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: source.worktreeRoot.lastPathComponent,
                    path: source.worktreeRoot
                )
            ),
            gitReadContext: gitReadContext,
            constructionCoordinator: constructionCoordinator
        )
        let reviewMetadataSource = BridgePaneProductReviewMetadataSource()
        let reviewContentLoaderCache = BridgeReviewContentLoaderCache(provider: reviewProvider)
        let reviewPublicationCoordinator = await MainActor.run {
            BridgeReviewPublicationCoordinator()
        }
        let refreshAdmissionCoordinator = await MainActor.run {
            BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        }
        let refreshWorkAdmissionSource = await MainActor.run {
            refreshAdmissionCoordinator.workAdmissionSource
        }
        let initialPresentation = await MainActor.run {
            refreshAdmissionCoordinator.productPresentationSnapshot
        }
        let providerDependencies = ProductProviderDependencies(
            fileMetadataSource: fileMetadataSource,
            initialPresentation: initialPresentation,
            refreshWorkAdmissionSource: refreshWorkAdmissionSource,
            reviewContentLoaderCache: reviewContentLoaderCache,
            reviewMetadataSource: reviewMetadataSource,
            reviewPublicationCoordinator: reviewPublicationCoordinator
        )
        let productProvider = Self.makeProductProvider(
            dependencies: providerDependencies
        )
        let productAdmissionGate = BridgeProductAdmissionGate()
        guard let productAdmission = productAdmissionGate.acquire() else {
            throw BridgeDevelopmentProductHostError.shutdown
        }
        let productSessionOwner = try BridgePaneProductSessionOwner(
            paneSessionId: paneSessionId,
            provider: productProvider,
            productAdmissionGate: productAdmissionGate
        )

        self.constructionCoordinator = constructionCoordinator
        self.gitReadScheduler = gitReadScheduler
        self.paneSessionId = paneSessionId
        self.productAdmission = productAdmission
        self.productAdmissionGate = productAdmissionGate
        self.productProvider = productProvider
        self.productSessionOwner = productSessionOwner
        self.refreshAdmissionCoordinator = refreshAdmissionCoordinator
        self.repoId = repoId
        self.reviewContentLoaderCache = reviewContentLoaderCache
        self.reviewBase = source.reviewBase
        self.reviewPipeline = reviewPipeline
        self.reviewPublicationCoordinator = reviewPublicationCoordinator
        self.reviewSharedConstructionBinder = reviewSharedConstructionBinder
        self.schemeHandler = BridgeSchemeHandler(
            paneId: paneId,
            appRootURL: source.worktreeRoot,
            telemetrySessionOwner: nil,
            productSessionRouter: productSessionOwner.schemeRouter
        )
        self.worktreeId = worktreeId
        await fileMetadataSource.setSourceAcceptedObserver { [weak self] source in
            await self?.publishFileNavigationIfNeeded(source)
        }
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
        let bindingRevision = navigationBindingRevision
        guard !isShutdown,
            publishedFileNavigationBindingRevision != bindingRevision,
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
        publishedFileNavigationBindingRevision = bindingRevision
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

        let pipelineRequest = makeDevelopmentReviewPipelineRequest(
            generatedAt: Int64(Date().timeIntervalSince1970 * 1000)
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
                    presentCommitted: { _ in }
                )
            else { return nil }
            return committedPublication
        }
        guard let committedPublication else {
            throw BridgeDevelopmentProductHostError.reviewPublicationFailed
        }
        return committedPublication
    }

    private func makeDevelopmentReviewPipelineRequest(
        generatedAt: Int64
    ) -> BridgeReviewPipelineRequest {
        let baseEndpoint = BridgeSourceEndpoint(
            endpointId: "development-base",
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId,
            label: reviewBase,
            createdAtUnixMilliseconds: generatedAt,
            contentSetHash: nil,
            providerIdentity: reviewBase
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
        return BridgeReviewPipelineRequest(
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
            reviewGeneration: 1,
            generatedAtUnixMilliseconds: generatedAt
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
            initialPanePresentation: dependencies.initialPresentation,
            refreshWorkAdmissionSource: dependencies.refreshWorkAdmissionSource
        )
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
        guard !source.reviewBase.isEmpty else {
            throw BridgeDevelopmentProductHostError.invalidReviewBase
        }
        return source
    }

    private static func validateReviewBase(
        _ reviewBase: String,
        provider: any BridgeReviewSourceProvider,
        repoId: UUID,
        worktreeId: UUID
    ) async throws {
        let endpoint = BridgeSourceEndpoint(
            endpointId: "development-review-base",
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId,
            label: reviewBase,
            createdAtUnixMilliseconds: 0,
            contentSetHash: nil,
            providerIdentity: reviewBase
        )
        do {
            _ = try await provider.resolveEndpoint(
                BridgeEndpointResolutionRequest(endpoint: endpoint)
            )
        } catch {
            throw BridgeDevelopmentProductHostError.invalidReviewBase
        }
    }
}
