import Foundation
import Testing

@Suite("Bridge hard-cut static negatives")
struct BridgeHardCutStaticNegativeTests {
    @Test("detects canonical and alternate legacy spellings without embedding scanner targets")
    func detectsCanonicalAndAlternateLegacySpellings() {
        let intakeEvent = bridgeHardCutJoin("__bridge_", "intake_", "json")
        let productEnvelopeRelay = bridgeHardCutJoin("applyEnvelope", "JSON")
        let leasedReply = bridgeHardCutJoin("startLeasedResource", "ReplyTask")
        let intakeReadyMethod = bridgeHardCutJoin("BridgeIntake", "ReadyMethod")
        let controllerPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Runtime", "BridgePaneController.swift")
        let schemeHandlerPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Transport", "BridgeSchemeHandler.swift")
        let supportPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Runtime", "BridgePaneControllerSupport.swift")

        let canonicalSources = [
            controllerPath: bridgeHardCutJoin(
                "window.__bridgeInternal.", productEnvelopeRelay, "(payload); ",
                "new CustomEvent('", intakeEvent, "')"),
            schemeHandlerPath: bridgeHardCutJoin(leasedReply, "(resource: resource)"),
            supportPath: bridgeHardCutJoin("enum ", intakeReadyMethod, " {}"),
        ]
        let alternateSources = [
            controllerPath: bridgeHardCutJoin(
                "window.__bridgeInternal.\n  ", productEnvelopeRelay, " \n ( payload ); ",
                "new CustomEvent(\n\"", intakeEvent, "\"\n)"),
            schemeHandlerPath: bridgeHardCutJoin(leasedReply, " \n ( resource: resource )"),
            supportPath: bridgeHardCutJoin("enum\n", intakeReadyMethod, "\n{}"),
        ]

        let canonicalIdentities = bridgeHardCutViolations(in: canonicalSources).map(\.identity)
        let alternateIdentities = bridgeHardCutViolations(in: alternateSources).map(\.identity)
        let expectedIdentities = [
            "product-dom-egress:\(controllerPath)",
            "feature-resource-get:\(schemeHandlerPath)",
            "native-review-publication:\(supportPath)",
        ]

        for expectedIdentity in expectedIdentities {
            #expect(canonicalIdentities.contains(expectedIdentity))
            #expect(alternateIdentities.contains(expectedIdentity))
        }
    }

    @Test("permits bootstrap, typed controls, and diagnostic read-only ingress")
    func permitsBootstrapTypedControlsAndDiagnosticReadOnlyIngress() {
        let readyHandlerPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Transport", "BridgeReadyMessageHandler.swift")
        let schemeHandlerPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Transport", "BridgeSchemeHandler.swift")
        let ipcProjectionPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Runtime", "BridgePaneController+IPCProjection.swift")
        let bootstrapPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Runtime", "BridgePaneController+Bootstrap.swift")
        let telemetrySidecarPath = bridgeHardCutSourcePath(
            "Sources", "AgentStudio", "Features", "Bridge", "Runtime", "BridgePaneController+TelemetrySidecar.swift")
        let allowedSources = [
            readyHandlerPath: bridgeHardCutJoin(
                "final class BridgeReadyMessageHandler: NSObject, WKScriptMessageHandler { ",
                "case productSessionBootstrap; case telemetrySessionBootstrap }"),
            schemeHandlerPath: "startProductReplyTask(request: request, continuation: continuation)",
            ipcProjectionPath: "let result = try await page.callJavaScript(Self.renderStateJavaScript)",
            bootstrapPath: "document.dispatchEvent(new CustomEvent('__bridge_product_session_bootstrap'))",
            telemetrySidecarPath: "return JSON.stringify(await control[action]())",
        ]

        #expect(bridgeHardCutViolations(in: allowedSources).isEmpty)
    }

    @Test("has no named legacy native product owners after atomic A0 hard cut")
    func hasNoNamedLegacyNativeProductOwnersAfterAtomicHardCut() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let violations = try bridgeHardCutViolations(projectRoot: projectRoot)
        let formattedViolations = violations.map(\.formatted).joined(separator: "\n")

        #expect(
            violations.isEmpty,
            "Named native legacy owners remain:\n\(formattedViolations)"
        )
    }
}

private enum BridgeHardCutOwnerGroup: String, Sendable {
    case featureResourceGet = "feature-resource-get"
    case legacyTelemetryTransport = "legacy-telemetry-transport"
    case nativeReviewPublication = "native-review-publication"
    case productDOMEgress = "product-dom-egress"
    case scriptMessageProductIngress = "script-message-product-ingress"
}

private struct BridgeHardCutOwnerRule: Sendable {
    enum Detection: Sendable {
        case ownerFile
        case sourceSignatures([String])
    }

    let description: String
    let detection: Detection
    let group: BridgeHardCutOwnerGroup
    let relativePath: String
}

private struct BridgeHardCutViolation: Equatable, Sendable {
    let description: String
    let group: BridgeHardCutOwnerGroup
    let relativePath: String

    var identity: String {
        "\(group.rawValue):\(relativePath)"
    }

    var formatted: String {
        "\(group.rawValue) :: \(relativePath) :: \(description)"
    }
}

private func bridgeHardCutOwnerRules() -> [BridgeHardCutOwnerRule] {
    bridgeHardCutNativeReviewPublicationRules()
        + bridgeHardCutFeatureResourceRules()
        + bridgeHardCutProductIngressAndEgressRules()
        + bridgeHardCutLegacyTelemetryRules()
}

private func bridgeHardCutNativeReviewPublicationRules() -> [BridgeHardCutOwnerRule] {
    let runtimeRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Runtime"]
    let reviewProtocolRuntimeRoot = runtimeRoot + ["ReviewProtocol"]
    let reviewProtocolModelRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Models", "ReviewProtocol"]
    let diffCommandsPath = bridgeHardCutSourcePath(
        runtimeRoot + [bridgeHardCutJoin("BridgePaneController+", "DiffCommands.swift")])
    let supportPath = bridgeHardCutSourcePath(runtimeRoot + ["BridgePaneControllerSupport.swift"])

    return [
        bridgeHardCutOwnerFileRule(
            .featureResourceGet,
            bridgeHardCutSourcePath(
                "Sources", "AgentStudio", "App", "Boot", "AppDelegate+BridgeWorkerFetchStartupDiagnostics.swift"),
            "legacy worker feature-resource GET startup diagnostic"),
        bridgeHardCutOwnerFileRule(
            .featureResourceGet,
            bridgeHardCutSourcePath(
                "Sources", "AgentStudio", "Features", "Bridge", "Models", "Transport",
                "BridgeResourceDescriptor.swift"),
            "generic feature-resource URL descriptor model"),
        bridgeHardCutOwnerFileRule(
            .nativeReviewPublication,
            bridgeHardCutSourcePath(
                runtimeRoot + [bridgeHardCutJoin("BridgePaneController+", "ReviewProtocolResources.swift")]),
            "native dual Review frame publication and intake delivery owner"),
        bridgeHardCutOwnerFileRule(
            .nativeReviewPublication,
            bridgeHardCutSourcePath(
                runtimeRoot + [bridgeHardCutJoin("BridgePaneController+", "ReviewMetadataInterest.swift")]),
            "native legacy Review metadata-interest page command owner"),
        bridgeHardCutOwnerFileRule(
            .nativeReviewPublication,
            bridgeHardCutSourcePath(reviewProtocolRuntimeRoot + ["BridgeReviewProtocolFrameBuilder.swift"]),
            "native legacy Review intake frame builder"),
        bridgeHardCutOwnerFileRule(
            .nativeReviewPublication,
            bridgeHardCutSourcePath(reviewProtocolModelRoot + ["BridgeReviewProtocolFrame.swift"]),
            "native legacy Review intake frame model"),
        bridgeHardCutSourceRule(
            .nativeReviewPublication,
            diffCommandsPath,
            "native legacy Review resource-lease activation",
            [bridgeHardCutCallSignature(bridgeHardCutJoin("activateReviewContent", "Handles"))]),
        bridgeHardCutSourceRule(
            .nativeReviewPublication,
            diffCommandsPath,
            "native intake-ready Review package replay",
            [bridgeHardCutCallSignature(bridgeHardCutJoin("scheduleReviewPackageReload", "ForIntakeAnnounce"))]),
        bridgeHardCutSourceRule(
            .nativeReviewPublication,
            supportPath,
            "native legacy intake-ready command contract",
            [bridgeHardCutJoin("BridgeIntake", "ReadyMethod")]),
    ]
}

private func bridgeHardCutFeatureResourceRules() -> [BridgeHardCutOwnerRule] {
    let runtimeRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Runtime"]
    let transportRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Transport"]
    let reviewFoundationRuntimeRoot = runtimeRoot + ["ReviewFoundation"]
    let schemeHandlerPath = bridgeHardCutSourcePath(transportRoot + ["BridgeSchemeHandler.swift"])

    return [
        bridgeHardCutOwnerFileRule(
            .featureResourceGet,
            bridgeHardCutSourcePath(transportRoot + ["BridgeTransportResourceLeaseRegistry.swift"]),
            "native feature resource GET lease authority"),
        bridgeHardCutOwnerFileRule(
            .featureResourceGet,
            bridgeHardCutSourcePath(transportRoot + ["BridgeTransportResourceURL.swift"]),
            "native feature resource GET URL authority"),
        bridgeHardCutOwnerFileRule(
            .featureResourceGet,
            bridgeHardCutSourcePath(
                "Sources", "AgentStudio", "Features", "Bridge", "Models", "Transport",
                "BridgeResourceProtocolRegistry.swift"),
            "native feature-resource protocol allowlist"),
        bridgeHardCutOwnerFileRule(
            .featureResourceGet,
            bridgeHardCutSourcePath(reviewFoundationRuntimeRoot + ["BridgeContentHandleIdentity.swift"]),
            "native Review content resource URL builder"),
        bridgeHardCutSourceRule(
            .featureResourceGet,
            schemeHandlerPath,
            "native leased Review resource GET route",
            [
                bridgeHardCutCallSignature(bridgeHardCutJoin("startLeasedResource", "ReplyTask")),
                bridgeHardCutCallSignature(bridgeHardCutJoin("routeLeasedResource", "Reply")),
            ]),
    ]
}

private func bridgeHardCutProductIngressAndEgressRules() -> [BridgeHardCutOwnerRule] {
    bridgeHardCutProductEgressRules() + bridgeHardCutScriptMessageProductIngressRules()
}

private func bridgeHardCutProductEgressRules() -> [BridgeHardCutOwnerRule] {
    let runtimeRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Runtime"]
    let transportRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Transport"]
    let controllerPath = bridgeHardCutSourcePath(runtimeRoot + ["BridgePaneController.swift"])
    let bootstrapPath = bridgeHardCutSourcePath(transportRoot + ["BridgeBootstrap.swift"])
    let bridgeWebBridgeRoot = ["BridgeWeb", "src", "bridge"]
    let pushStateRoot = ["Sources", "AgentStudio", "Features", "Bridge", "State", "Push"]

    return [
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(bridgeWebBridgeRoot + ["bridge-push-envelope.ts"]),
            "page-owned legacy product push envelope model"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(bridgeWebBridgeRoot + ["bridge-push-receiver.ts"]),
            "page-owned legacy product push receiver"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(
                runtimeRoot + [bridgeHardCutJoin("BridgePaneController+", "PushTransport.swift")]),
            "native main-to-page product push and intake transport"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(runtimeRoot + [bridgeHardCutJoin("BridgePaneController+", "PushPlans.swift")]),
            "native main-owned product page-push plans"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(runtimeRoot + ["BridgeMetadataLaneScheduler.swift"]),
            "native legacy metadata intake scheduler"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(runtimeRoot + ["BridgePushEnvelopeEncoder.swift"]),
            "native legacy push-envelope encoder"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(runtimeRoot + ["PreEncodedIntakeFrame.swift"]),
            "native legacy intake-frame carrier"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(pushStateRoot + ["EntitySlice.swift"]),
            "native legacy entity push projection"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(pushStateRoot + ["PushPlan.swift"]),
            "native legacy page-push plan"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(pushStateRoot + ["PushSnapshots.swift"]),
            "native legacy page-push snapshots"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(pushStateRoot + ["PushTransport.swift"]),
            "native legacy page-push transport contract"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(pushStateRoot + ["RevisionClock.swift"]),
            "native legacy page-push revision clock"),
        bridgeHardCutOwnerFileRule(
            .productDOMEgress,
            bridgeHardCutSourcePath(pushStateRoot + ["Slice.swift"]),
            "native legacy page-push slice projection"),
        bridgeHardCutSourceRule(
            .productDOMEgress,
            controllerPath,
            "native product callJavaScript and DOM relay",
            [
                bridgeHardCutCallSignature(bridgeHardCutJoin("applyEnvelope", "JSON")),
                bridgeHardCutQuotedSignature(bridgeHardCutJoin("__bridge_", "intake_", "json")),
            ]),
        bridgeHardCutSourceRule(
            .productDOMEgress,
            bootstrapPath,
            "bridge-world product push and intake page relay",
            [
                bridgeHardCutJoin("applyEnvelope", "JSON"),
                bridgeHardCutJoin("applyIntakeFrame", "JSON"),
                bridgeHardCutJoin("PUSH", "_NONCE"),
                bridgeHardCutJoin("push", "Nonce"),
            ]),
    ]
}

private func bridgeHardCutScriptMessageProductIngressRules() -> [BridgeHardCutOwnerRule] {
    let runtimeRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Runtime"]
    let transportRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Transport"]
    let readyHandlerPath = bridgeHardCutSourcePath(transportRoot + ["BridgeReadyMessageHandler.swift"])

    return [
        bridgeHardCutOwnerFileRule(
            .scriptMessageProductIngress,
            bridgeHardCutSourcePath(runtimeRoot + ["BridgePaneController+SchemeCommandDispatch.swift"]),
            "legacy generic scheme-command compatibility owner"),
        bridgeHardCutOwnerFileRule(
            .scriptMessageProductIngress,
            bridgeHardCutSourcePath(transportRoot + ["BridgeSchemeCommandDispatcher.swift"]),
            "legacy generic scheme-command dispatcher"),
        bridgeHardCutOwnerFileRule(
            .scriptMessageProductIngress,
            bridgeHardCutSourcePath(transportRoot + ["RPCMethod.swift"]),
            "legacy generic scheme-command method abstraction"),
        bridgeHardCutOwnerFileRule(
            .scriptMessageProductIngress,
            bridgeHardCutSourcePath(transportRoot + [bridgeHardCutJoin("RPCMessage", "Handler.swift")]),
            "post-bootstrap script-message product ingress"),
        bridgeHardCutOwnerFileRule(
            .scriptMessageProductIngress,
            bridgeHardCutSourcePath(transportRoot + [bridgeHardCutJoin("RPC", "Router.swift")]),
            "post-bootstrap script-message product router"),
        bridgeHardCutSourceRule(
            .scriptMessageProductIngress,
            readyHandlerPath,
            "non-bootstrap command accepted by the script-message handler",
            [
                bridgeHardCutJoin("__bridge_", "command"),
                bridgeHardCutJoin("BridgeIntake", "ReadyMethod"),
            ]),
    ]
}

private func bridgeHardCutLegacyTelemetryRules() -> [BridgeHardCutOwnerRule] {
    let runtimeRoot = ["Sources", "AgentStudio", "Features", "Bridge", "Runtime"]

    return [
        bridgeHardCutOwnerFileRule(
            .legacyTelemetryTransport,
            bridgeHardCutSourcePath(
                ["Sources", "AgentStudio", "Features", "Bridge", "Models", "Telemetry", "BridgeTelemetryBatch.swift"]),
            "legacy native telemetry batch transport model"),
        bridgeHardCutOwnerFileRule(
            .legacyTelemetryTransport,
            bridgeHardCutSourcePath(runtimeRoot + ["Telemetry", "BridgeTelemetryQueue.swift"]),
            "legacy native telemetry queue"),
        bridgeHardCutOwnerFileRule(
            .legacyTelemetryTransport,
            bridgeHardCutSourcePath(runtimeRoot + ["Telemetry", "BridgeTelemetryIngestor.swift"]),
            "legacy native telemetry batch ingestor"),
    ]
}

private func bridgeHardCutOwnerFileRule(
    _ group: BridgeHardCutOwnerGroup,
    _ relativePath: String,
    _ description: String
) -> BridgeHardCutOwnerRule {
    BridgeHardCutOwnerRule(
        description: description,
        detection: .ownerFile,
        group: group,
        relativePath: relativePath
    )
}

private func bridgeHardCutSourceRule(
    _ group: BridgeHardCutOwnerGroup,
    _ relativePath: String,
    _ description: String,
    _ signatures: [String]
) -> BridgeHardCutOwnerRule {
    BridgeHardCutOwnerRule(
        description: description,
        detection: .sourceSignatures(signatures),
        group: group,
        relativePath: relativePath
    )
}

private func bridgeHardCutViolations(projectRoot: URL) throws -> [BridgeHardCutViolation] {
    var violations: [BridgeHardCutViolation] = []
    for rule in bridgeHardCutOwnerRules() {
        let sourceURL = projectRoot.appending(path: rule.relativePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
        switch rule.detection {
        case .ownerFile:
            violations.append(bridgeHardCutViolation(for: rule))
        case .sourceSignatures(let signatures):
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            if bridgeHardCutSourceMatches(source, signatures: signatures) {
                violations.append(bridgeHardCutViolation(for: rule))
            }
        }
    }
    return violations
}

private func bridgeHardCutViolations(in sourceByRelativePath: [String: String]) -> [BridgeHardCutViolation] {
    bridgeHardCutOwnerRules().compactMap { rule in
        guard let source = sourceByRelativePath[rule.relativePath] else { return nil }
        switch rule.detection {
        case .ownerFile:
            return bridgeHardCutViolation(for: rule)
        case .sourceSignatures(let signatures):
            return bridgeHardCutSourceMatches(source, signatures: signatures)
                ? bridgeHardCutViolation(for: rule)
                : nil
        }
    }
}

private func bridgeHardCutViolation(for rule: BridgeHardCutOwnerRule) -> BridgeHardCutViolation {
    BridgeHardCutViolation(
        description: rule.description,
        group: rule.group,
        relativePath: rule.relativePath
    )
}

private func bridgeHardCutSourceMatches(_ source: String, signatures: [String]) -> Bool {
    let normalizedSource = bridgeHardCutNormalizedSource(source)
    return signatures.contains { signature in
        normalizedSource.contains(bridgeHardCutNormalizedSource(signature))
    }
}

private func bridgeHardCutNormalizedSource(_ source: String) -> String {
    source
        .replacingOccurrences(of: "\"", with: "'")
        .filter { !$0.isWhitespace }
}

private func bridgeHardCutSourcePath(_ components: String...) -> String {
    bridgeHardCutSourcePath(components)
}

private func bridgeHardCutSourcePath(_ components: [String]) -> String {
    components.joined(separator: "/")
}

private func bridgeHardCutJoin(_ fragments: String...) -> String {
    fragments.joined()
}

private func bridgeHardCutCallSignature(_ symbol: String) -> String {
    "\(symbol)("
}

private func bridgeHardCutQuotedSignature(_ token: String) -> String {
    "'\(token)'"
}
