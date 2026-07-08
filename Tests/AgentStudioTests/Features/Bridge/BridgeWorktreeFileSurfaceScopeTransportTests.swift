import CryptoKit
import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileSurfaceScopeTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("file scoped descriptor demand rejects sibling paths")
        func fileScopedDescriptorDemandRejectsSiblingPaths() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let scopedURL = fixture.rootURL.appending(path: "Sources/App/View.swift")
            let siblingURL = fixture.rootURL.appending(path: "Sources/App/Other.swift")
            try FileManager.default.createDirectory(
                at: scopedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "struct View {}\n".write(to: scopedURL, atomically: true, encoding: .utf8)
            try "struct Other {}\n".write(to: siblingURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-file-scope",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-file-scope",
                        pathScope: ["Sources/App/View.swift"]
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshot = try await waitForSnapshotFrame(from: eventCapture)
            let scopedRow = try #require(
                snapshot.payload.treeRows.first { $0.path == "Sources/App/View.swift" }
            )

            do {
                _ = try await fixture.controller.handleWorktreeFileDescriptorRequest(
                    BridgeWorktreeFileDescriptorRequest(
                        sourceIdentity: snapshot.payload.source,
                        rowId: scopedRow.rowId,
                        path: "Sources/App/Other.swift",
                        fileId: try #require(scopedRow.fileId),
                        lane: .foreground
                    )
                )
                Issue.record("Expected out-of-scope descriptor demand to fail")
            } catch RPCMethodDispatchError.invalidParams(let message) {
                #expect(message == "worktree_file.descriptor_path_out_of_scope")
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect((await eventCapture.intakeFrames()).count == 1)
            fixture.controller.teardown()
        }

        @Test("root scoped tree publishes non-ignored hidden paths and serves their descriptors")
        func rootScopedDescriptorDemandRejectsHiddenPathsOmittedFromTree() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let visibleURL = fixture.rootURL.appending(path: "Sources/App/View.swift")
            let hiddenURL = fixture.rootURL.appending(path: ".swiftlint.yml")
            try FileManager.default.createDirectory(
                at: visibleURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "struct View {}\n".write(to: visibleURL, atomically: true, encoding: .utf8)
            try "disabled_rules: []\n".write(to: hiddenURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-root-scope",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-root-scope",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshot = try await waitForSnapshotFrame(from: eventCapture)
            #expect(snapshot.payload.treeRows.contains { $0.path == "Sources/App/View.swift" })
            // Git-truth publication policy: non-ignored hidden paths are
            // published rows and their descriptors are demandable.
            let hiddenRow = try #require(
                snapshot.payload.treeRows.first { $0.path == ".swiftlint.yml" }
            )
            _ = try await fixture.controller.handleWorktreeFileDescriptorRequest(
                BridgeWorktreeFileDescriptorRequest(
                    sourceIdentity: snapshot.payload.source,
                    rowId: hiddenRow.rowId,
                    path: ".swiftlint.yml",
                    fileId: try #require(hiddenRow.fileId),
                    lane: .foreground
                )
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 2)
            let descriptorEnvelope = try decodeDescriptorEnvelope(try #require(intakeFrames.last))
            #expect(descriptorEnvelope.payload.frameKind == "worktree.fileDescriptor")
            #expect(descriptorEnvelope.payload.descriptor.path == ".swiftlint.yml")
            fixture.controller.teardown()
        }

        @Test("root scoped descriptor demand rejects gitignored paths omitted from tree")
        func rootScopedDescriptorDemandRejectsGitignoredPathsOmittedFromTree() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-ignore-scope")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let visibleURL = repoURL.appending(path: "Sources/App/View.swift")
            let ignoredURL = repoURL.appending(path: "ignored.log")
            try FileManager.default.createDirectory(
                at: visibleURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "*.log\n".write(to: repoURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
            try "struct View {}\n".write(to: visibleURL, atomically: true, encoding: .utf8)
            try "ignored\n".write(to: ignoredURL, atomically: true, encoding: .utf8)
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-gitignored-root-scope",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-gitignored-root-scope",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshot = try await waitForSnapshotFrame(from: eventCapture)
            #expect(snapshot.payload.treeRows.contains { $0.path == "Sources/App/View.swift" })
            #expect(!snapshot.payload.treeRows.contains { $0.path == "ignored.log" })

            do {
                _ = try await fixture.controller.handleWorktreeFileDescriptorRequest(
                    BridgeWorktreeFileDescriptorRequest(
                        sourceIdentity: snapshot.payload.source,
                        rowId: "ignored-row",
                        path: "ignored.log",
                        fileId: worktreeFileId(for: "ignored.log"),
                        lane: .foreground
                    )
                )
                Issue.record("Expected gitignored descriptor demand to fail")
            } catch RPCMethodDispatchError.invalidParams(let message) {
                #expect(message == "worktree_file.descriptor_path_out_of_scope")
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect((await eventCapture.intakeFrames()).count == 1)
            fixture.controller.teardown()
        }

        @Test("exact file scope publishes non-ignored generated paths and serves their descriptors")
        func exactFileScopeOmitsGeneratedPathsThatDescriptorDemandRejects() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let generatedPath = "node_modules/pkg/index.js"
            let generatedURL = fixture.rootURL.appending(path: generatedPath)
            try FileManager.default.createDirectory(
                at: generatedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "module.exports = {}\n".write(to: generatedURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-generated-file-scope",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-generated-file-scope",
                        pathScope: [generatedPath]
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshot = try await waitForSnapshotFrame(from: eventCapture)
            // Git-truth publication policy: generated paths are published
            // unless gitignored; this fixture has no repo, so nothing is
            // ignored and the exact-file scope row is served on demand.
            let generatedRow = try #require(
                snapshot.payload.treeRows.first { $0.path == generatedPath }
            )
            _ = try await fixture.controller.handleWorktreeFileDescriptorRequest(
                BridgeWorktreeFileDescriptorRequest(
                    sourceIdentity: snapshot.payload.source,
                    rowId: generatedRow.rowId,
                    path: generatedPath,
                    fileId: try #require(generatedRow.fileId),
                    lane: .foreground
                )
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 2)
            let descriptorEnvelope = try decodeDescriptorEnvelope(try #require(intakeFrames.last))
            #expect(descriptorEnvelope.payload.frameKind == "worktree.fileDescriptor")
            #expect(descriptorEnvelope.payload.descriptor.path == generatedPath)
            fixture.controller.teardown()
        }

        @Test("live Worktree/File changes suppress out-of-scope and generated paths")
        func liveWorktreeFileChangesSuppressOutOfScopeAndGeneratedPaths() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let sourceURL = fixture.rootURL.appending(path: "Sources/App/View.swift")
            let testURL = fixture.rootURL.appending(path: "Tests/App/ViewTests.swift")
            let dependencyURL = fixture.rootURL.appending(path: "node_modules/pkg/index.js")
            let tmpURL = fixture.rootURL.appending(path: "tmp/reloading.log")
            try FileManager.default.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: testURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: dependencyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: tmpURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "struct View {}\n".write(to: sourceURL, atomically: true, encoding: .utf8)
            try "struct ViewTests {}\n".write(to: testURL, atomically: true, encoding: .utf8)
            try "module.exports = {}\n".write(to: dependencyURL, atomically: true, encoding: .utf8)
            try "reload\n".write(to: tmpURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-sources-scope",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-sources-scope",
                        pathScope: ["Sources"]
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            _ = try await waitForSnapshotFrame(from: eventCapture)

            try await fixture.controller.publishWorktreeFileSurfaceChangeset(
                FileChangeset(
                    worktreeId: fixture.worktreeId,
                    rootPath: fixture.rootURL,
                    paths: [
                        "Tests/App/ViewTests.swift",
                        "node_modules/pkg/index.js",
                        "tmp/reloading.log",
                    ],
                    timestamp: .now,
                    batchSeq: 44
                )
            )

            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 1)
            fixture.controller.teardown()
        }

        private func worktreeFileId(for relativePath: String) -> String {
            let digest = SHA256.hash(data: Data(relativePath.utf8))
            let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
            return "worktree-file-\(hexDigest.prefix(32))"
        }
    }
}
