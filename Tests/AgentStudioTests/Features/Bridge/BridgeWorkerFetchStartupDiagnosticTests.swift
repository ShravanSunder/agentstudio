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

        @Test("product stream startup diagnostic runs the packaged worker feasibility probe")
        func productStreamStartupDiagnosticRunsPackagedWorkerFeasibilityProbe() throws {
            let source = try String(
                contentsOfFile:
                    "Sources/AgentStudio/App/Boot/AppDelegate+BridgeProductStreamWebKitFeasibilityStartupDiagnostics.swift",
                encoding: .utf8
            )

            #expect(source.contains("BridgeAppAssetStore().load("))
            #expect(source.contains("assets/bridge-worker-fetch-probe-worker.js"))
            #expect(source.contains("BridgeProductStreamWebKitFeasibilityDiagnostic.run("))
            #expect(source.contains("app.startup_diagnostic_action.completed"))
            #expect(source.contains("app.startup_diagnostic_action.blocked"))
            #expect(!source.contains("raw_capability"))
            #expect(!source.contains("raw_body"))
        }

        @Test("product stream positive verdict rejects incomplete lifecycle proof")
        func productStreamPositiveVerdictRejectsFalseGreenProof() {
            let exactResult = BridgeProductStreamFeasibilityDiagnosticResult(
                proof: makeProductStreamFeasibilityProof()
            )
            let authenticationResult = BridgeProductStreamFeasibilityDiagnosticResult(
                proof: makeProductStreamFeasibilityProof(authenticationBeforeBodySucceeded: false)
            )
            let bufferedFrameResult = BridgeProductStreamFeasibilityDiagnosticResult(
                proof: makeProductStreamFeasibilityProof(workerObservedIncrementalFrames: false)
            )
            let producerResidueResult = BridgeProductStreamFeasibilityDiagnosticResult(
                proof: makeProductStreamFeasibilityProof(activeProducerTaskCount: 1)
            )
            let postTerminalResult = BridgeProductStreamFeasibilityDiagnosticResult(
                proof: makeProductStreamFeasibilityProof(postTerminalFrameCount: 1)
            )
            let missingAcknowledgementResult = BridgeProductStreamFeasibilityDiagnosticResult(
                proof: makeProductStreamFeasibilityProof(
                    cancellationOrder: [.producerStopped, .producerUnregistered]
                )
            )

            #expect(exactResult.carrierSucceeded)
            #expect(exactResult.framedStreamSucceeded)
            #expect(exactResult.abortCausalCancellationSucceeded)
            #expect(!authenticationResult.carrierSucceeded)
            #expect(!bufferedFrameResult.carrierSucceeded)
            #expect(!producerResidueResult.carrierSucceeded)
            #expect(!postTerminalResult.carrierSucceeded)
            #expect(!missingAcknowledgementResult.carrierSucceeded)
        }

        private func makeProductStreamFeasibilityProof(
            authenticationBeforeBodySucceeded: Bool = true,
            workerObservedIncrementalFrames: Bool = true,
            activeProducerTaskCount: Int = 0,
            postTerminalFrameCount: Int = 0,
            cancellationOrder: [BridgeWebKitFeasibilityCancellationEvent] = [
                .producerStopped, .producerUnregistered, .resultAcknowledged,
            ]
        ) -> BridgeProductStreamWebKitFeasibilityProof {
            BridgeProductStreamWebKitFeasibilityProof(
                authenticationBeforeBodySucceeded: authenticationBeforeBodySucceeded,
                bodyCapBeforeDecodeSucceeded: true,
                strictRouteDecodeSucceeded: true,
                missingContentLengthAccepted: true,
                exactRequestBodyBytesSucceeded: true,
                bodyReadCount: 11,
                bodyReadByteCount: 66_000,
                decodeCallCount: 10,
                providerCallCount: 8,
                unauthorizedBodyReadCount: 0,
                validBodyByteCount: 128,
                firstFrameByteCount: 45,
                validStreamEnded: true,
                workerStartPostObserved: true,
                workerObservedExactFrames: true,
                workerObservedIncrementalFrames: workerObservedIncrementalFrames,
                workerObservedCancellation: true,
                frameReceiptCount: 4,
                cancellationOrder: cancellationOrder,
                activeProducerCount: 0,
                activeProducerTaskCount: activeProducerTaskCount,
                queuedFrameCount: 0,
                maximumQueuedFrameCount: 1,
                producerOverflowCount: 0,
                postTerminalFrameCount: postTerminalFrameCount,
                requestAPIObservations: [],
                failureReason: "none"
            )
        }
    }
}
