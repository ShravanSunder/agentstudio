import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct BridgeSchemeHandlerWorktreeFileResourceTests {
    private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            firstRejectedEventName: String?,
            receivedAtUnixNano: UInt64
        ) async {
            _ = reason
            _ = droppedCount
            _ = firstRejectedEventName
            _ = receivedAtUnixNano
        }

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drain() async throws {}
    }

    @Test
    func worktreeFileContentResourceEmitsSourceBackedChunks() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.fileContent/file-1?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-worktree-file-resource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appending(path: "large.txt")
        let body = Data(repeating: UInt8(ascii: "a"), count: 140 * 1024)
        try body.write(to: fileURL)
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                fileURL: fileURL,
                byteCount: body.count,
                mimeType: "text/plain"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: body.count,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        var response: URLResponse?
        var receivedBody = Data()
        var dataChunkCount = 0
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                response = emittedResponse
            case .data(let chunk):
                receivedBody.append(chunk)
                dataChunkCount += 1
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(response?.mimeType == "text/plain")
        #expect(response?.expectedContentLength == Int64(body.count))
        #expect(receivedBody == body)
        #expect(dataChunkCount > 1)
    }

    @Test
    func worktreeFileContentResourceRecordsContentLoadTelemetry() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.fileContent/file-telemetry?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        let recorder = BridgeTelemetryRecorderSpy()
        let body = Data("let answer = 42\n".utf8)
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                data: body,
                mimeType: "text/plain"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: body.count,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry,
            telemetryRecorder: recorder
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        for try await _ in handler.reply(for: request) {}

        let sample = try #require(await recorder.samples().first)
        #expect(sample.name == "performance.bridge.swift.content_load")
        #expect(sample.scope == .swift)
        #expect(sample.stringAttributes["agentstudio.bridge.phase"] == "success")
        #expect(sample.stringAttributes["agentstudio.bridge.plane"] == "data")
        #expect(sample.stringAttributes["agentstudio.bridge.priority"] == "hot")
        #expect(sample.stringAttributes["agentstudio.bridge.slice"] == "content_fetch")
        #expect(sample.stringAttributes["agentstudio.bridge.transport"] == "worktree-file")
        #expect(sample.stringAttributes["agentstudio.bridge.content.role"] == "file")
        #expect(sample.stringAttributes["agentstudio.bridge.cache.result"] == "provider_load")
        #expect(sample.stringAttributes["agentstudio.bridge.content.correlation_mode"] == "summary")
        #expect(sample.numericAttributes["agentstudio.bridge.content.byte_size_bucket"] == 1024)
        #expect(sample.booleanAttributes["agentstudio.bridge.header_missing"] == true)
        #expect(sample.booleanAttributes["agentstudio.bridge.header_supported"] == false)
    }

    @Test
    func worktreeFileContentRejectsDescriptorBodyDriftAfterSourceMutation() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.fileContent/file-drift?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-worktree-file-resource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appending(path: "drift.txt")
        let originalBody = Data("original-body".utf8)
        try originalBody.write(to: fileURL)
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                fileURL: fileURL,
                byteCount: originalBody.count,
                mimeType: "text/plain",
                expectedSHA256Hex: sha256Hex(originalBody)
            )
        )
        try Data("mutated--body".utf8).write(to: fileURL)
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: originalBody.count,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        do {
            for try await _ in handler.reply(for: request) {}
            Issue.record("Expected descriptor/body drift to fail closed")
        } catch BridgeWorktreeFileResourceBodyError.integrityMismatch {
            // Expected.
        } catch {
            Issue.record("Expected integrityMismatch, got \(error)")
        }
    }

    @Test
    func worktreeFileContentFailsClosedOnEarlyEOF() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.fileContent/file-short-read?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-worktree-file-resource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appending(path: "short-read.txt")
        let originalBody = Data("original-body".utf8)
        try originalBody.write(to: fileURL)
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                fileURL: fileURL,
                byteCount: originalBody.count,
                mimeType: "text/plain",
                expectedSHA256Hex: sha256Hex(originalBody)
            )
        )
        try Data("short".utf8).write(to: fileURL)
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: originalBody.count,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        do {
            for try await _ in handler.reply(for: request) {}
            Issue.record("Expected early EOF to fail closed")
        } catch BridgeWorktreeFileResourceBodyError.shortRead(
            let expectedBytes,
            let actualBytes
        ) {
            #expect(expectedBytes == originalBody.count)
            #expect(actualBytes == 5)
        } catch {
            Issue.record("Expected shortRead, got \(error)")
        }
    }

    @Test
    func revokedWorktreeFileResourceFailsWithoutLeakingCapabilityURL() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.fileContent/file-1?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                data: Data("let value = 1\n".utf8),
                mimeType: "text/plain"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 1024,
            expectedRevocationRevision: 0
        )
        resourceLeaseRegistry.revokeSynchronously(
            paneId: paneId,
            protocolId: "worktree-file",
            resourceKind: "worktree.fileContent"
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        do {
            for try await _ in handler.reply(for: request) {}
            Issue.record("Expected revoked Worktree/File resource request to fail before bytes")
        } catch BridgeSchemeError.invalidRoute(let route) {
            #expect(route != resourceURL)
            #expect(route.contains("status-1") == false)
            #expect(route.contains("cursor-3") == false)
            #expect(route.contains("agentstudio://resource") == false)
        } catch {
            Issue.record("Expected invalidRoute, got \(error)")
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
