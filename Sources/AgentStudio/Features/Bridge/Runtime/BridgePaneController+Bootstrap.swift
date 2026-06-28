import Foundation
import WebKit

struct BridgeBootstrapScriptInput {
    let bridgeNonce: String
    let pushNonce: String
    let reviewPaneId: String
    let reviewStreamId: String
    let worktreeFileSourceSpec: BridgeWorktreeFileSurfaceSourceSpec?
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
    let reviewResourceStore: BridgeReviewResourceStore
    let worktreeFileResourceStore: BridgeWorktreeFileResourceStore
    let resourceLeaseRegistry: BridgeTransportResourceLeaseRegistry
    let telemetryRecorder: (any BridgePerformanceTraceRecording)?
}

@MainActor
extension BridgePaneController {
    static func registerAgentStudioSchemeHandler(
        in config: inout WebPage.Configuration,
        input: BridgeSchemeHandlerRegistrationInput
    ) {
        guard let scheme = URLScheme("agentstudio") else { return }
        config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(
            paneId: input.paneId,
            contentStore: input.reviewContentStore,
            reviewResourceStore: input.reviewResourceStore,
            worktreeFileResourceStore: input.worktreeFileResourceStore,
            resourceLeaseRegistry: input.resourceLeaseRegistry,
            allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds,
            telemetryRecorder: input.telemetryRecorder
        )
    }

    nonisolated static func resolveTelemetryDependencies(
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

    static func makeBootstrapScript(_ input: BridgeBootstrapScriptInput) -> WKUserScript {
        WKUserScript(
            source: BridgeBootstrap.generateScript(
                bridgeNonce: input.bridgeNonce,
                pushNonce: input.pushNonce,
                reviewPaneId: input.reviewPaneId,
                reviewStreamId: input.reviewStreamId,
                worktreeFileSourceSpec: input.worktreeFileSourceSpec,
                telemetryConfig: input.telemetryConfig
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: input.bridgeWorld
        )
    }

    static func makeBootstrapArtifacts(
        paneId: UUID,
        metadata: PaneMetadata,
        source: BridgePaneSource?,
        telemetryScopeGate: BridgeTelemetryScopeGate,
        bridgeWorld: WKContentWorld
    ) -> BridgeBootstrapArtifacts {
        let bridgeNonce = UUID().uuidString
        let pushNonce = UUID().uuidString
        let reviewPaneId = paneId.uuidString
        let reviewStreamId = "review:\(reviewPaneId)"
        let webTelemetryScopes = telemetryScopeGate.browserExposedScopes
        let telemetryConfig =
            !webTelemetryScopes.isEmpty
            ? BridgeTelemetryBootstrapConfig.enabled(
                scopes: webTelemetryScopes,
                scenario: BridgeTelemetryBootstrapConfig.packageApplyContentFetchScenario
            )
            : nil
        let script = makeBootstrapScript(
            BridgeBootstrapScriptInput(
                bridgeNonce: bridgeNonce,
                pushNonce: pushNonce,
                reviewPaneId: reviewPaneId,
                reviewStreamId: reviewStreamId,
                worktreeFileSourceSpec: makeWorktreeFileBootstrapSourceSpec(
                    paneId: paneId,
                    metadata: metadata,
                    source: source
                ),
                telemetryConfig: telemetryConfig,
                bridgeWorld: bridgeWorld
            )
        )
        return BridgeBootstrapArtifacts(pushNonce: pushNonce, script: script)
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

    static func makeWorktreeFileBootstrapSourceSpec(
        paneId: UUID,
        metadata: PaneMetadata,
        source: BridgePaneSource?
    ) -> BridgeWorktreeFileSurfaceSourceSpec? {
        guard let repoId = metadata.repoId,
            let worktreeId = metadata.worktreeId,
            let rootURL = worktreeFileBootstrapRootURL(metadata: metadata, source: source)
        else {
            return nil
        }
        return BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "bootstrap:\(paneId.uuidString)",
            repoId: repoId,
            worktreeId: worktreeId,
            rootPathToken: StableKey.fromPath(rootURL),
            cwdScope: nil,
            pathScope: [],
            includeStatuses: true,
            includeFileDescriptors: true,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )
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
