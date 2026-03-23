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

    // MARK: - Push Plans

    private var diffPushPlan: PushPlan<DiffState>?
    private var reviewPushPlan: PushPlan<ReviewState>?
    private var connectionPushPlan: PushPlan<PaneDomainState>?
    private var agentPushPlan: PushPlan<PaneDomainState>?

    // MARK: - Private State

    let router: RPCRouter
    private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    private let userContentController: WKUserContentController
    private let bootstrapScript: WKUserScript
    private var managementScript: WKUserScript
    private(set) var isContentInteractionEnabled: Bool
    private var interactionApplyTask: Task<Void, Never>?

    /// Per store+op dedup cache. Bounded at O(StoreKey × PushOp) — currently 8 entries max.
    /// Each entry stores the epoch it was pushed in + the payload bytes. Dedup only matches
    /// within the same epoch — a new epoch always goes through even with identical bytes.
    /// This avoids cross-store thrash that a global epoch tracker would cause (connection
    /// uses epoch=0, diff uses diff.epoch, etc.)
    private var lastPushed: [String: DedupEntry] = [:]

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
        metadata: PaneMetadata? = nil
    ) {
        self.paneId = paneId
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
        let blockInteraction = ManagementModeMonitor.shared.isActive
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
        let bootstrapScript = WKUserScript(
            source: BridgeBootstrap.generateScript(bridgeNonce: bridgeNonce, pushNonce: pushNonce),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: bridgeWorld
        )
        self.bootstrapScript = bootstrapScript
        userContentController.addUserScript(bootstrapScript)
        userContentController.addUserScript(initialManagementScript)

        // Register scheme handler for agentstudio:// URLs (bundled React app assets + resources).
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(paneId: paneId)
        }

        // Create WebPage with bridge-specific navigation and dialog policies.
        self.page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        self.router = RPCRouter()

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

        onRuntimeEvent = { [weak self] event, commandId, correlationId in
            self?.runtime.ingestBridgeEvent(event, commandId: commandId, correlationId: correlationId)
        }
        onRuntimeCommandAck = { [weak self] ack in
            self?.runtime.recordCommandAck(ack)
        }
        runtime.commandHandler = self

        registerNamespaceHandlers()
    }

    // MARK: - Content Interaction

    /// Called by the pane view when management mode toggles. Keeps both the currently
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
                try? await Task.sleep(for: .milliseconds(50))
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
        registerStub(DiffMethods.RequestFileContentsMethod.self)
        registerStub(DiffMethods.LoadDiffMethod.self)

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
        diffPushPlan = nil
        reviewPushPlan = nil
        connectionPushPlan = nil
        agentPushPlan = nil
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
                Slice("diffStatus", store: .diff, level: .hot) { state in
                    DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                }
                EntitySlice(
                    "diffFiles", store: .diff, level: .cold,
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
            // Review epoch tracks diff epoch for now (Phase 2 stub — ReviewState has no
            // independent epoch). Phase 3+ should add review.epoch if review data has its own
            // version timeline separate from diffs.
            epoch: { [paneState] in paneState.diff.epoch },
            slices: {
                EntitySlice(
                    "reviewThreads", store: .review, level: .warm,
                    capture: { state in state.threads },
                    version: { thread in thread.version },
                    keyToString: { $0.uuidString }
                )
                Slice("reviewViewedFiles", store: .review, level: .warm) { state in
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
                Slice("connectionHealth", store: .connection, level: .hot) { state in
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
                Slice("commandAcks", store: .agent, level: .warm) { state in
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
            source: .floating(workingDirectory: nil, title: title),
            title: title
        )
    }

    private static func contentType(for state: BridgePaneState) -> PaneContentType {
        switch state.panelKind {
        case .diffViewer:
            return .diff
        }
    }

}

// MARK: - DedupEntry

/// Cache entry for transport-level content dedup.
/// Stores the epoch + payload for a given store+op key.
/// Dedup only matches within the same epoch — epoch transitions always push through.
private struct DedupEntry {
    let epoch: Int
    let payload: Data
}

// MARK: - PushTransport Conformance

extension BridgePaneController: PushTransport {
    func pushJSON(
        store: StoreKey,
        op: PushOp,
        level: PushLevel,
        revision: Int,
        epoch: Int,
        json: Data
    ) async {
        // Content guard — skip identical pushes to same store+op within the same epoch.
        // Keyed by store+op (not epoch) so the cache is bounded at O(StoreKey × PushOp).
        // Epoch is stored in the entry value — a new epoch always goes through even with
        // identical bytes, because React needs to see epoch transitions for tracking.
        // Including op ensures .replace and .merge with identical bytes are not
        // deduplicated (they have different semantics).
        let dedupKey = "\(store.rawValue):\(op.rawValue)"
        if let previous = lastPushed[dedupKey],
            previous.epoch == epoch,
            previous.payload == json
        {
            return
        }

        // Phase 1: encode the push envelope (encoding bugs are NOT connection errors).
        let envelopeString: String
        do {
            let payload = try JSONSerialization.jsonObject(with: json)
            let envelope: [String: Any] = [
                "__v": 1,
                "__revision": revision,
                "__epoch": epoch,
                "__pushId": UUID().uuidString,
                "store": store.rawValue,
                "op": op.rawValue,
                "level": level.rawValue,
                "payload": payload,
            ]
            let envelopeJSON = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            guard let encoded = String(data: envelopeJSON, encoding: .utf8) else {
                throw BridgeError.encoding("Unable to encode push envelope as UTF-8")
            }
            envelopeString = encoded
        } catch {
            bridgeControllerLogger.error(
                "[Bridge] envelope encoding bug store=\(store.rawValue) rev=\(revision): \(error)"
            )
            return
        }
        // Phase 2: transport the envelope to React (transport failures ARE connection errors).
        do {
            try await page.callJavaScript(
                "window.__bridgeInternal.applyEnvelope(JSON.parse(json))",
                arguments: ["json": envelopeString],
                contentWorld: bridgeWorld
            )
            lastPushed[dedupKey] = DedupEntry(epoch: epoch, payload: json)
            bridgeControllerLogger.debug(
                "[BridgePaneController] pushJSON store=\(store.rawValue) op=\(op.rawValue) level=\(String(describing: level)) rev=\(revision) epoch=\(epoch) bytes=\(json.count)"
            )
        } catch {
            bridgeControllerLogger.warning(
                "[Bridge] JS transport failed store=\(store.rawValue) rev=\(revision) epoch=\(epoch): \(error)"
            )
            paneState.connection.setHealth(.error)
        }
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
