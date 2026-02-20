import Foundation
import Observation
import WebKit
import os.log

private let bridgeControllerLogger = Logger(subsystem: "com.agentstudio", category: "BridgePaneController")

/// Per-pane controller for bridge-backed panels (diff viewer, code review, etc.).
///
/// Each bridge pane gets its own `WebPage.Configuration` with:
/// - Non-persistent data store (no cookies/history needed for internal panels)
/// - `RPCMessageHandler` in a dedicated bridge content world (isolated from page scripts)
/// - Bootstrap `WKUserScript` injected at document start in the bridge world
/// - `BridgeSchemeHandler` registered for the `agentstudio://` custom URL scheme
///
/// The controller owns the `RPCRouter` that dispatches incoming JSON-RPC messages
/// from the bridge world to registered handlers. Push plans (Stage 3) will be started
/// only after the `bridge.ready` handshake completes.
///
/// Unlike `WebviewPaneController` which uses a shared static configuration,
/// `BridgePaneController` creates a **per-pane** configuration because each pane
/// needs its own `WKUserContentController` for message handlers and bootstrap scripts.
///
/// Design doc §9.1, handshake gating §4.5.
@Observable
@MainActor
final class BridgePaneController {

    // MARK: - Public State

    let paneId: UUID
    let page: WebPage

    /// Whether the bridge handshake has completed (§4.5 step 6).
    /// No state pushes or commands are allowed before this becomes `true`.
    /// Gated and idempotent — once set, subsequent `bridge.ready` messages are ignored.
    private(set) var isBridgeReady = false

    // MARK: - Domain State

    let paneState = PaneDomainState()
    let revisionClock = RevisionClock()

    // MARK: - Push Plans

    private var diffPushPlan: PushPlan<DiffState>?
    private var reviewPushPlan: PushPlan<ReviewState>?
    private var connectionPushPlan: PushPlan<PaneDomainState>?

    // MARK: - Private State

    private let router: RPCRouter
    private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    private var lastPushedJSON: [String: Data] = [:]

    // MARK: - Init

    /// Create a bridge pane controller with per-pane WebPage configuration.
    ///
    /// - Parameters:
    ///   - paneId: Unique identifier for this pane instance.
    ///   - state: Serializable bridge pane state (panel kind + source).
    init(paneId: UUID, state: BridgePaneState) {
        self.paneId = paneId

        // Per-pane configuration — NOT shared (unlike WebviewPaneController.sharedConfiguration).
        // Each bridge pane needs its own userContentController for message handler and bootstrap script
        // registration, and its own urlSchemeHandlers for the agentstudio:// scheme.
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()

        // Register message handler in bridge content world only.
        // Page world scripts cannot access this handler — content world isolation enforced by WebKit.
        let messageHandler = RPCMessageHandler()
        config.userContentController.add(
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
        config.userContentController.addUserScript(bootstrapScript)

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

        // Log RPC-level errors (parse errors, unknown methods, batch rejection).
        // Handler execution errors are caught separately in the onValidJSON callback below.
        router.onError = { code, message, id in
            bridgeControllerLogger.warning(
                "[BridgePaneController] RPC error code=\(code) msg=\(message) id=\(String(describing: id))"
            )
        }

        // Wire message handler → router: validated JSON from postMessage is dispatched to handlers.
        messageHandler.onValidJSON = { [weak self] json in
            do {
                try await self?.router.dispatch(json: json)
            } catch {
                bridgeControllerLogger.error("[BridgePaneController] RPC dispatch error: \(error)")
            }
        }

        // Register bridge.ready handler — the ONLY trigger for starting push plans (§4.5 step 6).
        // The closure is @Sendable but RPCRouter.dispatch is @MainActor, so the handler
        // always runs on the main actor. Use assumeIsolated to satisfy the type checker.
        router.register("bridge.ready") { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleBridgeReady()
            }
        }
    }

    // MARK: - Lifecycle

    /// Load the bundled React application via the custom scheme.
    ///
    /// Push plans do NOT start here — they start when `bridge.ready` is received.
    /// `page.isLoading == false` does not guarantee React has mounted and listeners
    /// are attached (§4.5).
    func loadApp() {
        guard let appURL = URL(string: "agentstudio://app/index.html") else { return }
        _ = page.load(appURL)
    }

    /// Tear down all active push plans and reset bridge state.
    ///
    /// Called when the pane is being removed or the controller is being deallocated.
    /// Push plan teardown will be added in Stage 3.
    func teardown() {
        diffPushPlan?.stop()
        reviewPushPlan?.stop()
        connectionPushPlan?.stop()
        diffPushPlan = nil
        reviewPushPlan = nil
        connectionPushPlan = nil
        lastPushedJSON.removeAll()
        isBridgeReady = false
    }

    // MARK: - Bridge Handshake

    /// Handle the `bridge.ready` message from the bridge world.
    ///
    /// This is gated and idempotent (§4.5 line 246):
    /// - First call sets `isBridgeReady = true` and will start push plans (Stage 3).
    /// - Subsequent calls are silently ignored.
    ///
    /// `internal` (not `private`) for testability — allows integration tests to
    /// invoke the handshake directly without routing through WebKit message handlers.
    func handleBridgeReady() {
        guard !isBridgeReady else { return }
        isBridgeReady = true

        diffPushPlan = makeDiffPushPlan()
        reviewPushPlan = makeReviewPushPlan()
        connectionPushPlan = makeConnectionPushPlan()

        diffPushPlan?.start()
        reviewPushPlan?.start()
        connectionPushPlan?.start()
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
        // Content guard — skip identical pushes to same store+op pair.
        // Using store:op as key ensures a .replace and .merge to the same store
        // with identical bytes are NOT deduplicated (they have different semantics).
        let dedupKey = "\(store.rawValue):\(op.rawValue)"
        if lastPushedJSON[dedupKey] == json { return }
        lastPushedJSON[dedupKey] = json

        // Phase 2 stub: log the push. Full callJavaScript implementation in Phase 4.
        bridgeControllerLogger.debug(
            "[BridgePaneController] pushJSON store=\(store.rawValue) op=\(op.rawValue) level=\(String(describing: level)) rev=\(revision) epoch=\(epoch) bytes=\(json.count)"
        )
    }
}
