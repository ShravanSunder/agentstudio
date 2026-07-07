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
/// The controller owns the `RPCRouter` used by scheme RPC. Push plans are started
/// only after the `bridge.ready` handshake completes.
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
    /// No state pushes or commands are allowed before this becomes `true`.
    /// Gated and idempotent — once set, subsequent `bridge.ready` messages are ignored.
    private(set) var isBridgeReady = false
    let schemeRPCDispatcher = BridgeSchemeRPCDispatcher()

    // MARK: - Runtime Hooks

    var onRuntimeEvent: (@MainActor @Sendable (PaneRuntimeEvent, UUID?, UUID?) -> Void)?
    var onRuntimeCommandAck: (@MainActor @Sendable (CommandAck) -> Void)?

    // MARK: - Domain State

    let revisionClock = RevisionClock()
    let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
    let reviewContentStore: BridgeContentStore
    let worktreeFileResourceStore = BridgeWorktreeFileResourceStore()
    let reviewPipeline: BridgeReviewPipeline
    let reviewChangeIndex = BridgeChangeIndex()
    let bridgePaneState: BridgePaneState
    var nextReviewGeneration: BridgeReviewGeneration = 0
    var nextWorktreeFileSurfaceGeneration = 0
    var activeWorktreeFileSurfaceSource: BridgeWorktreeFileSurfaceActiveSourceState?
    var activeWorktreeFileManifestIndex: BridgeWorktreeFileManifestIndex?
    let worktreeFileMetadataScheduler = BridgeMetadataLaneScheduler()
    var activeWorktreeFileTreeWindowTask: Task<Void, Never>?
    var selectedReviewItemId: String?
    var activeReviewRefreshTask: Task<Void, Never>?
    var hasPendingReviewRefresh = false
    var pendingReviewPackageBuildReasons: Set<BridgeReviewPackageBuildReason> = []
    var reviewContentAuthorityLifetime = 0
    var nextReviewProtocolSequence = 0
    var activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
    var reviewProtocolSuppressedDrop: BridgeSuppressedProtocolDrop?
    var worktreeFileSuppressedDrop: BridgeSuppressedProtocolDrop?

    // MARK: - Push Plans

    private var diffPushPlan: PushPlan<DiffState>?
    private var reviewPushPlan: PushPlan<ReviewState>?
    private var connectionPushPlan: PushPlan<PaneDomainState>?
    private var agentPushPlan: PushPlan<PaneDomainState>?

    // MARK: - Private State

    let router: RPCRouter
    private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    let pushNonce: String
    let pushEnvelopeSink: @MainActor (WebPage, String, String) async throws -> Void
    let intakeFrameSink: @MainActor (WebPage, PreEncodedIntakeFrame) async throws -> Void
    private let userContentController: WKUserContentController
    private let bootstrapScript: WKUserScript
    private var managementScript: WKUserScript
    private(set) var isContentInteractionEnabled: Bool
    private var interactionApplyTask: Task<Void, Never>?
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
        telemetryIngestor: (any BridgeTelemetryBatchIngesting)? = nil,
        traceContextFactory: BridgeTraceContextFactory = .live,
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
            telemetryIngestor: telemetryIngestor
        )
        let resolvedTelemetryScopeGate = telemetryDependencies.scopeGate
        let resolvedTelemetryRecorder = telemetryDependencies.recorder
        let resolvedTelemetryIngestor = telemetryDependencies.ingestor
        self.telemetryScopeGate = resolvedTelemetryScopeGate
        self.telemetryRecorder = resolvedTelemetryRecorder
        self.traceContextFactory = traceContextFactory
        let resolvedReviewSourceProvider = reviewSourceProvider ?? BridgeUnavailableReviewSourceProvider()
        self.reviewContentStore = BridgeContentStore(provider: resolvedReviewSourceProvider)
        self.reviewPipeline = BridgeReviewPipeline(provider: resolvedReviewSourceProvider)
        let runtimePaneId = PaneId(uuid: paneId)
        let defaultMetadata = Self.makeDefaultRuntimeMetadata(paneId: runtimePaneId, state: state)
        let resolvedMetadata = (metadata ?? defaultMetadata).canonicalizedIdentity(
            paneId: runtimePaneId,
            contentType: Self.contentType(for: state)
        )
        self.runtime = BridgeRuntime(
            paneId: runtimePaneId,
            metadata: resolvedMetadata
        )
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
            metadata: resolvedMetadata,
            state: bridgePaneState,
            telemetryScopeGate: resolvedTelemetryScopeGate,
            bridgeWorld: bridgeWorld
        )
        self.pushNonce = bootstrapArtifacts.pushNonce
        self.pushEnvelopeSink = pushEnvelopeSink
        if let rawIntakeFrameSink {
            self.intakeFrameSink = { page, frame in
                try await rawIntakeFrameSink(page, frame.envelopeJSON, frame.pushNonce)
            }
        } else {
            self.intakeFrameSink = preEncodedIntakeFrameSink
        }
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
                worktreeFileResourceStore: worktreeFileResourceStore,
                resourceLeaseRegistry: resourceLeaseRegistry,
                telemetryRecorder: resolvedTelemetryRecorder,
                rpcDispatcher: schemeRPCDispatcher
            )
        )

        // Create WebPage with bridge-specific navigation and dialog policies.
        self.page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        self.router = RPCRouter()
        configureRouter(
            router,
            readyMessageHandler: readyMessageHandler,
            telemetryRecorder: resolvedTelemetryRecorder,
            telemetryIngestor: resolvedTelemetryIngestor
        )
        schemeRPCDispatcher.handler = { [weak self] json in
            await self?.handleIncomingSchemeRPC(json)
        }

        onRuntimeEvent = { [weak self] event, commandId, correlationId in
            self?.runtime.ingestBridgeEvent(event, commandId: commandId, correlationId: correlationId)
        }
        onRuntimeCommandAck = { [weak self] ack in
            self?.runtime.recordCommandAck(ack)
        }
        runtime.commandHandler = self

        registerNamespaceHandlers()
    }

    private func configureRouter(
        _ router: RPCRouter,
        readyMessageHandler: BridgeReadyMessageHandler,
        telemetryRecorder: (any BridgePerformanceTraceRecording)?,
        telemetryIngestor: (any BridgeTelemetryBatchIngesting)?
    ) {
        router.telemetryRecorder = telemetryRecorder
        router.telemetryIngestor = telemetryIngestor

        // Log all RPC errors (parse errors, unknown methods, batch rejection, handler failures).
        // All error codes are reported through this single callback.
        router.onError = { code, message, id in
            bridgeControllerLogger.warning(
                "[BridgePaneController] RPC error code=\(code) msg=\(message) id=\(String(describing: id))"
            )
        }

        router.onCommandAck = { [weak self] ack in
            self?.handleRuntimeCommandAck(ack)
        }
        router.onSuccessResponseDelivered = { [weak self] method in
            await self?.handleRPCSuccessResponseDelivered(method: method)
        }

        // Wire the one-shot ready handler directly. All other browser/native RPC uses scheme fetch.
        readyMessageHandler.onReadyRequest = { [weak self] readyMessage in
            guard let self else { return }
            switch readyMessage {
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
        router.register(method: BridgeReadyMethod.self) { [weak self] _ in
            self?.handleBridgeReady()
            return nil
        }
        router.register(method: BridgeIntakeReadyMethod.self) { [weak self] params in
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
        router.register(method: BridgeActiveViewerModeUpdateMethod.self) { [weak self] params in
            await self?.handleBridgeActiveViewerModeUpdate(params)
            return nil
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
        router.register(method: DiffMethods.LoadDiffMethod.self) { @MainActor [weak self] params in
            try await self?.handleLoadDiffRPC(params)
            return nil
        }
        typealias OpenWorktreeFileSurface = WorktreeFileSurfaceMethods.OpenSourceStreamMethod
        router.register(method: OpenWorktreeFileSurface.self) { @MainActor [weak self] params in
            guard let self else { return nil }
            return try await self.handleWorktreeFileSurfaceOpenSourceStream(params)
        }
        typealias RequestWorktreeFileDescriptor = WorktreeFileSurfaceMethods.RequestFileDescriptorMethod
        router.register(method: RequestWorktreeFileDescriptor.self) { @MainActor [weak self] params in
            guard let self else { return nil }
            return try await self.handleWorktreeFileDescriptorRequest(params)
        }

        // review namespace
        registerStub(ReviewMethods.AddCommentMethod.self)
        registerStub(ReviewMethods.ResolveThreadMethod.self)
        registerStub(ReviewMethods.UnresolveThreadMethod.self)
        registerStub(ReviewMethods.DeleteCommentMethod.self)
        router.register(method: ReviewMethods.MarkFileViewedMethod.self) { @MainActor [weak self] params in
            self?.paneState.review.markFileViewed(params.fileId)
            return nil
        }
        router.register(method: ReviewMethods.UnmarkFileViewedMethod.self) { @MainActor [weak self] params in
            self?.paneState.review.unmarkFileViewed(params.fileId)
            return nil
        }
        router.register(method: ReviewMethods.MetadataInterestUpdateMethod.self) { @MainActor [weak self] params in
            guard let self else { return nil }
            if params.protocolId == "worktree-file" {
                try await self.handleWorktreeFileMetadataInterestUpdate(params)
                return nil
            }
            try await self.handleReviewMetadataInterestUpdate(params)
            return nil
        }

        // agent namespace
        registerStub(AgentMethods.RequestRewriteMethod.self)
        registerStub(AgentMethods.CancelTaskMethod.self)
        registerStub(AgentMethods.InjectPromptMethod.self)

        // inbox namespace
        router.register(method: InboxMethods.PostMethod.self) { @MainActor [weak self] params in
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
        router.register(method: method) { _ in
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
    func teardown() {
        page.stopLoading()
        diffPushPlan?.stop()
        reviewPushPlan?.stop()
        connectionPushPlan?.stop()
        agentPushPlan?.stop()
        activeReviewRefreshTask?.cancel()
        activeWorktreeFileTreeWindowTask?.cancel()
        diffPushPlan = nil
        reviewPushPlan = nil
        connectionPushPlan = nil
        agentPushPlan = nil
        activeReviewRefreshTask = nil
        activeWorktreeFileTreeWindowTask = nil
        hasPendingReviewRefresh = false
        activeWorktreeFileSurfaceSource = nil
        revokeReviewContentAuthoritySynchronously()
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "worktree-file")
        let reviewContentStore = reviewContentStore
        let worktreeFileResourceStore = worktreeFileResourceStore
        let resourceLeaseRegistry = resourceLeaseRegistry
        let paneId = paneId
        let worktreeFileMetadataScheduler = worktreeFileMetadataScheduler
        Task {
            await worktreeFileMetadataScheduler.closeGate(protocolId: "worktree-file")
            await worktreeFileMetadataScheduler.closeGate(protocolId: "review")
            await reviewContentStore.deactivate()
            await worktreeFileResourceStore.reset(protocolId: "worktree-file")
            await resourceLeaseRegistry.reset(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content",
                revokeAuthority: false
            )
            await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "worktree-file")
        }
        runtime.resetForControllerTeardown()
        bridgeDeliveryTail = nil
        lastPushed.removeAll()
        isBridgeReady = false
        nextReviewProtocolSequence = 0
        activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
        reviewProtocolSuppressedDrop = nil
        worktreeFileSuppressedDrop = nil
        pendingReviewPackageBuildReasons.removeAll()
        // Fence in-flight review jobs synchronously: their body guard reads
        // nextReviewGeneration, so bumping it here prevents a dispatchable
        // job from delivering between this sync phase and the async gate
        // close below.
        nextReviewGeneration = nextReviewGeneration.next()
    }

    // MARK: - Bridge Handshake

    /// Handle the `bridge.ready` message from the bridge world.
    ///
    /// This is gated and idempotent:
    /// - First call sets `isBridgeReady = true` and starts push plans.
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

        diffPushPlan = makeDiffPushPlan()
        reviewPushPlan = makeReviewPushPlan()
        connectionPushPlan = makeConnectionPushPlan()
        agentPushPlan = makeAgentPushPlan()

        diffPushPlan?.start()
        reviewPushPlan?.start()
        connectionPushPlan?.start()
        agentPushPlan?.start()
        return true
    }

    func handleBridgeIntakeReady(_ params: BridgeIntakeReadyMethod.Params) async {
        _ = await handleBridgeIntakeReadyResult(params)
    }

    func handleBridgeIntakeReadyResult(_ params: BridgeIntakeReadyMethod.Params) async -> BridgeIntakeReadyResult {
        switch params.protocolId {
        case "review":
            return await handleReviewIntakeReady(params)
        case "worktree-file":
            return await handleWorktreeFileIntakeReady(params)
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
        await worktreeFileMetadataScheduler.openGate(protocolId: "review")
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

    private func handleWorktreeFileIntakeReady(_ params: BridgeIntakeReadyMethod.Params) async
        -> BridgeIntakeReadyResult
    {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            bridgeControllerLogger.warning(
                "[Bridge] Worktree/File intake ready ignored without active source pane=\(self.paneId.uuidString, privacy: .public)"
            )
            return .rejected("worktree_file.intake_ready.no_active_source")
        }
        guard params.streamId == nil || params.streamId == activeSource.streamId else {
            bridgeControllerLogger.warning(
                """
                Bridge Worktree/File intake ready ignored for pane \(self.paneId.uuidString, privacy: .public): \
                stream \(String(describing: params.streamId), privacy: .public) does not match \(activeSource.streamId, privacy: .public)
                """
            )
            return .rejected("worktree_file.intake_ready.stale_stream")
        }
        guard params.generation == nil || params.generation == activeSource.source.subscriptionGeneration else {
            bridgeControllerLogger.warning(
                """
                Bridge Worktree/File intake ready ignored for pane \(self.paneId.uuidString, privacy: .public): \
                generation \(String(describing: params.generation), privacy: .public) does not match \
                \(activeSource.source.subscriptionGeneration, privacy: .public)
                """
            )
            return .rejected("worktree_file.intake_ready.stale_generation")
        }
        await worktreeFileMetadataScheduler.openGate(protocolId: "worktree-file")
        return .accepted
    }

    // MARK: - Test/entrypoint utility

    /// Entry point for valid command payloads.
    ///
    /// Separated for tests and command-handler reuse.
    func handleIncomingRPC(_ json: String) async {
        await router.dispatch(json: json, isBridgeReady: isBridgeReady)
    }

    func handleIncomingSchemeRPC(_ json: String) async -> String? {
        if let rejection = Self.schemeRPCBootstrapOnlyRejection(for: json) {
            bridgeControllerLogger.warning(
                "[BridgePaneController] rejected bridge.ready over scheme RPC for pane \(self.paneId.uuidString, privacy: .public)"
            )
            return rejection.responseJSON
        }
        return await router.dispatchForSchemeRPC(json: json, isBridgeReady: isBridgeReady)
    }

    private struct SchemeRPCBootstrapOnlyRejection: Sendable {
        let responseJSON: String?
    }

    private nonisolated static func schemeRPCBootstrapOnlyRejection(for json: String)
        -> SchemeRPCBootstrapOnlyRejection?
    {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            dictionary["method"] as? String == BridgeReadyMethod.method
        else {
            return nil
        }

        guard dictionary.keys.contains("id") else {
            return SchemeRPCBootstrapOnlyRejection(
                responseJSON: makeSchemeRPCErrorResponse(
                    id: NSNull(),
                    code: -32_600,
                    message: "Invalid request"
                )
            )
        }
        guard let responseID = schemeRPCResponseIDValue(from: dictionary["id"]) else {
            return SchemeRPCBootstrapOnlyRejection(
                responseJSON: makeSchemeRPCErrorResponse(
                    id: NSNull(),
                    code: -32_600,
                    message: "Invalid request: invalid id"
                )
            )
        }
        return SchemeRPCBootstrapOnlyRejection(
            responseJSON: makeSchemeRPCErrorResponse(
                id: responseID,
                code: -32_601,
                message: "bridge.ready is bootstrap-only"
            )
        )
    }

    private nonisolated static func makeSchemeRPCErrorResponse(id: Any, code: Int, message: String) -> String? {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(envelope),
            let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func schemeRPCResponseIDValue(from id: Any?) -> Any? {
        guard let id else {
            return nil
        }
        if let string = id as? String {
            return string
        }
        if let number = id as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number
        }
        if id is NSNull {
            return NSNull()
        }
        return nil
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
