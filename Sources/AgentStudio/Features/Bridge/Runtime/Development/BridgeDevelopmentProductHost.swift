import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import WebKit

package actor BridgeDevelopmentProductHost {
    struct FileNavigationPublication: Equatable {
        let bindingRevision: Int
        let source: BridgeProductFileSourceIdentity
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
    let worktreeRefreshDriver: BridgePaneWorktreeRefreshDriver
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
    private let worktreeRoot: URL

    package init(
        source: BridgeDevelopmentProductSource,
        worktreeAnnotationStore: WorktreeAnnotationServiceActor? = nil,
        worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor? = nil,
        originatingWorkspaceID: String? = nil,
        contributionTargetCommit:
            @escaping @MainActor @Sendable (WorkspaceReviewContributionTarget) ->
            BridgePaneStateMutationResult
    ) async throws {
        try await self.init(
            source: source,
            worktreeAnnotationStore: worktreeAnnotationStore,
            worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator,
            originatingWorkspaceID: originatingWorkspaceID,
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
        worktreeAnnotationStore: WorktreeAnnotationServiceActor? = nil,
        worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor? = nil,
        originatingWorkspaceID: String? = nil,
        reviewSharedContentRootURL: URL,
        contributionTargetCommit:
            @escaping @MainActor @Sendable (WorkspaceReviewContributionTarget) ->
            BridgePaneStateMutationResult
    ) async throws {
        try await self.init(
            source: source,
            worktreeAnnotationStore: worktreeAnnotationStore,
            worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator,
            originatingWorkspaceID: originatingWorkspaceID,
            contributionTargetCommit: contributionTargetCommit,
            makeReviewProvider: { repositoryPath, gitReadContext in
                BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repositoryPath,
                    gitReadContext: gitReadContext,
                    sharedContentRootURL: reviewSharedContentRootURL
                )
            }
        )
    }

    package init(
        source: BridgeDevelopmentProductSource,
        worktreeAnnotationStore: WorktreeAnnotationServiceActor? = nil,
        worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor? = nil,
        originatingWorkspaceID: String? = nil,
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

        let productPreparation = try await Self.makeProductProviderPreparation(
            .init(
                gitReadContext: gitReadContext,
                originatingWorkspaceID: originatingWorkspaceID,
                reviewInitialization: reviewInitialization,
                reviewProvider: reviewProvider,
                source: source,
                worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator,
                worktreeAnnotationStore: worktreeAnnotationStore
            )
        )

        self.constructionCoordinator = productPreparation.constructionCoordinator
        self.contributionTargetCommit = contributionTargetCommit
        self.committedCallTarget = productPreparation.committedCallTarget
        self.gitReadScheduler = gitReadScheduler
        self.paneSessionId = paneId.uuidString
        self.productAdmission = productPreparation.productAdmission
        self.productAdmissionGate = productPreparation.productAdmissionGate
        self.productProvider = productPreparation.productProvider
        self.productSessionOwner = productPreparation.productSessionOwner
        self.refreshAdmissionCoordinator = productPreparation.refreshAdmissionCoordinator
        let preparedProductProvider = productPreparation.productProvider
        let preparedProductAdmissionGate = productPreparation.productAdmissionGate
        self.worktreeRefreshDriver = await MainActor.run {
            BridgePaneWorktreeRefreshDriver(
                coordinator: productPreparation.refreshAdmissionCoordinator,
                acquireProductAdmission: {
                    preparedProductAdmissionGate.acquire()
                },
                publishFileChangeset: { changeset, productAdmission, foregroundWorkAdmission in
                    await preparedProductProvider.publishFileChangeset(
                        changeset,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission
                    )
                },
                publishFileStatus: { status, productAdmission, foregroundWorkAdmission in
                    await preparedProductProvider.publishFileStatus(
                        status,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission
                    )
                },
                publishPresentation: { snapshot, traceContext in
                    await preparedProductProvider.publishPanePresentation(
                        snapshot,
                        traceContext: traceContext
                    )
                }
            )
        }
        self.repoId = repoId
        self.reviewedSubjectLabel = source.reviewedSubjectLabel
        self.reviewContentLoaderCache = productPreparation.reviewContentLoaderCache
        self.paneState = source.paneState
        self.reviewPipeline = reviewInitialization.pipeline
        self.reviewProvider = reviewProvider
        self.reviewComparisonTargetProjection = reviewInitialization.comparisonTargetProjection
        self.reviewPublicationCoordinator = productPreparation.reviewPublicationCoordinator
        self.reviewSharedConstructionBinder = productPreparation.reviewSharedConstructionBinder
        self.schemeHandler = Self.makeSchemeHandler(
            paneId: paneId,
            source: source,
            productSessionOwner: productPreparation.productSessionOwner
        )
        self.worktreeId = source.worktreeID
        self.worktreeRoot = source.worktreeRoot
        await connectProductCallbacks(
            committedCallTarget: productPreparation.committedCallTarget,
            fileMetadataSource: productPreparation.fileMetadataSource
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

    package func handleObservedWorktreeInvalidation(
        _ invalidation: BridgePaneWorktreeProductInvalidation
    ) async {
        guard !isShutdown else { return }
        switch invalidation {
        case .filesChanged(let changeset):
            guard changeset.repoId == repoId,
                changeset.worktreeId == worktreeId,
                changeset.rootPath.standardizedFileURL.resolvingSymlinksInPath()
                    == worktreeRoot.standardizedFileURL.resolvingSymlinksInPath()
            else { return }
            _ = await constructionCoordinator.invalidate(
                worktree: worktreeConstructionIdentity
            )
            _ = await worktreeRefreshDriver.recordInvalidation(
                fileChangeset: changeset,
                requiresReviewRefresh: true
            )
        case .statusChanged(let status):
            _ = await constructionCoordinator.invalidate(
                worktree: worktreeConstructionIdentity
            )
            _ = await worktreeRefreshDriver.recordInvalidation(
                fileChangeset: nil,
                latestFileStatus: status,
                requiresReviewRefresh: true
            )
        }
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
        await worktreeRefreshDriver.closeAndDrain()
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

    private var worktreeConstructionIdentity: BridgeWorktreeIdentityKey {
        BridgeWorktreeIdentityKey(
            repoIdentity: repoId.uuidString,
            worktreeIdentity: worktreeId.uuidString,
            stableRootIdentity: StableKey.fromPath(worktreeRoot)
        )
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

    private func connectProductCallbacks(
        committedCallTarget: BridgeDevelopmentProductCommittedCallTarget,
        fileMetadataSource: BridgePaneProductFileMetadataSource
    ) async {
        await MainActor.run {
            committedCallTarget.host = self
        }
        await fileMetadataSource.setSourceAcceptedObserver { [weak self] source in
            await self?.recordAcceptedFileSource(source)
        }
    }

    private func recordAcceptedFileSource(
        _ source: BridgeProductFileSourceIdentity
    ) async {
        await worktreeRefreshDriver.recordFileSourceAccepted(source)
        await publishFileNavigationIfNeeded(source)
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
final class BridgeDevelopmentProductCommittedCallTarget {
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

    func applyFileRefreshRetry(productAdmission: BridgeProductAdmissionContext) async {
        guard (productAdmission.withValidAdmission { true }) == true else { return }
        await host?.retryUnavailableFileRefresh()
    }
}

extension BridgeDevelopmentProductHost {
    func retryUnavailableFileRefresh() async {
        guard !isShutdown else { return }
        await MainActor.run {
            worktreeRefreshDriver.retryUnavailableFileRefresh()
        }
    }
}
