import Foundation
import Testing

@Suite("Bridge observability verifier script")
struct BridgeObservabilityVerifierScriptTests {
    @Test("verifier covers all bridge telemetry planes with marker-scoped Victoria proof")
    func verifierCoversBridgeTelemetryPlanesWithMarkerScopedVictoriaProof() throws {
        let verifierScript = try String(
            contentsOfFile: "scripts/verify-bridge-observability.sh",
            encoding: .utf8
        )
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(verifierScript.contains("bridge-review-observability-smoke"))
        #expect(verifierScript.contains("scripts/verify-debug-observability.sh"))
        #expect(verifierScript.contains("scripts/verify-bridge-web-no-direct-otlp.sh"))
        #expect(verifierScript.contains("AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO"))
        #expect(verifierScript.contains("performance.bridge.swift.package_build"))
        #expect(verifierScript.contains("performance.bridge.webkit.rpc_dispatch"))
        #expect(verifierScript.contains("performance.bridge.web.content_fetch"))
        #expect(verifierScript.contains("TRACES_QUERY_URL"))
        #expect(verifierScript.contains("span_attr:agent.proof.marker"))
        #expect(verifierScript.contains("agent.proof.marker"))
        #expect(!verifierScript.contains("agentstudio.trace.name"))
        #expect(verifierScript.contains("span_attr:agentstudio.bridge.test.scenario"))
        #expect(verifierScript.contains("span_attr:agentstudio.bridge.rpc.method_class"))
        #expect(verifierScript.contains("agentstudio.bridge.plane"))
        #expect(verifierScript.contains("agentstudio.bridge.priority"))
        #expect(verifierScript.contains("agentstudio.bridge.slice"))
        #expect(verifierScript.contains("agentstudio.bridge.rpc.method_class:telemetry"))
        #expect(verifierScript.contains("telemetry_self_rpc=absent"))
        #expect(verifierScript.contains("historical_bridge_lane_field"))
        #expect(verifierScript.contains("BRIDGE_HISTORICAL_LANE_SUFFIX"))
        #expect(verifierScript.contains("agentstudio.bridge.session_id"))
        #expect(verifierScript.contains("agentstudio.bridge.request_id"))
        #expect(verifierScript.contains("agentstudio.bridge.content_hash"))
        #expect(
            verifierScript.contains(
                "performance.bridge.webkit.package_push|transport|data|cold|diff_package_metadata|push"
            ))
        #expect(
            verifierScript.contains(
                "performance.bridge.webkit.package_push|transport|data|hot|diff_status|push"
            ))
        #expect(
            verifierScript.contains(
                "performance.bridge.webkit.package_push|transport|data|warm|diff_package_delta|push"
            ))
        #expect(
            verifierScript.contains(
                "performance.bridge.webkit.telemetry_batch|accepted|observability|best_effort|telemetry_batch|rpc"
            ))
        #expect(
            verifierScript.contains(
                "performance.bridge.web.content_fetch|fetch|data|hot|content_fetch|content"
            ))
        #expect(
            verifierScript.contains(
                "performance.bridge.swift.content_load|success|data|hot|content_fetch|content"
            ))
        #expect(
            verifierScript.contains(
                "performance.bridge.web.rpc_send|send|control|warm|review_rpc|rpc"
            ))
        #expect(verifierScript.contains("plane=\"'\"$plane\"'\""))
        #expect(verifierScript.contains("priority=\"'\"$priority\"'\""))
        #expect(verifierScript.contains("slice=\"'\"$slice\"'\""))
        #expect(verifierScript.contains("agentstudio.bridge.test.scenario"))
        #expect(verifierScript.contains("agentstudio.bridge.item_id"))
        #expect(verifierScript.contains("agentstudio.bridge.raw_error"))
        #expect(verifierScript.contains("agentstudio.bridge.prompt"))
        #expect(verifierScript.contains("missing Bridge broad package_push metric fallback"))
        #expect(verifierScript.contains("Bridge package_push metric used unknown producer slice"))
        #expect(verifierScript.contains("Bridge package_push log used unknown producer slice"))
        #expect(
            verifierScript.contains(
                "event=\"performance.bridge.webkit.package_push\",slice=\"unknown\""
            ))
        #expect(miseConfig.contains("[tasks.verify-bridge-observability]"))
    }

    @Test("BridgeWeb does not contain direct browser OTLP exporter hooks")
    func bridgeWebDoesNotContainDirectBrowserOTLPExporterHooks() throws {
        let scanScript = try String(
            contentsOfFile: "scripts/verify-bridge-web-no-direct-otlp.sh",
            encoding: .utf8
        )

        #expect(scanScript.contains("BridgeWeb/package.json"))
        #expect(scanScript.contains("BridgeWeb/pnpm-lock.yaml"))
        #expect(scanScript.contains("BridgeWeb/src"))
        #expect(scanScript.contains("Sources/AgentStudio/Resources/BridgeWeb/app"))
        #expect(scanScript.contains("BRIDGE_WEB_OTLP_SCAN_TARGETS"))
        #expect(scanScript.contains("default_scan_targets=("))
        #expect(scanScript.contains("scan_targets=(\"${default_scan_targets[@]}\")"))
        #expect(scanScript.contains("scan_targets+=(\"${extra_scan_targets[@]}\")"))
        #expect(scanScript.contains("mktemp -t bridge-web-otlp-scan"))
        #expect(scanScript.contains("@opentelemetry"))
        #expect(scanScript.contains("/v1/traces"))
        #expect(scanScript.contains("/v1/logs"))
        #expect(scanScript.contains("/v1/metrics"))
        #expect(scanScript.contains("OTEL_EXPORTER_OTLP"))
        #expect(scanScript.contains("OTLPHTTP"))
        #expect(scanScript.contains("127.0.0.1:4318"))
        #expect(scanScript.contains("localhost:4318"))
        #expect(scanScript.contains("-- \"$pattern\""))
    }

    @Test("BridgeWeb direct OTLP scanner keeps default roots when extra targets are supplied")
    func bridgeWebDirectOTLPScannerKeepsDefaultRootsWhenExtraTargetsAreSupplied() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/verify-bridge-web-no-direct-otlp.sh"]
        process.environment = [
            "BRIDGE_WEB_OTLP_SCAN_TARGETS": "/dev/null"
        ]

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    @Test("BridgeWeb direct OTLP scanner fails on seeded browser exporter markers")
    func bridgeWebDirectOTLPScannerFailsOnSeededMarkers() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-web-direct-otlp-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let seededFile = temporaryDirectory.appendingPathComponent("bad.ts")
        try "@opentelemetry/exporter-trace-otlp-http".write(to: seededFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/verify-bridge-web-no-direct-otlp.sh"]
        process.environment = [
            "BRIDGE_WEB_OTLP_SCAN_TARGETS": temporaryDirectory.path
        ]

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
    }
}
