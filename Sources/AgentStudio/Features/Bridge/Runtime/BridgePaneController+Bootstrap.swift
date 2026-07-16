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
        _ contentWorld: WKContentWorld,
        _ productAdmission: BridgeProductAdmissionContext
    ) async throws -> Void

typealias BridgeTelemetrySessionBootstrapSink =
    @MainActor (
        _ page: WebPage,
        _ requestId: String,
        _ installation: BridgeTelemetrySessionInstallation?,
        _ contentWorld: WKContentWorld
    ) async throws -> Void

struct BridgeBootstrapScriptInput {
    let reviewPaneId: String
    let reviewStreamId: String
    let panelKind: BridgePanelKind
    let telemetryConfig: BridgeTelemetryBootstrapConfig?
    let bridgeWorld: WKContentWorld
}

struct BridgeBootstrapArtifacts {
    let script: WKUserScript
}

struct BridgeSchemeHandlerRegistrationInput {
    let paneId: UUID
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
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

    func applyActiveViewerModeUpdate(
        _ call: BridgeProductCallRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
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
            activeSource: activeSource,
            productAdmission: productAdmission
        )
    }

    func applyReviewIntakeReady(
        _ request: BridgeProductReviewIntakeReadyRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        await controller?.handleCommittedProductReviewIntakeReady(
            request,
            productAdmission: productAdmission
        )
    }
}

@MainActor
extension BridgePaneController {
    func handleCommittedProductReviewIntakeReady(
        _ request: BridgeProductReviewIntakeReadyRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        let currentStreamId = reviewProtocolStreamId()
        guard request.streamId == currentStreamId else {
            await recordReviewIntakeReadyTelemetry(phase: "dropped")
            return
        }
        await recordReviewIntakeReadyTelemetry(phase: "accepted")
        _ = productAdmission.withValidAdmission {
            if let package = paneState.diff.packageMetadata {
                setActiveViewerModeAcceptedSignalForExplicitReviewRequestWithoutAdmissionCheck(
                    streamId: currentStreamId,
                    generation: package.reviewGeneration.rawValue
                )
            } else {
                clearActiveViewerModeAcceptedSignalForExplicitReviewRequestWithoutAdmissionCheck()
            }
            if paneState.diff.packageMetadata == nil {
                scheduleInitialReviewPackageLoadIfPossible(reason: .initialIntake)
            } else if request.reason == "sequence_gap" {
                scheduleReviewPackageReloadForProductResync(reason: .productResync)
            }
        }
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
        guard let productAdmission = productAdmissionGate.acquire() else { return }
        let precedingTransition = productSessionBootstrapTransitionTail
        let transition = Task { @MainActor [weak self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await self?.performProductSessionBootstrapRequest(
                requestId: requestId,
                reason: reason,
                productAdmission: productAdmission
            )
        }
        productSessionBootstrapTransitionTail = transition
        await transition.value
    }

    private func performProductSessionBootstrapRequest(
        requestId: String,
        reason: BridgeReadyMessageHandler.ProductSessionBootstrapReason,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        bridgeProductBootstrapLogger.debug(
            "Preparing product session bootstrap requestId=\(requestId, privacy: .public) reason=\(reason.rawValue, privacy: .public)"
        )
        let installation: BridgeProductSessionInstallation
        if hasPublishedProductSessionBootstrap {
            do {
                let candidate = try await productSessionOwner.prepareCandidate(
                    productAdmission: productAdmission
                )
                let retirementReason: BridgePaneProductSessionRetirementReason =
                    reason == .workerReplacement ? .workerReplacement : .pageReload
                while await productSessionOwner.retire(reason: retirementReason) != .retired {
                    guard (productAdmission.withValidAdmission { true }) == true else { return }
                    await Task.yield()
                }
                guard
                    await productSessionOwner.activatePreparedCandidate(
                        candidate,
                        productAdmission: productAdmission
                    ) == .activated
                else {
                    setProductBootstrapConnectionErrorIfAdmitted(productAdmission)
                    return
                }
                installation = candidate
            } catch BridgePaneProductSessionOwnerError.ownerDisposed {
                return
            } catch {
                bridgeProductBootstrapLogger.error("Bridge product session replacement failed: \(error)")
                setProductBootstrapConnectionErrorIfAdmitted(productAdmission)
                return
            }
        } else {
            guard let activeInstallation = await productSessionOwner.activeInstallation else {
                setProductBootstrapConnectionErrorIfAdmitted(productAdmission)
                return
            }
            guard (productAdmission.withValidAdmission { true }) == true else { return }
            installation = activeInstallation
        }

        guard
            (productAdmission.withValidAdmission {
                hasPublishedProductSessionBootstrap = true
                return true
            }) == true
        else { return }
        do {
            try await productSessionBootstrapSink(
                page,
                requestId,
                installation,
                bridgeWorld,
                productAdmission
            )
            bridgeProductBootstrapLogger.debug(
                "Delivered product session bootstrap requestId=\(requestId, privacy: .public)"
            )
        } catch {
            bridgeProductBootstrapLogger.error("Bridge product session bootstrap delivery failed: \(error)")
            guard (productAdmission.withValidAdmission { true }) == true else { return }
            while await productSessionOwner.retire(reason: .pageReload) != .retired {
                guard (productAdmission.withValidAdmission { true }) == true else { return }
                await Task.yield()
            }
            setProductBootstrapConnectionErrorIfAdmitted(productAdmission)
        }
    }

    private func setProductBootstrapConnectionErrorIfAdmitted(
        _ productAdmission: BridgeProductAdmissionContext
    ) {
        _ = productAdmission.withValidAdmission {
            paneState.connection.setHealth(.error)
        }
    }

    static func dispatchProductSessionBootstrap(
        page: WebPage,
        requestId: String,
        installation: BridgeProductSessionInstallation,
        contentWorld: WKContentWorld,
        productAdmission: BridgeProductAdmissionContext
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
        guard (productAdmission.withValidAdmission { true }) == true else {
            throw CancellationError()
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
        guard (productAdmission.withValidAdmission { true }) == true else {
            throw CancellationError()
        }
    }

    func configureRuntimeCallbacks() {
        onRuntimeEvent = { [weak self] event, commandId, correlationId in
            self?.runtime.ingestBridgeEvent(event, commandId: commandId, correlationId: correlationId)
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
        let productAdmissionGate = BridgeProductAdmissionGate()
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
            markReviewItemViewed: { itemId, productAdmission in
                _ = productAdmission.withValidAdmission {
                    runtime.paneState.review.markFileViewed(itemId)
                }
            },
            handleReviewIntakeReady: { request, productAdmission in
                await committedCallTarget.applyReviewIntakeReady(
                    request,
                    productAdmission: productAdmission
                )
            },
            applyActiveViewerModeUpdate: { call, productAdmission in
                await committedCallTarget.applyActiveViewerModeUpdate(
                    call,
                    productAdmission: productAdmission
                )
            },
            lifecycleTraceRecorder: telemetryRecorder.map(
                BridgeProductMetadataLifecycleTraceRecorder.init(recorder:)
            )
        )
        let installation = makeInitialProductSessionInstallation(
            paneSessionId: paneSessionId,
            provider: provider,
            productAdmissionGate: productAdmissionGate
        )
        return BridgePaneProductSessionDependencies(
            installation: installation,
            owner: makeProductSessionOwner(
                paneSessionId: paneSessionId,
                provider: provider,
                productAdmissionGate: productAdmissionGate,
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
        provider: any BridgeProductSchemeProvider,
        productAdmissionGate: BridgeProductAdmissionGate
    ) -> BridgeProductSessionInstallation {
        do {
            return try .make(
                paneSessionId: paneSessionId,
                provider: provider,
                productAdmissionGate: productAdmissionGate
            )
        } catch {
            preconditionFailure("Bridge product capability generation failed: \(error)")
        }
    }

    nonisolated static func makeProductSessionOwner(
        paneSessionId: String,
        provider: any BridgeProductSchemeProvider,
        productAdmissionGate: BridgeProductAdmissionGate,
        activeInstallation: BridgeProductSessionInstallation
    ) -> BridgePaneProductSessionOwner {
        do {
            return try BridgePaneProductSessionOwner(
                paneSessionId: paneSessionId,
                provider: provider,
                productAdmissionGate: productAdmissionGate,
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
            telemetrySessionOwner: input.telemetrySessionOwner,
            productSessionRouter: input.productSessionRouter
        )
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

    static func makeBootstrapScript(_ input: BridgeBootstrapScriptInput) -> WKUserScript {
        WKUserScript(
            source: BridgeBootstrap.generateScript(
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
                reviewPaneId: reviewPaneId,
                reviewStreamId: reviewStreamId,
                panelKind: state.panelKind,
                telemetryConfig: telemetryConfig,
                bridgeWorld: bridgeWorld
            )
        )
        return BridgeBootstrapArtifacts(script: script)
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
