import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeWorkerFetchStartupDiagnosticTests {
        @Test("startup diagnostic JavaScript creates worker fetch and streamed response probes")
        func startupDiagnosticJavaScriptCreatesWorkerFetchAndStreamedResponseProbes() throws {
            let source = try String(
                contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+BridgeWorkerFetchStartupDiagnostics.swift",
                encoding: .utf8
            )
            let workerSource = try String(
                contentsOfFile: "BridgeWeb/src/app/diagnostics/bridge-worker-fetch-probe-worker-entry.ts",
                encoding: .utf8
            )

            #expect(source.contains("new Worker("))
            #expect(source.contains("bridgeWorkerFetchSchemeSmokeWorkerScriptURL"))
            #expect(source.contains("agentstudio://app/assets/bridge-worker-fetch-probe-worker.js"))
            #expect(source.contains("new Worker(workerUrl)"))
            #expect(!source.contains("new Worker(workerScriptUrl, { type: 'module' })"))
            #expect(workerSource.contains("fetch(request.resourceUrl)"))
            #expect(workerSource.contains("response.body.getReader()"))
            #expect(workerSource.contains("reader.read()"))
            #expect(source.contains("worker_error"))
            #expect(source.contains("probeWorkerScriptFetch(workerScriptUrl)"))
            #expect(source.contains("worker.onerror = function(event)"))
            #expect(source.contains("worker_error:module_load"))
            #expect(source.contains("workerBootstrapMode: data.workerBootstrapMode || 'blob_classic'"))
            #expect(!source.contains("worker_script_fetch_failed"))
            #expect(!source.contains("failureReason: event.message"))
            #expect(!source.contains("failureReason: error.message"))
            #expect(source.contains("URL.createObjectURL"))
            #expect(source.contains("URL.revokeObjectURL"))
            #expect(source.contains("new Blob([workerSource]"))
        }

        @Test("startup diagnostic worker probe is packaged as an app asset")
        func startupDiagnosticWorkerProbeIsPackagedAsAppAsset() throws {
            let tsdownConfig = try String(
                contentsOfFile: "BridgeWeb/tsdown.config.ts",
                encoding: .utf8
            )
            let buildScript = try String(
                contentsOfFile: "BridgeWeb/scripts/build-app-assets.ts",
                encoding: .utf8
            )

            #expect(
                tsdownConfig.contains(
                    "name: 'bridge-worker-fetch-probe-worker'"
                ))
            #expect(
                tsdownConfig.contains(
                    "'bridge-worker-fetch-probe-worker':"
                ))
            #expect(
                tsdownConfig.contains(
                    "'./src/app/diagnostics/bridge-worker-fetch-probe-worker-entry.ts'"
                ))
            #expect(buildScript.contains("entrypointName: 'bridge-worker-fetch-probe-worker'"))
            #expect(
                FileManager.default.fileExists(
                    atPath: "BridgeWeb/src/app/diagnostics/bridge-worker-fetch-probe-worker-entry.ts"
                ))
        }

        @Test("startup diagnostic records marker scoped worker fetch proof facts")
        func startupDiagnosticRecordsMarkerScopedWorkerFetchProofFacts() throws {
            let source = try String(
                contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+BridgeWorkerFetchStartupDiagnostics.swift",
                encoding: .utf8
            )

            #expect(source.contains("waitForBridgeWorkerFetchSchemeSmokePageReady"))
            #expect(source.contains("controller.page.url?.absoluteString == \"agentstudio://app/index.html\""))
            #expect(source.contains("!controller.page.isLoading"))
            #expect(source.contains("controller.isBridgeReady"))
            #expect(source.contains("bridge_page_not_ready"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.bootstrap.mode"))
            #expect(
                source.contains(
                    "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_script_fetch.succeeded"
                ))
            #expect(
                source.contains(
                    "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_script_fetch.status"
                ))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open"))
            #expect(!source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.raw_url"))
            #expect(!source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.raw_path"))
        }
    }
}
