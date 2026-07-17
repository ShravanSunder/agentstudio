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
    // MARK: - Domain State

    let reviewContentLoaderCache: BridgeReviewContentLoaderCache
    let productAdmissionGate: BridgeProductAdmissionGate
    let refreshAdmissionCoordinator: BridgePaneRefreshAdmissionCoordinator
    let reviewPublicationCoordinator: BridgeReviewPublicationCoordinator
    let productSessionOwner: BridgePaneProductSessionOwner
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSchemeProvider: BridgePaneProductSchemeProvider?
    let reviewPipeline: BridgeReviewPipeline
    let reviewChangeIndex = BridgeChangeIndex()
    let bridgePaneState: BridgePaneState
    var nextReviewGeneration: BridgeReviewGeneration = 0
    var selectedReviewItemId: String?
    var activeReviewRefreshTask: Task<Void, Never>?
    var productPresentationTransitionGeneration: UInt64 = 0
    var productPresentationTransitionTail: Task<Void, Never>?
    var surfaceSelectionTransitionTail: Task<Void, Never>?
    var pendingReviewPackageBuildReasons: Set<BridgeReviewPackageBuildReason> = []
    var activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
    var surfaceSelectionAuthority = BridgePaneSurfaceSelectionAuthority()

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
    ///   - state: Serializable bridge pane state (panel kind + source).
    ///   - metadata: Optional runtime metadata override used by runtime registration paths.
    init(
        paneId: UUID,
        state: BridgePaneState,
        metadata: PaneMetadata? = nil,
        reviewSourceProvider: (any BridgeReviewSourceProvider)? = nil,
        gitReadContext: BridgeGitReadContext? = nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy = .live,
        telemetryScopeGate: BridgeTelemetryScopeGate? = nil,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil,
        traceContextFactory: BridgeTraceContextFactory = .live,
        initialPaneActivity: BridgePaneActivity,
        productSessionDependencies: BridgePaneProductSessionDependencies? = nil,
        telemetrySessionDependencies: BridgePaneTelemetrySessionDependencies? = nil,
        productSessionBootstrapSink: @escaping BridgeProductSessionBootstrapSink =
            BridgePaneController.dispatchProductSessionBootstrap,
        telemetrySessionBootstrapSink: @escaping BridgeTelemetrySessionBootstrapSink =
            BridgePaneController.dispatchTelemetrySessionBootstrap
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
        let resolvedReviewContentLoaderCache = BridgeReviewContentLoaderCache(
            provider: resolvedReviewSourceProvider
        )
        self.reviewContentLoaderCache = resolvedReviewContentLoaderCache
        let resolvedRefreshAdmissionCoordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: initialPaneActivity
        )
        self.refreshAdmissionCoordinator = resolvedRefreshAdmissionCoordinator
        let resolvedReviewPublicationCoordinator = BridgeReviewPublicationCoordinator()
        self.reviewPublicationCoordinator = resolvedReviewPublicationCoordinator
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
                BridgeProductSessionDependencyInput(
                    paneSessionId: paneId.uuidString,
                    runtime: resolvedRuntime,
                    state: state,
                    gitReadContext: gitReadContext,
                    reviewContentLoaderCache: resolvedReviewContentLoaderCache,
                    reviewPublicationCoordinator: resolvedReviewPublicationCoordinator,
                    refreshWorkAdmissionSource: resolvedRefreshAdmissionCoordinator.workAdmissionSource,
                    initialProductPresentation: resolvedRefreshAdmissionCoordinator.productPresentationSnapshot,
                    telemetryRecorder: telemetryDependencies.recorder
                )
            )
        self.productSessionOwner = resolvedProductSessionDependencies.owner
        self.productAdmissionGate = resolvedProductSessionDependencies.owner.productAdmissionGate
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

        // Register only the closed bootstrap handler in the bridge content world.
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
        self.productSessionBootstrapSink = productSessionBootstrapSink
        self.telemetrySessionBootstrapSink = telemetrySessionBootstrapSink
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
                telemetrySessionOwner: telemetryDependencies.sessionDependencies?.owner,
                productSessionRouter: resolvedProductSessionDependencies.owner.schemeRouter
            )
        )

        // Create WebPage with bridge-specific navigation and dialog policies.
        self.page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        configureReadyMessageHandler(readyMessageHandler)
        configureRuntimeCallbacks()
        resolvedProductSessionDependencies.committedCallTarget?.controller = self
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
    func loadApp() {
        guard let appURL = URL(string: "agentstudio://app/index.html") else { return }
        _ = page.load(appURL)
    }

    /// Called when the pane is being removed or the controller is being deallocated.
    @discardableResult
    func teardown() -> Task<Bool, Never> {
        if let lifecycleRetirementTask {
            return lifecycleRetirementTask
        }
        if !isTeardownStarted {
            isTeardownStarted = true
            refreshAdmissionCoordinator.close()
            productAdmissionGate.close()
            reviewPublicationCoordinator.close()
            activeReviewRefreshTask?.cancel()
            activeReviewRefreshTask = nil
            let reviewContentLoaderCache = reviewContentLoaderCache
            let productSchemeProvider = productSchemeProvider
            let productPresentationTransitionTail = productPresentationTransitionTail
            let surfaceSelectionTransitionTail = surfaceSelectionTransitionTail
            teardownCleanupTask = Task {
                await productPresentationTransitionTail?.value
                await surfaceSelectionTransitionTail?.value
                async let contentDemandDrain: Void? = productSchemeProvider?.closeAndDrain()
                await reviewContentLoaderCache.closeAndDrain()
                _ = await contentDemandDrain
            }
            runtime.resetForControllerTeardown()
            isBridgeReady = false
            activeViewerModeSignalState = BridgeActiveViewerModeSignalState()
            pendingReviewPackageBuildReasons.removeAll()
            // Fence in-flight review jobs synchronously before asynchronous retirement.
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

    private static func contentType(for state: BridgePaneState) -> PaneContentType {
        switch state.panelKind {
        case .diffViewer, .fileViewer:
            return .diff
        }
    }

}

extension BridgePaneController {
    var bootstrapScriptSourceForTesting: String { bootstrapScript.source }
}
