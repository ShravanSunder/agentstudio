import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct BridgeSchemeHandlerWorktreeFileResourceTests {
    @Test
    func worktreeFileTreeWindowResourceEmitsLeasedBody() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.treeWindow/tree-window-1?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        let body = Data(#"{"rows":[],"treeSizeFacts":{"extentKind":"exactPathCount","pathCount":0}}"#.utf8)
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                data: body,
                mimeType: "application/json"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 1024,
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
        var eventOrder: [String] = []
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                response = emittedResponse
                eventOrder.append("response")
            case .data(let chunk):
                receivedBody.append(chunk)
                eventOrder.append("data")
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(eventOrder == ["response", "data"])
        #expect(response?.mimeType == "application/json")
        #expect(response?.expectedContentLength == Int64(body.count))
        #expect(receivedBody == body)
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
            "agentstudio://resource/worktree-file/worktree.status/status-1?generation=3&cursor=cursor-3"
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
                data: Data(#"{"branchName":"main"}"#.utf8),
                mimeType: "application/json"
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
            resourceKind: "worktree.status"
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
