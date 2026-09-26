import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation
import WebKit
import os.log

private let bridgeControllerLogger = Logger(subsystem: "com.agentstudio", category: "BridgePaneController")

/// Per-pane controller for bridge-backed panels (diff viewer, code review, etc.).
///
/// Each bridge pane gets its own `WebPage.Configuration` with:
/// - Non-persistent data store (no cookies/history needed for internal panels)
/// - `BridgeReadyMessageHandler` in a dedicated bridge content world for one-shot ready bootstrap
/// - Bootstrap `WKUserScript` injected at document start in the bridge world
/// - `BridgeSchemeHandler` registered for the `agentstudio://` custom URL scheme
///
/// The `bridge.ready` script-message handshake is bootstrap-only. File and Review
/// control and product data use the pane product session and its direct comm-worker streams.
///
/// Unlike `WebviewPaneController` which uses a shared static configuration,
/// `BridgePaneController` creates a **per-pane** configuration because each pane
/// needs its own `WKUserContentController` for message handlers and bootstrap scripts.
///
/// See bridge runtime architecture docs for handshake and lifecycle behavior.
@Observable
@MainActor
package final class BridgePaneController {

    private struct InitialPageComposition {
        let page: WebPage
        let userContentController: WKUserContentController
        let bootstrapScript: WKUserScript
        let readyMessageHandler: BridgeReadyMessageHandler
    }

    private struct InitialPageCompositionInput {
        let paneId: UUID
        let state: BridgePaneState
        let appRootURL: URL
        let telemetryScopeGate: BridgeTelemetryScopeGate
        let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
        let productSessionRouter: BridgeProductSchemeSessionRouter
        let bridgeWorld: WKContentWorld
        let managementScript: WKUserScript
        let viewerOpenTelemetryAnchor: BridgeViewerOpenTelemetryAnchor?
    }

    // MARK: - Public State

    package let paneId: UUID
    package let page: WebPage
    package let runtime: BridgeRuntime
    package var paneState: PaneDomainState { runtime.paneState }

    /// Whether the bridge handshake has completed.
    /// No bootstrap-gated commands are allowed before this becomes `true`.
    /// Gated and idempotent — once set, subsequent `bridge.ready` messages are ignored.
    private(set) var isBridgeReady = false

    // MARK: - Runtime Hooks

    var onRuntimeEvent: (@MainActor @Sendable (PaneRuntimeEvent, UUID?, UUID?) -> Void)?
    // MARK: - Domain State

    let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    var productAdmissionGate: BridgeProductAdmissionGate {
        productSessionOwner.productAdmissionGate
    }
    let refreshAdmissionCoordinator: BridgePaneRefreshAdmissionCoordinator
    let worktreeRefreshDriver: BridgePaneWorktreeRefreshDriver
    let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    package let productSessionOwner: BridgePaneProductSessionOwner
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSchemeProvider: BridgePaneProductSchemeProvider?
    let reviewPipeline: BridgeReviewPipeline
    let reviewSourceProvider: any BridgeReviewSourceProvider
    let reviewSharedConstructionBinder: BridgePaneReviewSharedConstructionBinder?
    let reviewComparisonTargetProjection: BridgeReviewComparisonTargetProjection
    let worktreeAnnotationStore: WorktreeAnnotationServiceActor?
    let reviewChangeIndex = BridgeChangeIndex()
    package let bridgePaneState: BridgePaneState
    /// The controller's Review input. Only its comparison changes in place;
    /// a different member replaces the controller.
    package var reviewBinding: BridgeReviewSourceBinding?
    /// The controller's Files input. Membership and opened documents change in
    /// place through the mounted collection; the WebView is never recreated.
    package internal(set) var filesBinding: BridgeFilesSourceBinding?
    let fileCollectionSource: BridgeFileCollectionSource?
    /// Serializes Files membership updates so a later binding always lands last.
    var filesSourceUpdateTail: Task<Void, Never>?
    /// The newest Files binding requested, applied or still queued.
    var latestRequestedFilesBinding: BridgeFilesSourceBinding?
    let fileGitReadScheduler: BridgeGitReadScheduler?
    let worktreeProductConstructionCoordinator: BridgeWorktreeProductConstructionCoordinator?
    let gitWorkingTreeStatusProvider: (any GitWorkingTreeStatusProvider)?
    let initialContributionTargetCommit: BridgeReviewComparisonCommit?
    let contributionTargetCommit: BridgeReviewComparisonCommit?
    var nextReviewGeneration: BridgeReviewGeneration = 0
    var pendingComparisonReviewGeneration: BridgeReviewGeneration?
    var reviewGitRefreshSeedHolder = BridgeReviewGitRefreshSeedHolder()
    var selectedReviewItemId: String?
    var activeReviewRefreshTask: Task<Void, Never>?
    var activeReviewRefreshTaskId: UUID?
    var retiringReviewRefreshTaskById: [UUID: Task<Void, Never>] = [:]
    var surfaceSelectionTransitionTail: Task<Bool, Never>?
    var pendingReviewPackageBuildReasons: Set<BridgeReviewPackageBuildReason> = []
    var activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
    var surfaceSelectionAuthority = BridgePaneSurfaceSelectionAuthority()
    /// Receives each displayed File selection mapped back to its document.
    package var onFilesSelectionDisplayed: (@MainActor (BridgeFilesDisplayedSelection) -> Void)?
    /// The one native Files activation still waiting for its displayed receipt.
    var pendingFileActivation: BridgePendingFileActivation?

    // MARK: - Private State

    let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    let productSessionBootstrapSink: BridgeProductSessionBootstrapSink
    let telemetrySessionBootstrapSink: BridgeTelemetrySessionBootstrapSink
    private let userContentController: WKUserContentController
    private let bootstrapScript: WKUserScript
    private var managementScript: WKUserScript
    private(set) var isContentInteractionEnabled: Bool
    private var interactionApplyTask: Task<Void, Never>?
    private var isTeardownStarted = false
    private var lifecycleRetirementTask: Task<Bool, Never>?
    var productSessionBootstrapTransitionTail: Task<Void, Never>?
    var hasPublishedProductSessionBootstrap = false
    var telemetrySessionBootstrapTransitionTail: Task<Void, Never>?
    var hasPublishedTelemetrySessionBootstrap = false
    private var teardownCleanupTask: Task<Void, Never>?
    let telemetryScopeGate: BridgeTelemetryScopeGate
    let telemetryRecorder: (any BridgePerformanceTraceRecording)?
    let traceContextFactory: BridgeTraceContextFactory
    var lastReviewPackageTraceContext: BridgeTraceContext?

    // MARK: - Init

    /// Create a bridge pane controller with per-pane WebPage configuration.
    ///
    /// - Parameters:
    ///   - paneId: Unique identifier for this pane instance.
    ///   - state: Bridge pane payload (panel kind).
    ///   - sourceConfiguration: Review and Files inputs derived from the receiver's navigation record.
    ///   - metadata: Optional runtime metadata override used by runtime registration paths.
    package init(
        paneId: UUID,
        state: BridgePaneState,
        sourceConfiguration: BridgePaneSourceConfiguration,
        appRootURL: URL,
        metadata: PaneMetadata? = nil,
        reviewSourceProvider: (any BridgeReviewSourceProvider)? = nil,
        gitReadContext: BridgeGitReadContext? = nil,
        fileGitReadScheduler: BridgeGitReadScheduler? = nil,
        worktreeProductConstructionCoordinator: BridgeWorktreeProductConstructionCoordinator? = nil,
        worktreeAnnotationStore: WorktreeAnnotationServiceActor? = nil,
        worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinatorActor? = nil,
        gitWorkingTreeStatusProvider: (any GitWorkingTreeStatusProvider)? = nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy = .live,
        telemetryScopeGate: BridgeTelemetryScopeGate? = nil,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil,
        traceContextFactory: BridgeTraceContextFactory = .live,
        viewerOpenTelemetryAnchor: BridgeViewerOpenTelemetryAnchor? = nil,
        initialPaneActivity: BridgePaneActivity,
        productSessionDependencies: BridgePaneProductSessionDependencies? = nil,
        telemetrySessionDependencies: BridgePaneTelemetrySessionDependencies? = nil,
        productSessionBootstrapSink: @escaping BridgeProductSessionBootstrapSink =
            BridgePaneController.dispatchProductSessionBootstrap,
        telemetrySessionBootstrapSink: @escaping BridgeTelemetrySessionBootstrapSink =
            BridgePaneController.dispatchTelemetrySessionBootstrap,
        initialContributionTargetCommit: BridgeReviewComparisonCommit? = nil,
        contributionTargetCommit: BridgeReviewComparisonCommit? = nil
    ) {
        (self.paneId, self.bridgePaneState, self.reviewBinding) = (paneId, state, sourceConfiguration.review)
        let reviewBinding = sourceConfiguration.review
        (self.filesBinding, self.latestRequestedFilesBinding) = (sourceConfiguration.files, sourceConfiguration.files)
        self.fileGitReadScheduler = fileGitReadScheduler ?? gitReadContext?.scheduler
        (self.worktreeProductConstructionCoordinator, self.gitWorkingTreeStatusProvider) =
            (worktreeProductConstructionCoordinator, gitWorkingTreeStatusProvider)
        let reviewComparisonTargetProjection = BridgeReviewComparisonTargetProjection(reviewBinding: reviewBinding)
        self.reviewComparisonTargetProjection = reviewComparisonTargetProjection
        let telemetryDependencies = Self.resolveTelemetryDependencies(
            traceRuntime: traceRuntime,
            telemetryRuntimePolicy: telemetryRuntimePolicy,
            telemetryScopeGate: telemetryScopeGate,
            telemetryRecorder: telemetryRecorder,
            telemetrySessionDependencies: telemetrySessionDependencies
        )
        self.telemetryScopeGate = telemetryDependencies.scopeGate
        self.telemetryRecorder = telemetryDependencies.recorder
        self.telemetrySessionOwner = telemetryDependencies.sessionDependencies?.owner
        (self.traceContextFactory, self.worktreeAnnotationStore) = (traceContextFactory, worktreeAnnotationStore)
        let resolvedReviewSourceProvider = reviewSourceProvider ?? BridgeUnavailableReviewSourceProvider()
        self.reviewSourceProvider = resolvedReviewSourceProvider
        (self.initialContributionTargetCommit, self.contributionTargetCommit) =
            (initialContributionTargetCommit, contributionTargetCommit)
        let resolvedReviewContentLoaderCache = Self.makeReviewContentLoaderCache(resolvedReviewSourceProvider)
        self.reviewContentLoaderCache = resolvedReviewContentLoaderCache
        let resolvedRefreshAdmissionCoordinator = Self.makeRefreshAdmissionCoordinator(
            reviewBinding,
            initialActivity: initialPaneActivity
        )
        self.refreshAdmissionCoordinator = resolvedRefreshAdmissionCoordinator
        let resolvedReviewPublicationCoordinator = BridgeReviewPublicationCoordinator()
        self.reviewPublicationCoordinator = resolvedReviewPublicationCoordinator
        let reviewDependencies = Self.makeReviewDependencies(
            provider: resolvedReviewSourceProvider,
            coordinator: worktreeProductConstructionCoordinator,
            reviewBinding: reviewBinding
        )
        (self.reviewPipeline, self.reviewSharedConstructionBinder) = (
            reviewDependencies.pipeline, reviewDependencies.binder
        )
        let resolvedRuntime = Self.makeRuntime(paneId, for: state, overriding: metadata)
        self.runtime = resolvedRuntime
        let resolvedProductSessionDependencies =
            productSessionDependencies
            ?? Self.makeProductSessionDependencies(
                BridgeProductSessionDependencyInput(
                    paneSessionId: paneId.uuidString,
                    runtime: resolvedRuntime,
                    reviewBinding: reviewBinding,
                    filesBinding: sourceConfiguration.files,
                    gitReadContext: gitReadContext,
                    fileGitReadScheduler: fileGitReadScheduler ?? gitReadContext?.scheduler,
                    worktreeProductConstructionCoordinator: worktreeProductConstructionCoordinator,
                    worktreeAnnotationStore: worktreeAnnotationStore,
                    worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator,
                    gitWorkingTreeStatusProvider: gitWorkingTreeStatusProvider,
                    reviewContentLoaderCache: resolvedReviewContentLoaderCache,
                    reviewPublicationCoordinator: resolvedReviewPublicationCoordinator,
                    refreshWorkAdmissionSource: resolvedRefreshAdmissionCoordinator.workAdmissionSource,
                    initialProductPresentation: resolvedRefreshAdmissionCoordinator.productPresentationSnapshot,
                    telemetryRecorder: telemetryDependencies.recorder,
                    reviewSourceProvider: resolvedReviewSourceProvider,
                    reviewComparisonTargetProjection: reviewComparisonTargetProjection
                )
            )
        self.productSessionOwner = resolvedProductSessionDependencies.owner
        self.productSchemeProvider = resolvedProductSessionDependencies.productProvider
        self.fileCollectionSource = resolvedProductSessionDependencies.fileCollectionSource
        let refreshDriver = Self.makeWorktreeRefreshDriver(
            coordinator: resolvedRefreshAdmissionCoordinator,
            productSessionDependencies: resolvedProductSessionDependencies
        )
        self.worktreeRefreshDriver = refreshDriver
        resolvedProductSessionDependencies.fileSourceAcceptanceRelay?.bind { [weak refreshDriver] source in
            refreshDriver?.recordFileSourceAccepted(source)
        }
        let initialManagementScript = Self.makeInitialManagementScript()
        self.managementScript = initialManagementScript
        self.isContentInteractionEnabled = !atom(\.managementLayer).isActive
        let pageComposition = Self.makeInitialPageComposition(
            InitialPageCompositionInput(
                paneId: paneId,
                state: state,
                appRootURL: appRootURL,
                telemetryScopeGate: telemetryDependencies.scopeGate,
                telemetrySessionOwner: telemetryDependencies.sessionDependencies?.owner,
                productSessionRouter: resolvedProductSessionDependencies.owner.schemeRouter,
                bridgeWorld: bridgeWorld,
                managementScript: initialManagementScript,
                viewerOpenTelemetryAnchor: viewerOpenTelemetryAnchor
            )
        )
        self.userContentController = pageComposition.userContentController
        self.productSessionBootstrapSink = productSessionBootstrapSink
        self.telemetrySessionBootstrapSink = telemetrySessionBootstrapSink
        (self.bootstrapScript, self.page) = (pageComposition.bootstrapScript, pageComposition.page)

        finishRuntimeSetup(
            pageComposition.readyMessageHandler,
            resolvedProductSessionDependencies.committedCallTarget
        )
    }

    private static func makeInitialPageComposition(
        _ input: InitialPageCompositionInput
    ) -> InitialPageComposition {
        // Each bridge pane owns its handlers, bootstrap scripts, and scheme routing.
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let userContentController = configuration.userContentController
        let readyMessageHandler = registerReadyMessageHandler(
            in: userContentController,
            contentWorld: input.bridgeWorld
        )
        let bootstrapScript = makeBootstrapArtifacts(
            paneId: input.paneId,
            state: input.state,
            telemetryScopeGate: input.telemetryScopeGate,
            viewerOpenTelemetryAnchor: input.viewerOpenTelemetryAnchor,
            bridgeWorld: input.bridgeWorld
        ).script
        installInitialUserScripts(
            in: userContentController,
            bootstrapScript: bootstrapScript,
            managementScript: input.managementScript
        )
        registerAgentStudioSchemeHandler(
            in: &configuration,
            input: BridgeSchemeHandlerRegistrationInput(
                paneId: input.paneId,
                appRootURL: input.appRootURL,
                telemetrySessionOwner: input.telemetrySessionOwner,
                productSessionRouter: input.productSessionRouter
            )
        )
        return InitialPageComposition(
            page: WebPage(
                configuration: configuration,
                navigationDecider: BridgeNavigationDecider(),
                dialogPresenter: WebviewDialogHandler()
            ),
            userContentController: userContentController,
            bootstrapScript: bootstrapScript,
            readyMessageHandler: readyMessageHandler
        )
    }

    private static func makeWorktreeRefreshDriver(
        coordinator: BridgePaneRefreshAdmissionCoordinator,
        productSessionDependencies: BridgePaneProductSessionDependencies
    ) -> BridgePaneWorktreeRefreshDriver {
        let productProvider = productSessionDependencies.productProvider
        let productAdmissionGate = productSessionDependencies.owner.productAdmissionGate
        let publishFileChangeset =
            productProvider?.publishFileChangeset ?? rejectUnavailableBridgeFileChangeset
        let publishFileStatus =
            productProvider?.publishFileStatus ?? rejectUnavailableBridgeFileStatus
        return BridgePaneWorktreeRefreshDriver(
            coordinator: coordinator,
            acquireProductAdmission: {
                productAdmissionGate.acquire()
            },
            publishFileChangeset: publishFileChangeset,
            publishFileStatus: publishFileStatus,
            publishPresentation: { snapshot, traceContext in
                await productProvider?.publishPanePresentation(
                    snapshot,
                    traceContext: traceContext
                )
            },
            publishOperationLifecycle: { event in
                await productProvider?.recordOperationLifecycle(event)
            }
        )
    }

    private static func makeInitialManagementScript() -> WKUserScript {
        WebInteractionManagementScript.makeUserScript(
            blockInteraction: atom(\.managementLayer).isActive
        )
    }

    private func finishRuntimeSetup(
        _ readyMessageHandler: BridgeReadyMessageHandler,
        _ committedCallTarget: BridgePaneProductCommittedCallTarget?
    ) {
        configureReadyMessageHandler(readyMessageHandler)
        configureRuntimeCallbacks()
        committedCallTarget?.controller = self
    }

    private static func makeReviewDependencies(
        provider: any BridgeReviewSourceProvider,
        coordinator: BridgeWorktreeProductConstructionCoordinator?,
        reviewBinding: BridgeReviewSourceBinding?
    ) -> (
        pipeline: BridgeReviewPipeline,
        binder: BridgePaneReviewSharedConstructionBinder?
    ) {
        let pipeline = BridgeReviewPipeline(provider: provider)
        let binder = makeReviewSharedConstructionBinder(
            coordinator: coordinator,
            pipeline: pipeline,
            provider: provider,
            reviewBinding: reviewBinding
        )
        return (pipeline, binder)
    }

    private static func initialReviewComparisonPresentation(
        for reviewBinding: BridgeReviewSourceBinding?
    ) -> BridgePaneReviewComparisonPresentation? {
        guard let reviewBinding else { return nil }
        guard let baseline = reviewBinding.comparison else {
            return BridgePaneReviewComparisonPresentation(
                activeTarget: nil,
                attempt: .selectionRequired,
                displayedSnapshot: .absent
            )
        }
        guard let contributionTarget = baseline.contributionTarget else { return nil }
        return BridgePaneReviewComparisonPresentation(
            activeTarget: contributionTarget,
            attempt: .pending(reviewGeneration: 0),
            displayedSnapshot: .absent
        )
    }

    private static func makeRefreshAdmissionCoordinator(
        _ reviewBinding: BridgeReviewSourceBinding?,
        initialActivity: BridgePaneActivity
    ) -> BridgePaneRefreshAdmissionCoordinator {
        BridgePaneRefreshAdmissionCoordinator(
            initialActivity: initialActivity,
            initialReviewComparison: initialReviewComparisonPresentation(for: reviewBinding)
        )
    }

    private static func makeReviewContentLoaderCache(
        _ provider: any BridgeReviewSourceProvider
    ) -> BridgeReviewContentLoaderCache {
        BridgeReviewContentLoaderCache(provider: provider)
    }

    private func configureReadyMessageHandler(_ readyMessageHandler: BridgeReadyMessageHandler) {
        readyMessageHandler.onBootstrapRequest = { [weak self] bootstrapMessage in
            guard let self else { return }
            switch bootstrapMessage {
            case .ready(let requestId):
                if handleBridgeReady() || isBridgeReady {
                    await emitBridgeReadyAcknowledgement(id: requestId, result: nil, error: nil)
                } else {
                    await emitBridgeReadyAcknowledgement(
                        id: requestId,
                        result: nil,
                        error: (code: -32_000, message: "bridge.ready failed")
                    )
                }
            case .productSessionBootstrap(let requestId, let reason):
                await enqueueProductSessionBootstrapRequest(
                    requestId: requestId,
                    reason: reason
                )
            case .telemetrySessionBootstrap(let requestId, let reason):
                await enqueueTelemetrySessionBootstrapRequest(
                    requestId: requestId,
                    reason: reason
                )
            case .invalid(let id, let message):
                await emitBridgeReadyAcknowledgement(
                    id: id,
                    result: nil,
                    error: (code: -32_600, message: message)
                )
            }
        }

    }

    // MARK: - Content Interaction

    /// Called by the pane view when management layer toggles. Keeps both the currently
    /// loaded bridge page and future navigations in sync with interaction suppression.
    func setWebContentInteractionEnabled(_ enabled: Bool) {
        let didChange = enabled != isContentInteractionEnabled
        isContentInteractionEnabled = enabled

        if didChange {
            refreshPersistentScripts()
        }
        applyCurrentDocumentInteractionState()
    }

    private func refreshPersistentScripts() {
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(bootstrapScript)
        managementScript = WebInteractionManagementScript.makeUserScript(
            blockInteraction: !isContentInteractionEnabled
        )
        userContentController.addUserScript(managementScript)
    }

    private func applyCurrentDocumentInteractionState() {
        let script = WebInteractionManagementScript.makeRuntimeToggleSource(
            blockInteraction: !isContentInteractionEnabled
        )
        interactionApplyTask?.cancel()
        let page = self.page
        let shouldReapplyAfterLoad = page.isLoading

        interactionApplyTask = Task { @MainActor in
            do {
                _ = try await page.callJavaScript(script)
            } catch is CancellationError {
                return
            } catch {
                bridgeControllerLogger.debug(
                    "Failed to apply interaction script for pane \(self.paneId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }

            guard shouldReapplyAfterLoad else { return }

            let deadline = ContinuousClock.now + .seconds(2)
            while page.isLoading, ContinuousClock.now < deadline {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
            }

            if Task.isCancelled { return }
            do {
                _ = try await page.callJavaScript(script)
            } catch is CancellationError {
                return
            } catch {
                bridgeControllerLogger.debug(
                    "Failed to reapply interaction script for pane \(self.paneId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Lifecycle

    /// Load the bundled React application via the custom scheme.
    ///
    /// `page.isLoading == false` does not guarantee React has mounted.
    @discardableResult
    package func loadApp() -> some AsyncSequence<WebPage.NavigationEvent, any Error> {
        page.load(URL(string: "agentstudio://app/index.html"))
    }

    /// Reload the existing browser page without changing native source authority.
    package var canReloadWebView: Bool {
        !isTeardownStarted
    }

    @discardableResult
    package func reloadWebView() -> Bool {
        guard canReloadWebView else { return false }
        _ = page.reload()
        return true
    }

    /// Called when the pane is being removed or the controller is being deallocated.
    package func beginTeardown() -> Task<Bool, Never> {
        if let lifecycleRetirementTask {
            return lifecycleRetirementTask
        }
        var reviewRefreshCleanupTelemetryTask: Task<Void, Never>?
        if !isTeardownStarted {
            isTeardownStarted = true
            refreshAdmissionCoordinator.close()
            productAdmissionGate.close()
            surfaceSelectionAuthority.invalidate()
            settlePendingFileActivation(.cancelled)
            let reviewPublicationCloseDrain = reviewPublicationCoordinator.close()
            let reviewPublicationCleanupSnapshot = reviewPublicationCoordinator.diagnosticSnapshot
            reviewRefreshCleanupTelemetryTask = makeReviewRefreshCleanupTelemetryTask(
                snapshot: reviewPublicationCleanupSnapshot
            )
            let reviewRefreshTasks =
                Array(retiringReviewRefreshTaskById.values)
                + [activeReviewRefreshTask].compactMap { $0 }
            for task in reviewRefreshTasks { task.cancel() }
            activeReviewRefreshTask = nil
            activeReviewRefreshTaskId = nil
            retiringReviewRefreshTaskById.removeAll()
            let reviewContentLoaderCache = reviewContentLoaderCache
            let productSchemeProvider = productSchemeProvider
            let surfaceSelectionTransitionTail = surfaceSelectionTransitionTail
            let worktreeRefreshDriver = worktreeRefreshDriver
            teardownCleanupTask = Task {
                await worktreeRefreshDriver.closeAndDrain()
                _ = await surfaceSelectionTransitionTail?.value
                async let contentDemandDrain: Void? = productSchemeProvider?.closeAndDrain()
                await reviewContentLoaderCache.closeAndDrain()
                _ = await contentDemandDrain
                async let closePublicationDrain: Void = reviewPublicationCloseDrain.releaseAndWait()
                for task in reviewRefreshTasks { await task.value }
                let lateArtifactPinReleaseTask = reviewPublicationCoordinator.takeArtifactPinReleaseTask()
                await closePublicationDrain
                await lateArtifactPinReleaseTask?.value
            }
            runtime.resetForControllerTeardown()
            isBridgeReady = false
            activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
            pendingReviewPackageBuildReasons.removeAll()
            reviewGitRefreshSeedHolder.retire()
            // Fence in-flight review jobs synchronously before asynchronous retirement.
            nextReviewGeneration = nextReviewGeneration.next()
        }

        guard let teardownCleanupTask else {
            preconditionFailure("Bridge teardown cleanup task was not installed")
        }
        let productSessionOwner = productSessionOwner
        let lifecycleRetirementTask = Task { @MainActor [weak self] in
            await reviewRefreshCleanupTelemetryTask?.value
            if let telemetrySessionOwner = self?.telemetrySessionOwner {
                do {
                    let terminalDrain = try await self?.drainTelemetrySidecar(closeAfterDrain: true)
                    guard
                        terminalDrain?.kind == .report,
                        let telemetrySessionId = terminalDrain?.telemetrySessionId,
                        let sidecarReport = terminalDrain?.sidecar,
                        sidecarReport.type == .drained
                    else {
                        throw BridgeTelemetrySidecarControlError.invalidResponse
                    }
                    let native = await telemetrySessionOwner.snapshot
                    let report = BridgeTelemetryProofReport.drain(
                        telemetrySessionId: telemetrySessionId,
                        sidecar: sidecarReport,
                        expectedSettlementDisposition: .closed,
                        native: native
                    )
                    try await self?.recordTelemetrySidecarProof(
                        report: report,
                        phase: .terminalClosed,
                        expectedSettlementDisposition: .closed
                    )
                    if !report.proofEligible {
                        await telemetrySessionOwner.markProofFailure()
                    }
                } catch {
                    await telemetrySessionOwner.markProofFailure()
                }
                await telemetrySessionOwner.revoke()
            }
            self?.page.stopLoading()
            let productSessionRetired = await productSessionOwner.retire(reason: .paneDisposal) == .retired
            await teardownCleanupTask.value
            if !productSessionRetired {
                self?.lifecycleRetirementTask = nil
            }
            return productSessionRetired
        }
        self.lifecycleRetirementTask = lifecycleRetirementTask
        return lifecycleRetirementTask
    }

    private static func retainedReviewPublicationCount(
        _ snapshot: BridgeReviewPublicationStateSnapshot
    ) -> Int {
        Set(
            [snapshot.active, snapshot.acknowledgedDisplayed, snapshot.admitted, snapshot.pending]
                .compactMap(\.self)
                .map(\.publicationId)
                + snapshot.retiring.map(\.publicationId)
        ).count
    }

    private func makeReviewRefreshCleanupTelemetryTask(
        snapshot: BridgeReviewPublicationStateSnapshot
    ) -> Task<Void, Never> {
        let recorder = telemetryRecorder.map(
            BridgeReviewRefreshLifecycleTraceRecorder.init(recorder:)
        )
        let retainedPublicationCount = Self.retainedReviewPublicationCount(snapshot)
        return Task {
            await recorder?.record(
                BridgeReviewRefreshLifecycleTraceEvent(
                    phase: .sourceCleanupTerminal,
                    resultReason: .close,
                    presentationClass: nil,
                    reviewGeneration: nil,
                    importedCommitCount: nil,
                    affectedFileCount: nil,
                    changedLineCount: nil,
                    affectedStableFileCount: nil,
                    retainedPublicationCount: retainedPublicationCount,
                    sourceLeaseCount: snapshot.activeContentLeaseCount,
                    durationMilliseconds: nil,
                    traceContext: nil
                )
            )
        }
    }

    // MARK: - Bridge Handshake

    /// Handle the `bridge.ready` message from the bridge world.
    ///
    /// This is gated and idempotent:
    /// - First call sets `isBridgeReady = true`.
    /// - Subsequent calls are silently ignored.
    ///
    /// `internal` (not `private`) for testability — allows integration tests to
    /// invoke the handshake directly without routing through WebKit message handlers.
    @discardableResult
    func handleBridgeReady() -> Bool {
        guard !isTeardownStarted else { return false }
        guard !isBridgeReady else { return false }
        if runtime.lifecycle == .created {
            guard runtime.transitionToReady() else {
                bridgeControllerLogger.error(
                    "Bridge ready handshake failed runtime transition for pane \(self.paneId.uuidString, privacy: .public)"
                )
                return false
            }
        } else if runtime.lifecycle != .ready {
            bridgeControllerLogger.error(
                """
                Bridge ready handshake rejected for pane \(self.paneId.uuidString, privacy: .public): \
                runtime lifecycle \(String(describing: self.runtime.lifecycle), privacy: .public)
                """
            )
            return false
        }
        isBridgeReady = true

        return true
    }

    func recordReviewIntakeReadyTelemetry(phase: String) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .webKit,
                name: "performance.bridge.webkit.review_intake_ready",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": phase,
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.control.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.warm.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.reviewMetadata.rawValue,
                    "agentstudio.bridge.transport": "product_control",
                ],
                numericAttributes: [:],
                booleanAttributes: [
                    "agentstudio.bridge.header_supported": isBridgeReady
                ]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    /// Runtime-facing typed event ingress for bridge domain events.
    func ingestRuntimeEvent(
        _ event: PaneRuntimeEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        onRuntimeEvent?(event, commandId, correlationId)
    }

    private func emitBridgeReadyAcknowledgement(
        id: String?,
        result: Any?,
        error: (code: Int, message: String)?
    ) async {
        guard
            let responseJSON = Self.makeBridgeReadyAcknowledgementJSON(
                id: id,
                result: result,
                error: error
            )
        else {
            bridgeControllerLogger.warning("[Bridge] ready acknowledgement encoding failed")
            paneState.connection.setHealth(.error)
            return
        }
        do {
            try await page.callJavaScript(
                """
                document.dispatchEvent(new CustomEvent('__bridge_ready_ack', {
                    detail: JSON.parse(json)
                }));
                """,
                arguments: ["json": responseJSON],
                contentWorld: bridgeWorld
            )
        } catch {
            bridgeControllerLogger.warning("[Bridge] ready acknowledgement transport failed: \(error)")
            paneState.connection.setHealth(.error)
        }
    }

    private nonisolated static func makeBridgeReadyAcknowledgementJSON(
        id: String?,
        result: Any?,
        error: (code: Int, message: String)?
    ) -> String? {
        var envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
        ]
        if let error {
            envelope["error"] = [
                "code": error.code,
                "message": error.message,
            ]
        } else {
            envelope["result"] = result ?? NSNull()
        }
        guard JSONSerialization.isValidJSONObject(envelope),
            let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func makeDefaultRuntimeMetadata(
        paneId: PaneId,
        state: BridgePaneState
    ) -> PaneMetadata {
        let contentType = contentType(for: state)
        let title: String
        switch state.panelKind {
        case .diffViewer:
            title = "Diff"
        case .fileViewer:
            title = "Files"
        }

        return PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            title: title
        )
    }

    private static func makeRuntime(
        _ paneId: UUID,
        for state: BridgePaneState,
        overriding metadata: PaneMetadata?
    ) -> BridgeRuntime {
        let runtimePaneId = PaneId(existingUUID: paneId)
        let defaultMetadata = makeDefaultRuntimeMetadata(paneId: runtimePaneId, state: state)
        let resolvedMetadata = (metadata ?? defaultMetadata).canonicalizedIdentity(
            paneId: runtimePaneId,
            contentType: contentType(for: state)
        )
        return BridgeRuntime(
            paneId: runtimePaneId,
            metadata: resolvedMetadata
        )
    }

    private static func contentType(for state: BridgePaneState) -> PaneContentType {
        switch state.panelKind {
        case .diffViewer, .fileViewer:
            return .diff
        }
    }

}

private func rejectUnavailableBridgeFileChangeset(
    _: FileChangeset,
    _: BridgeProductAdmissionContext,
    _: BridgePaneRefreshWorkAdmission,
    _: String,
    _: Int
) async -> BridgePaneProductFileRefreshPublicationDisposition {
    .notRequired
}

private func rejectUnavailableBridgeFileStatus(
    _: GitWorkingTreeStatus,
    _: BridgeProductAdmissionContext,
    _: BridgePaneRefreshWorkAdmission,
    _: String,
    _: Int
) async -> BridgePaneProductFileRefreshPublicationDisposition {
    .notRequired
}

extension BridgePaneController {
    var bootstrapScriptSourceForTesting: String { bootstrapScript.source }
}
