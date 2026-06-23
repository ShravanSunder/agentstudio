import Foundation
import Observation
import WebKit
import os.log

private let bridgeControllerLogger = Logger(subsystem: "com.agentstudio", category: "BridgePaneController")
enum BridgeReadyMethod: RPCMethod {
    struct Params: Decodable {}
    typealias Result = RPCNoResponse

    static let method = "bridge.ready"
}

/// Per-pane controller for bridge-backed panels (diff viewer, code review, etc.).
///
/// Each bridge pane gets its own `WebPage.Configuration` with:
/// - Non-persistent data store (no cookies/history needed for internal panels)
/// - `RPCMessageHandler` in a dedicated bridge content world (isolated from page scripts)
/// - Bootstrap `WKUserScript` injected at document start in the bridge world
/// - `BridgeSchemeHandler` registered for the `agentstudio://` custom URL scheme
///
/// The controller owns the `RPCRouter` that dispatches incoming JSON-RPC messages
/// from the bridge world to registered handlers. Push plans are started
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

    // MARK: - Runtime Hooks

    var onRuntimeEvent: (@MainActor @Sendable (PaneRuntimeEvent, UUID?, UUID?) -> Void)?
    var onRuntimeCommandAck: (@MainActor @Sendable (CommandAck) -> Void)?

    // MARK: - Domain State

    let revisionClock = RevisionClock()
    let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
    let reviewContentStore: BridgeContentStore
    let reviewPipeline: BridgeReviewPipeline
    let reviewChangeIndex = BridgeChangeIndex()
    let bridgePaneState: BridgePaneState
    var nextReviewGeneration: BridgeReviewGeneration = 0
    var selectedReviewItemId: String?
    var activeReviewRefreshTask: Task<Void, Never>?
    var hasPendingReviewRefresh = false

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
    private let userContentController: WKUserContentController
    private let bootstrapScript: WKUserScript
    private var managementScript: WKUserScript
    private(set) var isContentInteractionEnabled: Bool
    private var interactionApplyTask: Task<Void, Never>?
    var pushDeliveryTail: Task<Void, Never>?
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
            BridgePaneController.dispatchPushEnvelope
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
        // Each bridge pane needs its own userContentController for message handler and bootstrap script
        // registration, and its own urlSchemeHandlers for the agentstudio:// scheme.
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        self.userContentController = config.userContentController

        // Register message handler in bridge content world only.
        // Page world scripts cannot access this handler — content world isolation enforced by WebKit.
        let messageHandler = RPCMessageHandler()
        userContentController.add(
            messageHandler,
            contentWorld: bridgeWorld,
            name: "rpc"
        )

        // Bootstrap script — installs __bridgeInternal relay in bridge world,
        // sets up nonce-validated command forwarding, and dispatches handshake event.
        let bridgeNonce = UUID().uuidString
        let pushNonce = UUID().uuidString
        self.pushNonce = pushNonce
        self.pushEnvelopeSink = pushEnvelopeSink
        let webTelemetryScopes = resolvedTelemetryScopeGate.browserExposedScopes
        let telemetryConfig =
            !webTelemetryScopes.isEmpty
            ? BridgeTelemetryBootstrapConfig.enabled(
                scopes: webTelemetryScopes,
                scenario: BridgeTelemetryBootstrapConfig.packageApplyContentFetchScenario
            )
            : nil
        let bootstrapScript = WKUserScript(
            source: BridgeBootstrap.generateScript(
                bridgeNonce: bridgeNonce,
                pushNonce: pushNonce,
                telemetryConfig: telemetryConfig
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: bridgeWorld
        )
        self.bootstrapScript = bootstrapScript
        userContentController.addUserScript(bootstrapScript)
        #if DEBUG
            userContentController.addUserScript(Self.makePageDiagnosticsProbeScript())
        #endif
        userContentController.addUserScript(initialManagementScript)

        // Register scheme handler for agentstudio:// URLs (bundled React app assets + resources).
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(
                paneId: paneId,
                contentStore: reviewContentStore,
                resourceLeaseRegistry: resourceLeaseRegistry,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds,
                telemetryRecorder: resolvedTelemetryRecorder
            )
        }

        // Create WebPage with bridge-specific navigation and dialog policies.
        self.page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        self.router = RPCRouter()
        configureRouter(
            router,
            messageHandler: messageHandler,
            telemetryRecorder: resolvedTelemetryRecorder,
            telemetryIngestor: resolvedTelemetryIngestor
        )

        onRuntimeEvent = { [weak self] event, commandId, correlationId in
            self?.runtime.ingestBridgeEvent(event, commandId: commandId, correlationId: correlationId)
        }
        onRuntimeCommandAck = { [weak self] ack in
            self?.runtime.recordCommandAck(ack)
        }
        runtime.commandHandler = self

        registerNamespaceHandlers()
    }

    private nonisolated static func resolveTelemetryDependencies(
        traceRuntime: AgentStudioTraceRuntime?,
        telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy,
        telemetryScopeGate: BridgeTelemetryScopeGate?,
        telemetryRecorder: (any BridgePerformanceTraceRecording)?,
        telemetryIngestor: (any BridgeTelemetryBatchIngesting)?
    ) -> (
        scopeGate: BridgeTelemetryScopeGate,
        recorder: (any BridgePerformanceTraceRecording)?,
        ingestor: (any BridgeTelemetryBatchIngesting)?
    ) {
        guard telemetryRuntimePolicy.allowsTelemetry else {
            return (BridgeTelemetryScopeGate(enabledScopes: []), nil, nil)
        }

        let resolvedScopeGate = telemetryScopeGate ?? BridgeTelemetryScopeGate(traceRuntime: traceRuntime)
        let resolvedRecorder =
            telemetryRecorder
            ?? (resolvedScopeGate.isEnabled ? BridgePerformanceTraceRecorder(traceRuntime: traceRuntime) : nil)
        let resolvedIngestor =
            resolvedScopeGate.isEnabled(.web)
            ? (telemetryIngestor
                ?? resolvedRecorder.map {
                    BridgeTelemetryIngestor(scopeGate: resolvedScopeGate, recorder: $0)
                })
            : nil
        return (resolvedScopeGate, resolvedRecorder, resolvedIngestor)
    }

    private func configureRouter(
        _ router: RPCRouter,
        messageHandler: RPCMessageHandler,
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
        router.onResponse = { [weak self] responseJSON in
            await self?.emitRPCResponse(responseJSON)
        }

        // Wire message handler → router: validated JSON from postMessage is dispatched to handlers.
        messageHandler.onValidJSON = { [weak self] json in
            await self?.handleIncomingRPC(json)
        }

        // Register bridge.ready handler — the ONLY trigger for starting push plans.
        // The closure is @Sendable and async — awaits the @MainActor-isolated handleBridgeReady.
        router.register(method: BridgeReadyMethod.self) { [weak self] _ in
            self?.handleBridgeReady()
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

        let body = params.body?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
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
        diffPushPlan = nil
        reviewPushPlan = nil
        connectionPushPlan = nil
        agentPushPlan = nil
        activeReviewRefreshTask = nil
        hasPendingReviewRefresh = false
        let reviewContentStore = reviewContentStore
        let resourceLeaseRegistry = resourceLeaseRegistry
        let paneId = paneId
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "review", resourceKind: "content")
        Task {
            await reviewContentStore.deactivate()
            await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "review", resourceKind: "content")
        }
        runtime.resetForControllerTeardown()
        lastPushed.removeAll()
        isBridgeReady = false
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
    func handleBridgeReady() {
        guard !isBridgeReady else { return }
        if runtime.lifecycle == .created {
            guard runtime.transitionToReady() else {
                bridgeControllerLogger.error(
                    "Bridge ready handshake failed runtime transition for pane \(self.paneId.uuidString, privacy: .public)"
                )
                return
            }
        } else if runtime.lifecycle != .ready {
            bridgeControllerLogger.error(
                """
                Bridge ready handshake rejected for pane \(self.paneId.uuidString, privacy: .public): \
                runtime lifecycle \(String(describing: self.runtime.lifecycle), privacy: .public)
                """
            )
            return
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
    }

    // MARK: - Test/entrypoint utility

    /// Entry point for valid command payloads.
    ///
    /// Separated for tests and command-handler reuse.
    func handleIncomingRPC(_ json: String) async {
        await router.dispatch(json: json, isBridgeReady: isBridgeReady)
    }

    /// Runtime-facing typed event ingress for bridge domain events.
    func ingestRuntimeEvent(
        _ event: PaneRuntimeEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        onRuntimeEvent?(event, commandId, correlationId)
    }

    // MARK: - Push Plan Factories

    private func makeDiffPushPlan() -> PushPlan<DiffState> {
        PushPlan(
            state: paneState.diff,
            transport: self,
            revisions: revisionClock,
            epoch: { [paneState] in paneState.diff.epoch },
            slices: {
                Slice("diffStatus", telemetrySlice: .diffStatus, store: .diff, level: .hot) { state in
                    DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                }
                Slice(
                    "diffPackageMetadata",
                    telemetrySlice: .diffPackageMetadata,
                    store: .diff,
                    level: .cold,
                    op: .replace
                ) { state in
                    DiffPackageMetadataSlice(package: state.packageMetadata)
                }
                Slice(
                    "diffPackageDelta",
                    telemetrySlice: .diffPackageDelta,
                    store: .diff,
                    level: .warm,
                    op: .merge
                ) { state in
                    DiffPackageDeltaSlice(delta: state.packageDelta)
                }
                EntitySlice(
                    "diffFiles", telemetrySlice: .diffFiles, store: .diff, level: .cold,
                    capture: { state in state.files },
                    version: { file in file.version },
                    keyToString: { $0 }
                )
            }
        )
    }

    private func makeReviewPushPlan() -> PushPlan<ReviewState> {
        PushPlan(
            state: paneState.review,
            transport: self,
            revisions: revisionClock,
            // Review epoch tracks diff epoch until review data has its own
            // version timeline separate from diffs.
            epoch: { [paneState] in paneState.diff.epoch },
            slices: {
                EntitySlice(
                    "reviewThreads", telemetrySlice: .reviewThreads, store: .review, level: .warm,
                    capture: { state in state.threads },
                    version: { thread in thread.version },
                    keyToString: { $0.uuidString }
                )
                Slice(
                    "reviewViewedFiles",
                    telemetrySlice: .reviewViewedFiles,
                    store: .review,
                    level: .warm
                ) { state in
                    state.viewedFiles.sorted()
                }
            }
        )
    }

    private func makeConnectionPushPlan() -> PushPlan<PaneDomainState> {
        PushPlan(
            state: paneState,
            transport: self,
            revisions: revisionClock,
            epoch: { 0 },
            slices: {
                Slice("connectionHealth", telemetrySlice: .connectionHealth, store: .connection, level: .hot) { state in
                    ConnectionSlice(health: state.connection.health, latencyMs: state.connection.latencyMs)
                }
            }
        )
    }

    private func makeAgentPushPlan() -> PushPlan<PaneDomainState> {
        PushPlan(
            state: paneState,
            transport: self,
            revisions: revisionClock,
            epoch: { 0 },
            slices: {
                Slice("commandAcks", telemetrySlice: .commandAcks, store: .agent, level: .warm) { state in
                    state.commandAcks
                }
            }
        )
    }

    private func handleRuntimeCommandAck(_ ack: CommandAck) {
        onRuntimeCommandAck?(ack)
    }

    private func emitRPCResponse(_ responseJSON: String) async {
        do {
            try await page.callJavaScript(
                """
                const payload = JSON.parse(json);
                window.__bridgeInternal.response(payload.id, payload.result, payload.error);
                """,
                arguments: ["json": responseJSON],
                contentWorld: bridgeWorld
            )
        } catch {
            bridgeControllerLogger.warning("[Bridge] JS response transport failed: \(error)")
            paneState.connection.setHealth(.error)
        }
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
        }

        return PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            title: title
        )
    }

    private static func contentType(for state: BridgePaneState) -> PaneContentType {
        switch state.panelKind {
        case .diffViewer:
            return .diff
        }
    }

    private static func dispatchPushEnvelope(
        page: WebPage,
        envelopeString: String,
        pushNonce: String
    ) async throws {
        let envelopeLiteral = try makeJavaScriptStringLiteral(envelopeString)
        let nonceLiteral = try makeJavaScriptStringLiteral(pushNonce)
        try await page.callJavaScript(
            """
            document.dispatchEvent(new CustomEvent('__bridge_push_json', {
                detail: { json: \(envelopeLiteral), nonce: \(nonceLiteral) }
            }));
            """,
            contentWorld: .page
        )
    }

    #if DEBUG
        private static func makePageDiagnosticsProbeScript() -> WKUserScript {
            WKUserScript(
                source: """
                    (() => {
                      const maxEntries = 40;
                      const clip = (value, limit) => String(value ?? '').slice(0, limit);
                      const pushBounded = (target, entry) => {
                        target.push(entry);
                        if (target.length > maxEntries) {
                          target.splice(0, target.length - maxEntries);
                        }
                      };
                      window.__bridgeErrorProbe = [];
                      window.__bridgePushProbe = [];
                      const requestLabel = (input) => {
                        if (typeof input === 'string') { return input; }
                        if (input instanceof URL) { return input.href; }
                        return input?.url ?? String(input);
                      };
                      window.addEventListener('error', (event) => {
                        pushBounded(window.__bridgeErrorProbe, {
                          kind: 'error',
                          message: clip(event.message, 300),
                          stack: clip(event.error?.stack, 800)
                        });
                      });
                      window.addEventListener('unhandledrejection', (event) => {
                        pushBounded(window.__bridgeErrorProbe, {
                          kind: 'unhandledrejection',
                          message: clip(event.reason?.message ?? event.reason, 300),
                          stack: clip(event.reason?.stack, 800)
                        });
                      });
                      if (typeof window.fetch === 'function') {
                        const originalFetch = window.fetch.bind(window);
                        window.fetch = (input, init) => {
                          const url = requestLabel(input);
                          return originalFetch(input, init).catch((error) => {
                            pushBounded(window.__bridgeErrorProbe, {
                              kind: 'fetch_error',
                              message: clip(url + ': ' + (error?.message ?? error), 300),
                              stack: clip(error?.stack, 800)
                            });
                            throw error;
                          });
                        };
                      }
                      document.addEventListener('__bridge_push_json', (event) => {
                        pushBounded(window.__bridgePushProbe, {
                          hasDetail: Boolean(event.detail),
                          hasJson: typeof event.detail?.json === 'string',
                          jsonLength: typeof event.detail?.json === 'string'
                            ? event.detail.json.length
                            : -1,
                          nonceLength: typeof event.detail?.nonce === 'string'
                            ? event.detail.nonce.length
                            : -1
                        });
                      });
                    })();
                    """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            )
        }
    #endif

    private static func makeJavaScriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw BridgeError.encoding("Unable to encode push envelope as JavaScript string literal")
        }
        return literal
    }

}

private enum BridgeError: Error, LocalizedError, Sendable {
    case encoding(String)

    var errorDescription: String? {
        switch self {
        case .encoding(let message):
            return message
        }
    }
}

struct BridgeMethodUnimplementedError: Error, LocalizedError, Sendable {
    let method: String

    var errorDescription: String? {
        "Unimplemented bridge method: \(method)"
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
