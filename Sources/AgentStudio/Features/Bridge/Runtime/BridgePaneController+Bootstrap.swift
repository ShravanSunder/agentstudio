import Foundation
import WebKit
import os.log

private let bridgeProductBootstrapLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeProductBootstrap"
)

typealias BridgeProductSessionBootstrapSink =
    @MainActor (
        _ page: WebPage,
        _ requestId: String,
        _ installation: BridgeProductSessionInstallation,
        _ contentWorld: WKContentWorld
    ) async throws -> Void

typealias BridgeTelemetrySessionBootstrapSink =
    @MainActor (
        _ page: WebPage,
        _ requestId: String,
        _ installation: BridgeTelemetrySessionInstallation?,
        _ contentWorld: WKContentWorld
    ) async throws -> Void

struct BridgeBootstrapScriptInput {
    let bridgeNonce: String
    let pushNonce: String
    let reviewPaneId: String
    let reviewStreamId: String
    let panelKind: BridgePanelKind
    let telemetryConfig: BridgeTelemetryBootstrapConfig?
    let bridgeWorld: WKContentWorld
}

struct BridgeBootstrapArtifacts {
    let pushNonce: String
    let script: WKUserScript
}

struct BridgeSchemeHandlerRegistrationInput {
    let paneId: UUID
    let reviewContentStore: BridgeContentStore
    let resourceLeaseRegistry: BridgeTransportResourceLeaseRegistry
    let telemetryRecorder: (any BridgePerformanceTraceRecording)?
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSessionOwner: BridgePaneProductSessionOwner
    let productSessionRouter: BridgeProductSchemeSessionRouter
}

struct BridgePaneTelemetrySessionDependencies: Sendable {
    let installation: BridgeTelemetrySessionInstallation
    let owner: BridgePaneTelemetrySessionOwner
}

struct BridgePaneProductSessionDependencies {
    let installation: BridgeProductSessionInstallation
    let owner: BridgePaneProductSessionOwner
    let committedCallTarget: BridgePaneProductCommittedCallTarget?
    let productProvider: BridgePaneProductSchemeProvider?

    init(
        installation: BridgeProductSessionInstallation,
        owner: BridgePaneProductSessionOwner,
        committedCallTarget: BridgePaneProductCommittedCallTarget? = nil,
        productProvider: BridgePaneProductSchemeProvider? = nil
    ) {
        self.installation = installation
        self.owner = owner
        self.committedCallTarget = committedCallTarget
        self.productProvider = productProvider
    }
}

@MainActor
final class BridgePaneProductCommittedCallTarget {
    weak var controller: BridgePaneController?

    func applyActiveViewerModeUpdate(_ call: BridgeProductCallRequest) async {
        let mode: BridgeActiveViewerMode
        let sourceProtocol: BridgeActiveViewerSourceProtocol
        let update: BridgeProductActiveViewerModeUpdateRequest
        switch call {
        case .fileSourceCurrent:
            return
        case .fileActiveViewerModeUpdate(let request):
            mode = .file
            sourceProtocol = .worktreeFile
            update = request
        case .reviewActiveViewerModeUpdate(let request):
            mode = .review
            sourceProtocol = .review
            update = request
        case .reviewIntakeReady:
            return
        case .reviewMarkFileViewed:
            return
        }
        let activeSource = update.activeSource.map {
            BridgeActiveViewerSource(
                protocolId: sourceProtocol,
                streamId: $0.streamId,
                generation: $0.generation
            )
        }
        await controller?.handleCommittedProductActiveViewerModeUpdate(
            sessionId: update.sessionId,
            sequence: update.sequence,
            mode: mode,
            activeSource: activeSource
        )
    }

    func applyReviewIntakeReady(_ request: BridgeProductReviewIntakeReadyRequest) async {
        _ = await controller?.handleBridgeIntakeReadyResult(
            BridgeIntakeReadyMethod.Params(
                protocolId: "review",
                streamId: request.streamId,
                reason: request.reason
            )
        )
    }
}

@MainActor
extension BridgePaneController {
    func enqueueTelemetrySessionBootstrapRequest(
        requestId: String,
        reason: BridgeReadyMessageHandler.TelemetrySessionBootstrapReason
    ) async {
        let precedingTransition = telemetrySessionBootstrapTransitionTail
        let transition = Task { @MainActor [weak self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await self?.performTelemetrySessionBootstrapRequest(
                requestId: requestId,
                reason: reason
            )
        }
        telemetrySessionBootstrapTransitionTail = transition
        await transition.value
    }

    private func performTelemetrySessionBootstrapRequest(
        requestId: String,
        reason _: BridgeReadyMessageHandler.TelemetrySessionBootstrapReason
    ) async {
        guard let telemetrySessionOwner, let telemetryRecorder else {
            try? await telemetrySessionBootstrapSink(page, requestId, nil, bridgeWorld)
            return
        }

        let installation: BridgeTelemetrySessionInstallation
        if hasPublishedTelemetrySessionBootstrap {
            do {
                installation = try await telemetrySessionOwner.replace(
                    enabledScopes: [.web],
                    endpointURL: "agentstudio://telemetry/batch",
                    policy: .live,
                    projector: BridgeTelemetryNativeProjector(recorder: telemetryRecorder).project
                )
            } catch {
                try? await telemetrySessionBootstrapSink(page, requestId, nil, bridgeWorld)
                return
            }
        } else {
            installation = await telemetrySessionOwner.installation
        }

        hasPublishedTelemetrySessionBootstrap = true
        do {
            try await telemetrySessionBootstrapSink(
                page,
                requestId,
                installation,
                bridgeWorld
            )
        } catch {
            await telemetrySessionOwner.invalidateActiveSession()
        }
    }

    static func dispatchTelemetrySessionBootstrap(
        page: WebPage,
        requestId: String,
        installation: BridgeTelemetrySessionInstallation?,
        contentWorld: WKContentWorld
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bootstrapJSON: String
        if let installation {
            let data = try encoder.encode(installation.bootstrap)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw BridgeError.encoding("Unable to encode telemetry session bootstrap")
            }
            bootstrapJSON = encoded
        } else {
            bootstrapJSON = "null"
        }
        try await page.callJavaScript(
            """
            document.dispatchEvent(new CustomEvent('__bridge_telemetry_session_bootstrap', {
                detail: {
                    requestId: requestId,
                    result: bootstrapJSON === 'null'
                        ? { kind: 'unavailable', reason: 'disabled' }
                        : { kind: 'available', workerBootstrap: JSON.parse(bootstrapJSON) }
                }
            }));
            """,
            arguments: [
                "requestId": requestId,
                "bootstrapJSON": bootstrapJSON,
            ],
            contentWorld: contentWorld
        )
    }

    func enqueueProductSessionBootstrapRequest(
        requestId: String,
        reason: BridgeReadyMessageHandler.ProductSessionBootstrapReason
    ) async {
        let precedingTransition = productSessionBootstrapTransitionTail
        let transition = Task { @MainActor [weak self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await self?.performProductSessionBootstrapRequest(
                requestId: requestId,
                reason: reason
            )
        }
        productSessionBootstrapTransitionTail = transition
        await transition.value
    }

    private func performProductSessionBootstrapRequest(
        requestId: String,
        reason: BridgeReadyMessageHandler.ProductSessionBootstrapReason
    ) async {
        bridgeProductBootstrapLogger.debug(
            "Preparing product session bootstrap requestId=\(requestId, privacy: .public) reason=\(reason.rawValue, privacy: .public)"
        )
        let installation: BridgeProductSessionInstallation
        if hasPublishedProductSessionBootstrap {
            do {
                let candidate = try await productSessionOwner.prepareCandidate()
                let retirementReason: BridgePaneProductSessionRetirementReason =
                    reason == .workerReplacement ? .workerReplacement : .pageReload
                while await productSessionOwner.retire(reason: retirementReason) != .retired {
                    await Task.yield()
                }
                guard await productSessionOwner.activatePreparedCandidate(candidate) == .activated else {
                    paneState.connection.setHealth(.error)
                    return
                }
                installation = candidate
            } catch BridgePaneProductSessionOwnerError.ownerDisposed {
                return
            } catch {
                bridgeProductBootstrapLogger.error("Bridge product session replacement failed: \(error)")
                paneState.connection.setHealth(.error)
                return
            }
        } else {
            guard let activeInstallation = await productSessionOwner.activeInstallation else {
                paneState.connection.setHealth(.error)
                return
            }
            installation = activeInstallation
        }

        hasPublishedProductSessionBootstrap = true
        do {
            try await productSessionBootstrapSink(
                page,
                requestId,
                installation,
                bridgeWorld
            )
            bridgeProductBootstrapLogger.debug(
                "Delivered product session bootstrap requestId=\(requestId, privacy: .public)"
            )
        } catch {
            bridgeProductBootstrapLogger.error("Bridge product session bootstrap delivery failed: \(error)")
            while await productSessionOwner.retire(reason: .pageReload) != .retired {
                await Task.yield()
            }
            paneState.connection.setHealth(.error)
        }
    }

    static func dispatchProductSessionBootstrap(
        page: WebPage,
        requestId: String,
        installation: BridgeProductSessionInstallation,
        contentWorld: WKContentWorld
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bootstrapData = try encoder.encode(installation.bootstrap)
        let capabilityData = try encoder.encode(installation.capabilityBytes)
        guard let bootstrapJSON = String(data: bootstrapData, encoding: .utf8),
            let capabilityJSON = String(data: capabilityData, encoding: .utf8)
        else {
            throw BridgeError.encoding("Unable to encode product session bootstrap")
        }
        try await page.callJavaScript(
            """
            document.dispatchEvent(new CustomEvent('__bridge_product_session_bootstrap', {
                detail: {
                    requestId: requestId,
                    bootstrap: JSON.parse(bootstrapJSON),
                    productCapability: new Uint8Array(JSON.parse(capabilityJSON)).buffer
                }
            }));
            """,
            arguments: [
                "requestId": requestId,
                "bootstrapJSON": bootstrapJSON,
                "capabilityJSON": capabilityJSON,
            ],
            contentWorld: contentWorld
        )
    }

    func configureRuntimeCallbacks() {
        onRuntimeEvent = { [weak self] event, commandId, correlationId in
            self?.runtime.ingestBridgeEvent(event, commandId: commandId, correlationId: correlationId)
        }
        onRuntimeCommandAck = { [weak self] ack in
            self?.runtime.recordCommandAck(ack)
        }
        runtime.commandHandler = self
    }

    static func makeProductSessionDependencies(
        paneSessionId: String,
        runtime: BridgeRuntime,
        state: BridgePaneState,
        reviewContentStore: BridgeContentStore,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil
    ) -> BridgePaneProductSessionDependencies {
        let committedCallTarget = BridgePaneProductCommittedCallTarget()
        let fileMetadataSource: any BridgePaneProductFileMetadataProducing =
            if let authority = makeProductFileSourceAuthority(
                paneId: UUID(uuidString: paneSessionId),
                runtime: runtime,
                state: state
            ) {
                BridgePaneProductFileMetadataSource(authority: authority)
            } else {
                BridgeUnavailablePaneProductFileMetadataSource()
            }
        let reviewContentSource = BridgePaneProductReviewContentSource(
            contentStore: reviewContentStore
        )
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: fileMetadataSource,
            reviewMetadataSource: BridgePaneProductReviewMetadataSource(
                initialAvailability: .loading
            ),
            reviewContentSource: reviewContentSource,
            markReviewItemViewed: { itemId in
                runtime.paneState.review.markFileViewed(itemId)
            },
            handleReviewIntakeReady: { request in
                await committedCallTarget.applyReviewIntakeReady(request)
            },
            applyActiveViewerModeUpdate: { call in
                await committedCallTarget.applyActiveViewerModeUpdate(call)
            },
            lifecycleTraceRecorder: telemetryRecorder.map(
                BridgeProductMetadataLifecycleTraceRecorder.init(recorder:)
            )
        )
        let installation = makeInitialProductSessionInstallation(
            paneSessionId: paneSessionId,
            provider: provider
        )
        return BridgePaneProductSessionDependencies(
            installation: installation,
            owner: makeProductSessionOwner(
                paneSessionId: paneSessionId,
                provider: provider,
                activeInstallation: installation
            ),
            committedCallTarget: committedCallTarget,
            productProvider: provider
        )
    }

    private static func makeProductFileSourceAuthority(
        paneId: UUID?,
        runtime: BridgeRuntime,
        state: BridgePaneState
    ) -> BridgePaneProductFileSourceAuthority? {
        guard let paneId,
            let repoId = runtime.metadata.repoId,
            let worktreeId = runtime.metadata.worktreeId,
            let rootURL = worktreeFileBootstrapRootURL(
                metadata: runtime.metadata,
                source: state.source
            )
        else { return nil }
        return BridgePaneProductFileSourceAuthority(
            paneId: paneId,
            worktree: Worktree(
                id: worktreeId,
                repoId: repoId,
                name: runtime.metadata.worktreeName ?? rootURL.lastPathComponent,
                path: rootURL
            )
        )
    }

    nonisolated static func makeInitialProductSessionInstallation(
        paneSessionId: String,
        provider: any BridgeProductSchemeProvider
    ) -> BridgeProductSessionInstallation {
        do {
            return try .make(paneSessionId: paneSessionId, provider: provider)
        } catch {
            preconditionFailure("Bridge product capability generation failed: \(error)")
        }
    }

    nonisolated static func makeProductSessionOwner(
        paneSessionId: String,
        provider: any BridgeProductSchemeProvider,
        activeInstallation: BridgeProductSessionInstallation
    ) -> BridgePaneProductSessionOwner {
        do {
            return try BridgePaneProductSessionOwner(
                paneSessionId: paneSessionId,
                provider: provider,
                activeInstallation: activeInstallation
            )
        } catch {
            preconditionFailure("Bridge product session owner construction failed: \(error)")
        }
    }

    static func registerAgentStudioSchemeHandler(
        in config: inout WebPage.Configuration,
        input: BridgeSchemeHandlerRegistrationInput
    ) {
        guard let scheme = URLScheme("agentstudio") else { return }
        config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(
            paneId: input.paneId,
            contentStore: input.reviewContentStore,
            resourceLeaseRegistry: input.resourceLeaseRegistry,
            allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds,
            telemetryRecorder: input.telemetryRecorder,
            telemetrySessionOwner: input.telemetrySessionOwner,
            productSessionRouter: input.productSessionRouter
        )
        _ = input.productSessionOwner
    }

    nonisolated static func makeTelemetrySessionDependencies(
        scopeGate: BridgeTelemetryScopeGate,
        recorder: (any BridgePerformanceTraceRecording)?
    ) -> BridgePaneTelemetrySessionDependencies? {
        guard scopeGate.isEnabled(.web), let recorder else { return nil }
        do {
            let projector = BridgeTelemetryNativeProjector(recorder: recorder)
            let installation = try BridgeTelemetrySessionInstallation.make(
                enabledScopes: [.web],
                endpointURL: "agentstudio://telemetry/batch",
                policy: .live,
                projector: projector.project
            )
            return BridgePaneTelemetrySessionDependencies(
                installation: installation,
                owner: BridgePaneTelemetrySessionOwner(initialInstallation: installation)
            )
        } catch {
            bridgeProductBootstrapLogger.error("Bridge telemetry session creation failed: \(error)")
            return nil
        }
    }

    nonisolated static func resolveTelemetryDependencies(
        traceRuntime: AgentStudioTraceRuntime?,
        telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy,
        telemetryScopeGate: BridgeTelemetryScopeGate?,
        telemetryRecorder: (any BridgePerformanceTraceRecording)?,
        telemetrySessionDependencies: BridgePaneTelemetrySessionDependencies?
    ) -> (
        scopeGate: BridgeTelemetryScopeGate,
        recorder: (any BridgePerformanceTraceRecording)?,
        sessionDependencies: BridgePaneTelemetrySessionDependencies?
    ) {
        guard telemetryRuntimePolicy.allowsTelemetry else {
            return (BridgeTelemetryScopeGate(enabledScopes: []), nil, telemetrySessionDependencies)
        }

        let resolvedScopeGate = telemetryScopeGate ?? BridgeTelemetryScopeGate(traceRuntime: traceRuntime)
        let resolvedRecorder =
            telemetryRecorder
            ?? (resolvedScopeGate.isEnabled ? BridgePerformanceTraceRecorder(traceRuntime: traceRuntime) : nil)
        let resolvedSessionDependencies =
            telemetrySessionDependencies
            ?? makeTelemetrySessionDependencies(scopeGate: resolvedScopeGate, recorder: resolvedRecorder)
        return (resolvedScopeGate, resolvedRecorder, resolvedSessionDependencies)
    }

    nonisolated static func resolveIntakeFrameSink(
        preEncodedIntakeFrameSink: @escaping @MainActor (WebPage, PreEncodedIntakeFrame) async throws -> Void,
        rawIntakeFrameSink: (@MainActor (WebPage, String, String) async throws -> Void)?
    ) -> @MainActor (WebPage, PreEncodedIntakeFrame) async throws -> Void {
        guard let rawIntakeFrameSink else { return preEncodedIntakeFrameSink }
        return { page, frame in
            try await rawIntakeFrameSink(page, frame.envelopeJSON, frame.pushNonce)
        }
    }

    static func makeBootstrapScript(_ input: BridgeBootstrapScriptInput) -> WKUserScript {
        WKUserScript(
            source: BridgeBootstrap.generateScript(
                bridgeNonce: input.bridgeNonce,
                pushNonce: input.pushNonce,
                appProtocol: Self.bridgeAppProtocol(for: input.panelKind),
                reviewPaneId: input.reviewPaneId,
                reviewStreamId: input.reviewStreamId,
                telemetryConfig: input.telemetryConfig
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: input.bridgeWorld
        )
    }

    static func makeBootstrapArtifacts(
        paneId: UUID,
        state: BridgePaneState,
        telemetryScopeGate: BridgeTelemetryScopeGate,
        bridgeWorld: WKContentWorld
    ) -> BridgeBootstrapArtifacts {
        let bridgeNonce = UUID().uuidString
        let pushNonce = UUID().uuidString
        let reviewPaneId = paneId.uuidString
        let reviewStreamId = "review:\(reviewPaneId)"
        let webTelemetryScopes = telemetryScopeGate.browserExposedScopes
        let telemetryConfig: BridgeTelemetryBootstrapConfig?
        if webTelemetryScopes.isEmpty {
            telemetryConfig = nil
        } else {
            // Anchor the cold `time_to_first_interaction` measurement: capture the native
            // viewer-open wall-clock epoch (pane creation precedes WebView navigation) and a
            // root trace context, both threaded to the browser via the handshake config.
            let viewerOpenEpochUnixMillis = Int(Date().timeIntervalSince1970 * 1000)
            let viewerOpenTraceparent = BridgeTraceContextFactory.live.makeRootContext()?.traceparent
            telemetryConfig = BridgeTelemetryBootstrapConfig.enabled(
                scopes: webTelemetryScopes,
                scenario: BridgeTelemetryBootstrapConfig.packageApplyContentFetchScenario,
                viewerOpenEpochUnixMillis: viewerOpenEpochUnixMillis,
                viewerOpenTraceparent: viewerOpenTraceparent
            )
        }
        let script = makeBootstrapScript(
            BridgeBootstrapScriptInput(
                bridgeNonce: bridgeNonce,
                pushNonce: pushNonce,
                reviewPaneId: reviewPaneId,
                reviewStreamId: reviewStreamId,
                panelKind: state.panelKind,
                telemetryConfig: telemetryConfig,
                bridgeWorld: bridgeWorld
            )
        )
        return BridgeBootstrapArtifacts(pushNonce: pushNonce, script: script)
    }

    private static func bridgeAppProtocol(for panelKind: BridgePanelKind) -> String {
        switch panelKind {
        case .diffViewer:
            "review"
        case .fileViewer:
            "worktree-file"
        }
    }

    static func installInitialUserScripts(
        in userContentController: WKUserContentController,
        bootstrapScript: WKUserScript,
        managementScript: WKUserScript
    ) {
        userContentController.addUserScript(bootstrapScript)
        #if DEBUG
            userContentController.addUserScript(Self.makePageDiagnosticsProbeScript())
        #endif
        userContentController.addUserScript(managementScript)
    }

    static func worktreeFileBootstrapRootURL(
        metadata: PaneMetadata,
        source: BridgePaneSource?
    ) -> URL? {
        if case .workspace(let rootPath, _)? = source {
            return URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        }
        return metadata.cwd?.standardizedFileURL.resolvingSymlinksInPath()
    }
}
