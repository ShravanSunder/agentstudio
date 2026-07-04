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

            #expect(source.contains("new Worker("))
            #expect(source.contains("fetch(resourceUrl)"))
            #expect(source.contains("response.body.getReader()"))
            #expect(source.contains("reader.read()"))
            #expect(source.contains("holdStreamOpen"))
        }

        @Test("startup diagnostic records marker scoped worker fetch proof facts")
        func startupDiagnosticRecordsMarkerScopedWorkerFetchProofFacts() throws {
            let source = try String(
                contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+BridgeWorkerFetchStartupDiagnostics.swift",
                encoding: .utf8
            )

            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count"))
            #expect(source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open"))
            #expect(!source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.raw_url"))
            #expect(!source.contains("agentstudio.startup_diagnostic.bridge.worker_fetch.raw_path"))
        }
    }
}
