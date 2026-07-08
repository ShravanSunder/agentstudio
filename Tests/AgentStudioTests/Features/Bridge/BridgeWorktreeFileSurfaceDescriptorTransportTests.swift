import CryptoKit
import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileSurfaceDescriptorTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("file scoped open source reports metadata tree rows without metadata resource leases")
        func fileScopedOpenSourceReportsMetadataTreeRowsWithoutMetadataResourceLeases() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let fileURL = fixture.rootURL
                .appending(path: "Sources")
                .appending(path: "App")
                .appending(path: "View.swift")
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "struct View {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let firstResponseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await firstResponseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            let firstSpec = sourceSpec(
                fixture: fixture,
                clientRequestId: "request-file",
                pathScope: ["Sources/App/View.swift"]
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-file",
                    method: "worktreeFileSurface.openSourceStream",
                    params: firstSpec
                ).jsonString()
            )

            let firstResponse = try await decodedResponse(from: firstResponseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file", streamId: firstResponse.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let firstSnapshotJSON = try #require(await eventCapture.intakeFrames().first)
            let firstSnapshot = try decodeIntakeEnvelope(
                firstSnapshotJSON,
                as: BridgeWorktreeSnapshotFrame.self
            )
            #expect(firstResponse.result.status == "accepted")
            #expect(firstSnapshot.payload.treeSizeFacts.extentKind == .exactPathCount)
            #expect(firstSnapshot.payload.treeSizeFacts.pathCount == 3)
            #expect(
                firstSnapshot.payload.treeRows.map(\.path) == [
                    "Sources",
                    "Sources/App",
                    "Sources/App/View.swift",
                ]
            )
            #expect(firstSnapshot.payload.treeRows.last?.sizeBytes == Data("struct View {}\n".utf8).count)
            #expect(firstSnapshot.payload.treeRows.last?.lineCount == nil)

            let secondResponseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await secondResponseCapture.set(responseJSON)
            }
            let secondSpec = sourceSpec(
                fixture: fixture,
                clientRequestId: "request-root",
                pathScope: []
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-root",
                    method: "worktreeFileSurface.openSourceStream",
                    params: secondSpec
                ).jsonString()
            )

            _ = try await decodedResponse(from: secondResponseCapture)
            fixture.controller.teardown()
        }

        @Test("file scoped descriptor demand emits descriptor frame and serves content")
        func fileScopedDescriptorDemandEmitsDescriptorFrameAndServesContent() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let fileURL = fixture.rootURL
                .appending(path: "Sources")
                .appending(path: "App")
                .appending(path: "View.swift")
            let fileText = "struct View {}\nlet value = 1"
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileText.write(to: fileURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            let spec = sourceSpec(
                fixture: fixture,
                clientRequestId: "request-file-descriptor",
                pathScope: ["Sources/App/View.swift"]
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-file-metadata",
                    method: "worktreeFileSurface.openSourceStream",
                    params: spec
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let events = await eventCapture.events()
            #expect(events == ["response", "intake"])
            let intakeFrames = await eventCapture.intakeFrames()
            let snapshotEnvelope = try decodeIntakeEnvelope(
                intakeFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            #expect(snapshotEnvelope.kind == "snapshot")
            #expect(snapshotEnvelope.streamId == response.result.streamId)
            #expect(snapshotEnvelope.generation == response.result.generation)
            let selectedRow = try #require(snapshotEnvelope.payload.treeRows.last)
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-file-descriptor",
                sourceIdentity: snapshotEnvelope.payload.source,
                row: selectedRow,
                path: "Sources/App/View.swift",
                lane: .foreground
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            // The descriptor frame is emitted by a scheduler job, so its
            // delivery interleaves with the RPC response at suspension
            // points; only counts and intake order are deterministic.
            let demandEvents = await eventCapture.events()
            #expect(demandEvents.prefix(2) == ["response", "intake"])
            #expect(demandEvents.count == 4)
            #expect(demandEvents.filter { $0 == "response" }.count == 2)
            let demandIntakeFrames = await eventCapture.intakeFrames()
            let intakeFrame = try decodeDescriptorEnvelope(demandIntakeFrames[1])
            #expect(intakeFrame.kind == "delta")
            #expect(intakeFrame.streamId == response.result.streamId)
            #expect(intakeFrame.generation == response.result.generation)
            #expect(intakeFrame.sequence == 1)
            #expect(intakeFrame.payload.frameKind == "worktree.fileDescriptor")
            #expect(intakeFrame.payload.descriptor.path == "Sources/App/View.swift")
            #expect(intakeFrame.payload.descriptor.contentHash == sha256ContentHash(fileText))
            #expect(intakeFrame.payload.descriptor.virtualizedExtentKind == .exactLineCount)
            #expect(intakeFrame.payload.descriptor.lineCount == 2)
            #expect(intakeFrame.payload.descriptor.contentDescriptor.descriptor.resourceKind == "worktree.fileContent")
            let contentResource = try #require(
                BridgeTransportResourceURL.parse(
                    intakeFrame.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                    allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
                )
            )
            #expect(await fixture.controller.resourceLeaseRegistry.contains(contentResource, paneId: fixture.paneId))
            let schemeHandler = BridgeSchemeHandler(
                paneId: fixture.paneId,
                worktreeFileResourceStore: fixture.controller.worktreeFileResourceStore,
                resourceLeaseRegistry: fixture.controller.resourceLeaseRegistry
            )
            let contentBody = try await resourceBody(
                url: intakeFrame.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                handler: schemeHandler
            )
            #expect(String(data: contentBody, encoding: .utf8) == fileText)
            fixture.controller.teardown()
        }

        @Test("descriptor demand after tree windows emits latest sequence and serves clicked content")
        func descriptorDemandAfterTreeWindowsEmitsLatestSequenceAndServesClickedContent() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let selectedFileURL = fixture.rootURL.appending(path: "File-259.swift")
            let selectedFileText = "let selected = 259\n"
            for index in 0..<260 {
                let fileURL = fixture.rootURL.appending(path: String(format: "File-%03d.swift", index))
                let fileText = index == 259 ? selectedFileText : "let value\(index) = \(index)\n"
                try fileText.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            #expect(FileManager.default.fileExists(atPath: selectedFileURL.path))
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-tree-before-demand",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-tree-before-demand",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let treeFrames = await eventCapture.intakeFrames()
            #expect(treeFrames.count == 2)
            let treeWindow = try decodeIntakeEnvelope(
                treeFrames[1],
                as: BridgeWorktreeTreeWindowFrame.self
            )
            #expect(treeWindow.payload.treeSizeFacts.windowStartIndex == 200)
            let selectedRow = try #require(
                treeWindow.payload.rows.first { $0.path == "File-259.swift" }
            )

            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-selected-after-window",
                sourceIdentity: treeWindow.payload.projectionIdentity.source,
                row: selectedRow,
                path: "File-259.swift",
                lane: .foreground
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let demandFrames = await eventCapture.intakeFrames()
            #expect(demandFrames.count == 3)
            let descriptorEnvelope = try decodeDescriptorEnvelope(demandFrames[2])
            #expect(descriptorEnvelope.payload.frameKind == "worktree.fileDescriptor")
            #expect(descriptorEnvelope.sequence == 2)
            #expect(descriptorEnvelope.payload.descriptor.path == "File-259.swift")
            let schemeHandler = BridgeSchemeHandler(
                paneId: fixture.paneId,
                worktreeFileResourceStore: fixture.controller.worktreeFileResourceStore,
                resourceLeaseRegistry: fixture.controller.resourceLeaseRegistry
            )
            let contentBody = try await resourceBody(
                url: descriptorEnvelope.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                handler: schemeHandler
            )
            #expect(String(data: contentBody, encoding: .utf8) == selectedFileText)

            fixture.controller.teardown()
        }

        @Test("root scoped open source streams metadata rows and descriptors on demand")
        func rootScopedOpenSourceStreamsMetadataRowsAndDescriptorsOnDemand() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            try writeRootScopedDescriptorFixtureFiles(rootURL: fixture.rootURL)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            let spec = sourceSpec(
                fixture: fixture,
                clientRequestId: "request-root-descriptors",
                pathScope: []
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-root-descriptors",
                    method: "worktreeFileSurface.openSourceStream",
                    params: spec
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let events = await eventCapture.events()
            #expect(events == ["response", "intake"])
            let intakeFrames = await eventCapture.intakeFrames()
            let snapshotEnvelope = try decodeIntakeEnvelope(
                intakeFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            let requestPathScope = try #require(snapshotEnvelope.payload.requestSelector?.pathScope)
            #expect(requestPathScope.isEmpty)
            let snapshotTreeRowPaths = snapshotEnvelope.payload.treeRows.map(\.path)
            #expect(snapshotTreeRowPaths.contains("README.md"))
            #expect(snapshotTreeRowPaths.contains("Sources/App/View.swift"))
            // Git-truth publication policy: this fixture is not a git repo,
            // so nothing is gitignored — the planted tmp probe and build
            // artifact are published rows. Only `.git` internals stay
            // structurally excluded.
            #expect(
                snapshotTreeRowPaths.contains(
                    "BridgeWeb/BridgeWeb/tmp/bridge-viewer-worktree-dev-server/2026-06-29-review-probe/review-probe.json"
                )
            )
            #expect(snapshotTreeRowPaths.contains(".build-agent-1/debug/generated.txt"))
            #expect(snapshotTreeRowPaths.contains(".git/index") == false)
            #expect(snapshotTreeRowPaths.contains(".git") == false)
            let readmeRow = try #require(snapshotEnvelope.payload.treeRows.first { $0.path == "README.md" })
            let sourceRow = try #require(
                snapshotEnvelope.payload.treeRows.first { $0.path == "Sources/App/View.swift" }
            )
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-readme-descriptor",
                sourceIdentity: snapshotEnvelope.payload.source,
                row: readmeRow,
                path: "README.md",
                lane: .visible
            )
            // Drain between the two demands: with both queued, strict lane
            // priority would legally deliver the foreground descriptor before
            // the visible one, so per-request delivery is what pins the order.
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-source-descriptor",
                sourceIdentity: snapshotEnvelope.payload.source,
                row: sourceRow,
                path: "Sources/App/View.swift",
                lane: .foreground
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let demandFrames = await eventCapture.intakeFrames()
            let firstDescriptor = try decodeDescriptorEnvelope(demandFrames[1])
            let secondDescriptor = try decodeDescriptorEnvelope(demandFrames[2])
            let descriptorPaths = [
                firstDescriptor.payload.descriptor.path,
                secondDescriptor.payload.descriptor.path,
            ]
            #expect(descriptorPaths == ["README.md", "Sources/App/View.swift"])
            #expect(firstDescriptor.payload.descriptor.lineCount == 2)
            #expect(secondDescriptor.payload.descriptor.lineCount == 3)
            let firstResourceKind = firstDescriptor.payload.descriptor.contentDescriptor.descriptor.resourceKind
            let secondResourceKind = secondDescriptor.payload.descriptor.contentDescriptor.descriptor.resourceKind
            #expect(firstResourceKind == "worktree.fileContent")
            #expect(secondResourceKind == "worktree.fileContent")
            let contentResource = try #require(
                BridgeTransportResourceURL.parse(
                    secondDescriptor.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                    allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
                )
            )
            #expect(await fixture.controller.resourceLeaseRegistry.contains(contentResource, paneId: fixture.paneId))
            fixture.controller.teardown()
        }

        @Test("root scoped open source streams the startup window in deterministic neutral order")
        func rootScopedOpenSourcePrioritizesNativeSourceRowsBeforeBridgeWebRows() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let sourcesURL = fixture.rootURL.appending(path: "Sources")
            let bridgeWebURL = fixture.rootURL.appending(path: "BridgeWeb")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bridgeWebURL, withIntermediateDirectories: true)
            for index in 0..<260 {
                let fileName = String(format: "WebFile%03d.ts", index)
                try "export const value\(index) = \(index);\n".write(
                    to: bridgeWebURL.appending(path: fileName),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try "struct NativeStartupCanary {}\n".write(
                to: sourcesURL.appending(path: "NativeStartupCanary.swift"),
                atomically: true,
                encoding: .utf8
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-source-priority",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-source-priority",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            let snapshotEnvelope = try decodeIntakeEnvelope(
                try #require(intakeFrames.first),
                as: BridgeWorktreeSnapshotFrame.self
            )
            // Manifest ordering is deterministic and policy-owned: sibling
            // names compare by plain code units, breadth-first by directory.
            // No repository-specific folder priority exists; rows the UI
            // needs first are the metadata-interest lanes' job, not the
            // startup window's ordering.
            let paths = snapshotEnvelope.payload.treeRows.map(\.path)
            #expect(paths.first == "BridgeWeb")
            #expect(paths.dropFirst().first == "Sources")
            #expect(paths.contains("BridgeWeb/WebFile000.ts"))
            #expect(!paths.contains("Sources/NativeStartupCanary.swift"))
            #expect(
                paths.count == AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
            )
            // The canary still arrives through manifest continuation: the
            // full manifest is complete even though the startup window is
            // dominated by the byte-order-first directory.
            var manifestPaths = Set<String>()
            for intakeFrame in intakeFrames {
                if let window = try? decodeIntakeEnvelope(
                    intakeFrame,
                    as: BridgeWorktreeTreeWindowFrame.self
                ) {
                    manifestPaths.formUnion(window.payload.rows.map(\.path))
                }
            }
            manifestPaths.formUnion(paths)
            #expect(manifestPaths.contains("Sources/NativeStartupCanary.swift"))
            #expect(manifestPaths.count == 263)

            fixture.controller.teardown()
        }
    }
}

private func sha256ContentHash(_ text: String) -> String {
    "sha256:" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}
