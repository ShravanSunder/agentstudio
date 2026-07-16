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
/// The controller owns the scheme-command dispatcher used by scheme RPC. The `bridge.ready`
/// handshake is bootstrap-only; ordinary File and Review product data uses the pane product
/// session and its direct comm-worker streams.
///
/// Unlike `WebviewPaneController` which uses a shared static configuration,
/// `BridgePaneController` creates a **per-pane** configuration because each pane
/// needs its own `WKUserContentController` for message handlers and bootstrap scripts.
///
/// See bridge runtime architecture docs for handshake and lifecycle behavior.
@Observable
@MainActor
final class BridgePaneController {

    // MARK: - Public State

    let paneId: UUID
    let page: WebPage
    let runtime: BridgeRuntime
    var paneState: PaneDomainState { runtime.paneState }

    /// Whether the bridge handshake has completed.
    /// No bootstrap-gated commands are allowed before this becomes `true`.
    /// Gated and idempotent — once set, subsequent `bridge.ready` messages are ignored.
    private(set) var isBridgeReady = false

    // MARK: - Runtime Hooks

    var onRuntimeEvent: (@MainActor @Sendable (PaneRuntimeEvent, UUID?, UUID?) -> Void)?
    var onRuntimeCommandAck: (@MainActor @Sendable (CommandAck) -> Void)?

    // MARK: - Domain State

    let revisionClock = RevisionClock()
    let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
    let reviewContentStore: BridgeContentStore
    let productSessionOwner: BridgePaneProductSessionOwner
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSchemeProvider: BridgePaneProductSchemeProvider?
    let reviewPipeline: BridgeReviewPipeline
    let reviewChangeIndex = BridgeChangeIndex()
    let bridgePaneState: BridgePaneState
    var nextReviewGeneration: BridgeReviewGeneration = 0
    let worktreeFileMetadataScheduler = BridgeMetadataLaneScheduler()
    var selectedReviewItemId: String?
    var activeReviewRefreshTask: Task<Void, Never>?
    var hasPendingReviewRefresh = false
    var pendingReviewPackageBuildReasons: Set<BridgeReviewPackageBuildReason> = []
    var reviewContentAuthorityLifetime = 0
    var nextReviewProtocolSequence = 0
    var activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
    var reviewProtocolSuppressedDrop: BridgeSuppressedProtocolDrop?

    // MARK: - Push Plans

    private var diffPushPlan: PushPlan<DiffState>?
    private var reviewPushPlan: PushPlan<ReviewState>?
    private var connectionPushPlan: PushPlan<PaneDomainState>?
    private var agentPushPlan: PushPlan<PaneDomainState>?

    // MARK: - Private State

    let schemeCommandDispatcher: BridgeSchemeCommandDispatcher
    let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    let pushNonce: String
    let productSessionBootstrapSink: BridgeProductSessionBootstrapSink
    let telemetrySessionBootstrapSink: BridgeTelemetrySessionBootstrapSink
    let pushEnvelopeSink: @MainActor (WebPage, String, String) async throws -> Void
    let intakeFrameSink: @MainActor (WebPage, PreEncodedIntakeFrame) async throws -> Void
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
    var bridgeDeliveryTail: Task<Void, Never>?
    private var inboxPostTimestamps: [Date] = []
    let telemetryScopeGate: BridgeTelemetryScopeGate
    let telemetryRecorder: (any BridgePerformanceTraceRecording)?
    let traceContextFactory: BridgeTraceContextFactory
    var lastReviewPackageTraceContext: BridgeTraceContext?

    /// Per store+op dedup cache. Bounded at O(StoreKey × PushOp) — currently 8 entries max.
    /// Each entry stores the epoch it was pushed in + the payload bytes. Dedup only matches
    /// within the same epoch — a new epoch always goes through even with identical bytes.
    /// This avoids cross-store thrash that a global epoch tracker would cause (connection
    /// uses epoch=0, diff uses diff.epoch, etc.)
    var lastPushed: [String: BridgePushDedupEntry] = [:]

    // MARK: - Init

    /// Create a bridge pane controller with per-pane WebPage configuration.
    ///
    /// - Parameters:
    ///   - paneId: Unique identifier for this pane instance.
    ///   - state: Serializable bridge pane state (panel kind + source).
    ///   - metadata: Optional runtime metadata override used by runtime registration paths.
    init(
        paneId: UUID,
        state: BridgePaneState,
        metadata: PaneMetadata? = nil,
        reviewSourceProvider: (any BridgeReviewSourceProvider)? = nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy = .live,
        telemetryScopeGate: BridgeTelemetryScopeGate? = nil,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil,
        traceContextFactory: BridgeTraceContextFactory = .live,
        productSessionDependencies: BridgePaneProductSessionDependencies? = nil,
        telemetrySessionDependencies: BridgePaneTelemetrySessionDependencies? = nil,
        productSessionBootstrapSink: @escaping BridgeProductSessionBootstrapSink =
            BridgePaneController.dispatchProductSessionBootstrap,
        telemetrySessionBootstrapSink: @escaping BridgeTelemetrySessionBootstrapSink =
            BridgePaneController.dispatchTelemetrySessionBootstrap,
        pushEnvelopeSink: @escaping @MainActor (WebPage, String, String) async throws -> Void =
            BridgePaneController.dispatchPushEnvelope,
        preEncodedIntakeFrameSink: @escaping @MainActor (WebPage, PreEncodedIntakeFrame) async throws -> Void =
            BridgePaneController.dispatchIntakeFrame,
        intakeFrameSink rawIntakeFrameSink: (@MainActor (WebPage, String, String) async throws -> Void)? = nil
    ) {
        self.paneId = paneId
        self.bridgePaneState = state
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
        self.traceContextFactory = traceContextFactory
        let resolvedReviewSourceProvider = reviewSourceProvider ?? BridgeUnavailableReviewSourceProvider()
        let resolvedReviewContentStore = BridgeContentStore(provider: resolvedReviewSourceProvider)
        self.reviewContentStore = resolvedReviewContentStore
        self.reviewPipeline = BridgeReviewPipeline(provider: resolvedReviewSourceProvider)
        let runtimePaneId = PaneId(uuid: paneId)
        let defaultMetadata = Self.makeDefaultRuntimeMetadata(paneId: runtimePaneId, state: state)
        let resolvedMetadata = (metadata ?? defaultMetadata).canonicalizedIdentity(
            paneId: runtimePaneId,
            contentType: Self.contentType(for: state)
        )
        let resolvedRuntime = BridgeRuntime(
            paneId: runtimePaneId,
            metadata: resolvedMetadata
        )
        self.runtime = resolvedRuntime
        let resolvedProductSessionDependencies =
            productSessionDependencies
            ?? Self.makeProductSessionDependencies(
                paneSessionId: paneId.uuidString,
                runtime: resolvedRuntime,
                state: state,
                reviewContentStore: resolvedReviewContentStore,
                telemetryRecorder: telemetryDependencies.recorder
            )
        self.productSessionOwner = resolvedProductSessionDependencies.owner
        self.productSchemeProvider = resolvedProductSessionDependencies.productProvider
        let blockInteraction = atom(\.managementLayer).isActive
        let initialManagementScript = WebInteractionManagementScript.makeUserScript(
            blockInteraction: blockInteraction
        )
        self.managementScript = initialManagementScript
        self.isContentInteractionEnabled = !blockInteraction

        // Per-pane configuration — NOT shared (unlike WebviewPaneController.sharedConfiguration).
        // Each bridge pane needs its own userContentController for ready bootstrap and script
        // registration, and its own urlSchemeHandlers for the agentstudio:// scheme.
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        self.userContentController = config.userContentController

        // Register only the bridge.ready bootstrap handler in the bridge content world.
        // Ordinary browser/native RPC uses the agentstudio://rpc/command scheme route.
        let readyMessageHandler = BridgeReadyMessageHandler()
        userContentController.add(
            readyMessageHandler,
            contentWorld: bridgeWorld,
            name: "rpc"
        )

        let bootstrapArtifacts = Self.makeBootstrapArtifacts(
            paneId: paneId,
            state: bridgePaneState,
            telemetryScopeGate: telemetryDependencies.scopeGate,
            bridgeWorld: bridgeWorld
        )
        self.pushNonce = bootstrapArtifacts.pushNonce
        self.productSessionBootstrapSink = productSessionBootstrapSink
        self.telemetrySessionBootstrapSink = telemetrySessionBootstrapSink
        self.pushEnvelopeSink = pushEnvelopeSink
        self.intakeFrameSink = Self.resolveIntakeFrameSink(
            preEncodedIntakeFrameSink: preEncodedIntakeFrameSink,
            rawIntakeFrameSink: rawIntakeFrameSink
        )
        self.bootstrapScript = bootstrapArtifacts.script
        Self.installInitialUserScripts(
            in: userContentController,
            bootstrapScript: bootstrapArtifacts.script,
            managementScript: initialManagementScript
        )

        Self.registerAgentStudioSchemeHandler(
            in: &config,
            input: BridgeSchemeHandlerRegistrationInput(
                paneId: paneId,
                reviewContentStore: reviewContentStore,
                resourceLeaseRegistry: resourceLeaseRegistry,
                telemetryRecorder: telemetryDependencies.recorder,
                telemetrySessionOwner: telemetryDependencies.sessionDependencies?.owner,
                productSessionOwner: resolvedProductSessionDependencies.owner,
                productSessionRouter: resolvedProductSessionDependencies.owner.schemeRouter
            )
        )

        // Create WebPage with bridge-specific navigation and dialog policies.
        self.page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        self.schemeCommandDispatcher = BridgeSchemeCommandDispatcher()
        configureSchemeCommandDispatcher(
            schemeCommandDispatcher,
            readyMessageHandler: readyMessageHandler,
            telemetryRecorder: telemetryDependencies.recorder
        )
        configureRuntimeCallbacks()
        registerNamespaceHandlers()
        resolvedProductSessionDependencies.committedCallTarget?.controller = self
    }

    private func configureSchemeCommandDispatcher(
        _ dispatcher: BridgeSchemeCommandDispatcher,
        readyMessageHandler: BridgeReadyMessageHandler,
        telemetryRecorder: (any BridgePerformanceTraceRecording)?
    ) {
        dispatcher.telemetryRecorder = telemetryRecorder

        // Log all RPC errors (parse errors, unknown methods, batch rejection, handler failures).
        // All error codes are reported through this single callback.
        dispatcher.onError = { code, message, id in
            bridgeControllerLogger.warning(
                "[BridgePaneController] RPC error code=\(code) msg=\(message) id=\(String(describing: id))"
            )
        }

        dispatcher.onCommandAck = { [weak self] ack in
            self?.handleRuntimeCommandAck(ack)
        }
        dispatcher.onSuccessResponseDelivered = { [weak self] method in
            await self?.handleRPCSuccessResponseDelivered(method: method)
        }

        // Wire the one-shot ready handler directly. All other browser/native RPC uses scheme fetch.
        readyMessageHandler.onBootstrapRequest = { [weak self] bootstrapMessage in
            guard let self else { return }
            switch bootstrapMessage {
            case .ready(let requestId):
                if handleBridgeReady() {
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

        // Register bridge.ready handler — the ONLY trigger for starting push plans.
        // The closure is @Sendable and async — awaits the @MainActor-isolated handleBridgeReady.
        dispatcher.register(method: BridgeReadyMethod.self) { [weak self] _ in
            self?.handleBridgeReady()
            return nil
        }
        dispatcher.register(method: BridgeIntakeReadyMethod.self) { [weak self] params in
            let result =
                await self?.handleBridgeIntakeReadyResult(params)
                ?? .rejected("bridge.intake_ready.controller_missing")
            switch result {
            case .accepted:
                return nil
            case .rejected(let reason):
                throw RPCMethodDispatchError.invalidParams(reason)
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

    /// Register stub handlers for command namespaces until behavior wiring is fully implemented.
    ///
    /// Keeps non-`bridge.ready` production command names discoverable and avoids `-32601`:
    /// diff.*, review.*, agent.*, and system.*. Each stub logs at `.info` level so calls
    /// are observable (prevents silent false-positive acks from hiding wiring gaps).
    private func registerNamespaceHandlers() {
        // diff namespace
        schemeCommandDispatcher.register(method: DiffMethods.LoadDiffMethod.self) { @MainActor [weak self] params in
            try await self?.handleLoadDiffRPC(params)
            return nil
        }
        // review namespace
        registerStub(ReviewMethods.AddCommentMethod.self)
        registerStub(ReviewMethods.ResolveThreadMethod.self)
        registerStub(ReviewMethods.UnresolveThreadMethod.self)
        registerStub(ReviewMethods.DeleteCommentMethod.self)
        typealias MarkFileViewed = ReviewMethods.MarkFileViewedMethod
        schemeCommandDispatcher.register(method: MarkFileViewed.self) { @MainActor [weak self] params in
            self?.paneState.review.markFileViewed(params.fileId)
            return nil
        }
        typealias UnmarkFileViewed = ReviewMethods.UnmarkFileViewedMethod
        schemeCommandDispatcher.register(method: UnmarkFileViewed.self) { @MainActor [weak self] params in
            self?.paneState.review.unmarkFileViewed(params.fileId)
            return nil
        }
        typealias MetadataInterestUpdate = ReviewMethods.MetadataInterestUpdateMethod
        schemeCommandDispatcher.register(method: MetadataInterestUpdate.self) { @MainActor [weak self] params in
            guard let self else { return nil }
            try await self.handleReviewMetadataInterestUpdate(params)
            return nil
        }

        // agent namespace
        registerStub(AgentMethods.RequestRewriteMethod.self)
        registerStub(AgentMethods.CancelTaskMethod.self)
        registerStub(AgentMethods.InjectPromptMethod.self)

        // inbox namespace
        schemeCommandDispatcher.register(method: InboxMethods.PostMethod.self) { @MainActor [weak self] params in
            guard let self else { return nil }
            let sanitizedParams = try self.sanitizeInboxPostParams(params)
            // Pane identity comes from this controller, not RPC params, so web content cannot spoof another pane.
            self.ingestRuntimeEvent(
                .agentNotificationRequested(title: sanitizedParams.title, body: sanitizedParams.body)
            )
            return nil
        }

        // system namespace
        registerStub(SystemMethods.HealthMethod.self)
        registerStub(SystemMethods.CapabilitiesMethod.self)
        registerStub(SystemMethods.ResyncAgentEventsMethod.self)
    }

    /// Register a no-op stub handler that logs when called.
    /// Prevents -32601 for known methods while behavior wiring is pending.
    private func registerStub<M: RPCMethod>(_ method: M.Type) {
        schemeCommandDispatcher.register(method: method) { _ in
            bridgeControllerLogger.info("[BridgePaneController] stub: \(M.method) called (not yet wired)")
            throw BridgeMethodUnimplementedError(method: M.method)
        }
    }

    private func handleLoadDiffRPC(_ params: DiffMethods.LoadDiffMethod.Params) async throws {
        let commandId = UUID()
        let result = await handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: params.diffId ?? UUIDv7.generate(),
                    worktreeId: params.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: commandId,
            correlationId: nil
        )

        switch result {
        case .success, .queued:
            return
        case .failure(let error):
            throw rpcDispatchError(from: error)
        }
    }

    private func rpcDispatchError(from error: ActionError) -> RPCMethodDispatchError {
        switch error {
        case .invalidPayload(let description):
            return .invalidParams(description)
        case .backendUnavailable(let backend):
            return .handlerFailure("Backend unavailable: \(backend)")
        case .runtimeNotReady(let lifecycle):
            return .handlerFailure("Runtime not ready: \(lifecycle)")
        case .unsupportedCommand(let command, let required):
            return .handlerFailure("Unsupported command \(command); requires \(required)")
        case .timeout(let commandId):
            return .handlerFailure("Command timed out: \(commandId.uuidString)")
        }
    }

    private func sanitizeInboxPostParams(
        _ params: InboxMethods.PostMethod.Params
    ) throws -> InboxMethods.PostMethod.Params {
        let now = Date()
        let windowStart = now.addingTimeInterval(-AppPolicies.InboxNotification.rpcPostRateLimitWindowSeconds)
        inboxPostTimestamps.removeAll { $0 < windowStart }
        guard inboxPostTimestamps.count < AppPolicies.InboxNotification.maxRPCPostsPerWindow else {
            throw RPCMethodDispatchError.invalidParams("inbox.post rate limit exceeded")
        }

        let title = params.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw RPCMethodDispatchError.invalidParams("inbox.post title is required")
        }
        inboxPostTimestamps.append(now)

        let trimmedBody = params.body?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmedBody?.isEmpty == true ? nil : trimmedBody
        let boundedText = InboxNotificationTextPolicy.bounded(title: title, body: body)

        return .init(
            title: boundedText.title,
            body: boundedText.body
        )
    }

    // MARK: - Lifecycle

    /// Load the bundled React application via the custom scheme.
    ///
    /// Push plans do NOT start here — they start when `bridge.ready` is received.
    /// `page.isLoading == false` does not guarantee React has mounted and listeners
    /// are attached.
    func loadApp() {
        guard let appURL = URL(string: "agentstudio://app/index.html") else { return }
        _ = page.load(appURL)
    }

    /// Tear down all active push plans and reset bridge state.
    ///
    /// Called when the pane is being removed or the controller is being deallocated.
    @discardableResult
    func teardown() -> Task<Bool, Never> {
        if let lifecycleRetirementTask {
            return lifecycleRetirementTask
        }
        if !isTeardownStarted {
            isTeardownStarted = true
            diffPushPlan?.stop()
            reviewPushPlan?.stop()
            connectionPushPlan?.stop()
            agentPushPlan?.stop()
            activeReviewRefreshTask?.cancel()
            diffPushPlan = nil
            reviewPushPlan = nil
            connectionPushPlan = nil
            agentPushPlan = nil
            activeReviewRefreshTask = nil
            hasPendingReviewRefresh = false
            revokeReviewContentAuthoritySynchronously()
            let reviewContentStore = reviewContentStore
            let resourceLeaseRegistry = resourceLeaseRegistry
            let paneId = paneId
            let worktreeFileMetadataScheduler = worktreeFileMetadataScheduler
            teardownCleanupTask = Task {
                await worktreeFileMetadataScheduler.closeGate(protocolId: "review")
                await reviewContentStore.deactivate()
                await resourceLeaseRegistry.reset(
                    paneId: paneId,
                    protocolId: "review",
                    resourceKind: "content",
                    revokeAuthority: false
                )
            }
            runtime.resetForControllerTeardown()
            bridgeDeliveryTail = nil
            lastPushed.removeAll()
            isBridgeReady = false
            nextReviewProtocolSequence = 0
            activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
            reviewProtocolSuppressedDrop = nil
            pendingReviewPackageBuildReasons.removeAll()
            // Fence in-flight review jobs synchronously before the asynchronous gate close.
            nextReviewGeneration = nextReviewGeneration.next()
        }

        guard let teardownCleanupTask else {
            preconditionFailure("Bridge teardown cleanup task was not installed")
        }
        let productSessionOwner = productSessionOwner
        let lifecycleRetirementTask = Task { @MainActor [weak self] in
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
            let productSessionRetired =
                await productSessionOwner.retire(reason: .paneDisposal) == .retired
            await teardownCleanupTask.value
            if !productSessionRetired {
                self?.lifecycleRetirementTask = nil
            }
            return productSessionRetired
        }
        self.lifecycleRetirementTask = lifecycleRetirementTask
        return lifecycleRetirementTask
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
        guard !isBridgeReady else { return true }
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

    func handleBridgeIntakeReady(_ params: BridgeIntakeReadyMethod.Params) async {
        _ = await handleBridgeIntakeReadyResult(params)
    }

    func handleBridgeIntakeReadyResult(_ params: BridgeIntakeReadyMethod.Params) async -> BridgeIntakeReadyResult {
        switch params.protocolId {
        case "review":
            return await handleReviewIntakeReady(params)
        default:
            await recordReviewIntakeReadyTelemetry(phase: "dropped")
            return .rejected("bridge.intake_ready.unsupported_protocol")
        }
    }

    private func handleReviewIntakeReady(_ params: BridgeIntakeReadyMethod.Params) async -> BridgeIntakeReadyResult {
        let currentStreamId = reviewProtocolStreamId()
        guard params.streamId == nil || params.streamId == currentStreamId else {
            bridgeControllerLogger.warning(
                """
                Bridge intake ready ignored for pane \(self.paneId.uuidString, privacy: .public): \
                stream \(String(describing: params.streamId), privacy: .public) does not match \(currentStreamId, privacy: .public)
                """
            )
            await recordReviewIntakeReadyTelemetry(phase: "dropped")
            return .rejected("review.intake_ready.stale_stream")
        }
        await recordReviewIntakeReadyTelemetry(phase: "accepted")
        if let package = paneState.diff.packageMetadata {
            await setActiveViewerModeAcceptedSignalForExplicitReviewRequest(
                streamId: currentStreamId,
                generation: package.reviewGeneration.rawValue
            )
        } else {
            clearActiveViewerModeAcceptedSignalForExplicitReviewRequest()
        }
        // The review viewer announces intake-ready when its surface mounts or
        // when an active surface has no applied snapshot. An announce is the
        // browser declaring "I have no usable review state": a cold pane
        // bootstraps, and a loaded pane RE-DELIVERS as a fresh generation —
        // only a higher-generation reset can re-key a receiver that dropped
        // frames while inactive or is stuck in resetRequired after a gap.
        // Both paths dedup on the single review refresh task.
        if paneState.diff.packageMetadata == nil {
            scheduleInitialReviewPackageLoadIfPossible(reason: .initialIntake)
        } else if params.reason == "sequence_gap" {
            scheduleReviewPackageReloadForIntakeAnnounce(reason: .intakeReannounce)
        }
        return .accepted
    }

    // MARK: - Test/entrypoint utility

    /// Entry point for valid command payloads.
    ///
    /// Separated for tests and command-handler reuse.
    @discardableResult
    func dispatchIncomingSchemeCommand(_ json: String) async -> String? {
        if let rejection = Self.schemeRPCBootstrapOnlyRejection(for: json) {
            bridgeControllerLogger.warning(
                "[BridgePaneController] rejected bridge.ready over scheme RPC for pane \(self.paneId.uuidString, privacy: .public)"
            )
            return rejection.responseJSON
        }
        return await schemeCommandDispatcher.dispatchSchemeCommand(json: json, isBridgeReady: isBridgeReady)
    }

    private func handleRPCSuccessResponseDelivered(method: String) async {
        _ = method
    }

    private func recordReviewIntakeReadyTelemetry(phase: String) async {
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
                    "agentstudio.bridge.transport": "intake",
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

    private static func contentType(for state: BridgePaneState) -> PaneContentType {
        switch state.panelKind {
        case .diffViewer, .fileViewer:
            return .diff
        }
    }

    private static func dispatchPushEnvelope(
        page: WebPage,
        envelopeString: String,
        _: String
    ) async throws {
        let envelopeLiteral = try makeJavaScriptStringLiteral(envelopeString)
        try await page.callJavaScript(
            """
            window.__bridgeInternal.applyEnvelopeJSON(\(envelopeLiteral));
            """,
            contentWorld: WKContentWorld.world(name: "agentStudioBridge")
        )
    }

    private static func dispatchIntakeFrame(
        page: WebPage,
        frame: PreEncodedIntakeFrame
    ) async throws {
        try await page.callJavaScript(
            """
            document.dispatchEvent(new CustomEvent('__bridge_intake_json', {
                detail: { json: \(frame.frameJavaScriptLiteral), nonce: \(frame.pushNonceJavaScriptLiteral) }
            }));
            """,
            contentWorld: .page
        )
    }

    private static func makeJavaScriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw BridgeError.encoding("Unable to encode push envelope as JavaScript string literal")
        }
        return literal
    }

}

extension BridgePaneController {
    var bootstrapScriptSourceForTesting: String { bootstrapScript.source }
}
