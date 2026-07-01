import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeReviewContentStreamTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("modified review file streams base and head content when base size is not exact")
        func modifiedReviewFileStreamsBaseAndHeadContentWhenBaseSizeIsNotExact() async throws {
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let baseText = "old source with extra bytes\nlet oldOnly = true\n"
            let headText = "new source\n"
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: Data(headText.utf8).count,
                oldContentHash: bridgeSHA256ContentHash(baseText),
                newContentHash: bridgeSHA256ContentHash(headText)
            )
            let expectedBaseHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: baseEndpoint,
                role: .base,
                reviewGeneration: 1
            )
            let expectedHeadHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: headEndpoint,
                role: .head,
                reviewGeneration: 1
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [changedFile]
                ),
                contentByHandleId: [
                    expectedBaseHandle.handleId: makeContentResult(handle: expectedBaseHandle, data: baseText),
                    expectedHeadHandle.handleId: makeContentResult(handle: expectedHeadHandle, data: headText),
                ]
            )
            let paneId = UUIDv7.generate()
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )

            let result = await controller.handleDiffCommand(
                DiffCommand.loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: UUID(),
                correlationId: nil
            )

            guard case .success = result else {
                Issue.record("Expected Review diff load to succeed")
                return
            }
            #expect(expectedBaseHandle.sizeBytesIsExact == false)
            #expect(expectedHeadHandle.sizeBytesIsExact)
            let schemeHandler = BridgeSchemeHandler(
                paneId: paneId,
                contentStore: controller.reviewContentStore,
                resourceLeaseRegistry: controller.resourceLeaseRegistry
            )

            let baseBody = try await contentBody(url: expectedBaseHandle.resourceUrl, handler: schemeHandler)
            let headBody = try await contentBody(url: expectedHeadHandle.resourceUrl, handler: schemeHandler)

            #expect(String(data: baseBody, encoding: .utf8) == baseText)
            #expect(String(data: headBody, encoding: .utf8) == headText)
            #expect(await provider.recordedContentRequestsCount(handleId: expectedBaseHandle.handleId) == 1)
            #expect(await provider.recordedContentRequestsCount(handleId: expectedHeadHandle.handleId) == 1)
        }

        @Test("modified base content descriptor does not advertise inexact size as expected bytes")
        func modifiedBaseContentDescriptorDoesNotAdvertiseInexactSizeAsExpectedBytes() throws {
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let baseText = "old source with extra bytes\nlet oldOnly = true\n"
            let headText = "new source\n"
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: Data(headText.utf8).count,
                oldContentHash: bridgeSHA256ContentHash(baseText),
                newContentHash: bridgeSHA256ContentHash(headText)
            )
            let expectedBaseHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: baseEndpoint,
                role: .base,
                reviewGeneration: 1
            )
            let expectedHeadHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: headEndpoint,
                role: .head,
                reviewGeneration: 1
            )
            let query = makeBridgeReviewQuery(
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId
            )
            let package = try BridgeReviewPackageBuilder.build(
                request: BridgeReviewPackageBuildRequest(
                    packageId: "package",
                    query: query,
                    comparison: BridgeEndpointComparison(
                        baseEndpoint: baseEndpoint,
                        headEndpoint: headEndpoint,
                        changedFiles: [changedFile]
                    ),
                    checkpointIds: [],
                    reviewGeneration: 1,
                    generatedAtUnixMilliseconds: 10
                )
            )
            let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
                request: BridgeReviewProtocolSnapshotBuildRequest(
                    paneId: "pane-1",
                    sourceIdentity: package.query.queryId,
                    streamId: "review:pane-1",
                    sequence: 1,
                    package: package,
                    selectedItemId: package.orderedItemIds.first,
                    visibleItemIds: package.orderedItemIds,
                    changesetCluster: nil
                )
            )
            let baseDescriptor = try #require(
                frame.comparison.contentDescriptors.first {
                    $0.descriptor.descriptorId == expectedBaseHandle.handleId
                }
            )
            let headDescriptor = try #require(
                frame.comparison.contentDescriptors.first {
                    $0.descriptor.descriptorId == expectedHeadHandle.handleId
                }
            )

            #expect(baseDescriptor.descriptor.content.expectedBytes == nil)
            #expect(baseDescriptor.descriptor.content.maxBytes == AppPolicies.Bridge.contentMaxBytesPerItem)
            #expect(headDescriptor.descriptor.content.expectedBytes == Data(headText.utf8).count)
            #expect(headDescriptor.descriptor.content.maxBytes == Data(headText.utf8).count)
        }

        @Test("modified review metadata exposes selected base and head content handles")
        func modifiedReviewMetadataExposesSelectedBaseAndHeadContentHandles() async throws {
            let capturedIntakeFrames = WebKitSerializedTests.BridgePaneControllerTests.SendableBox<[String]>([])
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let baseText = "old source\nlet removed = true\n"
            let headText = "new source\nlet added = true\n"
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "selected-modified",
                path: "Sources/App/Selected.swift",
                sizeBytes: Data(headText.utf8).count,
                oldContentHash: bridgeSHA256ContentHash(baseText),
                newContentHash: bridgeSHA256ContentHash(headText)
            )
            let expectedBaseHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: baseEndpoint,
                role: .base,
                reviewGeneration: 1
            )
            let expectedHeadHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: headEndpoint,
                role: .head,
                reviewGeneration: 1
            )
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [changedFile]
                ),
                contentByHandleId: [
                    expectedBaseHandle.handleId: makeContentResult(handle: expectedBaseHandle, data: baseText),
                    expectedHeadHandle.handleId: makeContentResult(handle: expectedHeadHandle, data: headText),
                ]
            )
            let paneId = UUIDv7.generate()
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedIntakeFrames.update { frames in
                        frames + [frameJSON]
                    }
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )

            let commandId = UUID()
            let result = await controller.handleDiffCommand(
                DiffCommand.loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            let capturedFrames = await capturedIntakeFrames.get()
            let snapshotPayload = try #require(
                capturedFrames.compactMap { frameJSON in
                    try? Self.reviewMetadataSnapshotEnvelope(frameJSON).payload
                }.first { payload in
                    payload.frameKind == "review.metadataSnapshot"
                }
            )
            #expect(snapshotPayload.selectedItemId == "item-selected-modified")
            let selectedItem = try #require(
                snapshotPayload.itemMetadata.first { $0.itemId == "item-selected-modified" }
            )
            #expect(selectedItem.contentRoles == ["base", "head"])
            let descriptorIdsByRole = try #require(selectedItem.contentDescriptorIdsByRole)
            #expect(descriptorIdsByRole.base == expectedBaseHandle.handleId)
            #expect(descriptorIdsByRole.head == expectedHeadHandle.handleId)
            let descriptorIds = Set(
                snapshotPayload.comparison.contentDescriptors.map(\.descriptor.descriptorId)
            )
            #expect(descriptorIds.contains(expectedBaseHandle.handleId))
            #expect(descriptorIds.contains(expectedHeadHandle.handleId))

            let schemeHandler = BridgeSchemeHandler(
                paneId: paneId,
                contentStore: controller.reviewContentStore,
                resourceLeaseRegistry: controller.resourceLeaseRegistry
            )
            let baseBody = try await contentBody(url: expectedBaseHandle.resourceUrl, handler: schemeHandler)
            let headBody = try await contentBody(url: expectedHeadHandle.resourceUrl, handler: schemeHandler)
            #expect(String(data: baseBody, encoding: .utf8) == baseText)
            #expect(String(data: headBody, encoding: .utf8) == headText)
        }

        private func contentBody(url: String, handler: BridgeSchemeHandler) async throws -> Data {
            _ = try #require(
                BridgeTransportResourceURL.parse(
                    url,
                    allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
                )
            )
            var body = Data()
            let request = URLRequest(url: try #require(URL(string: url)))
            for try await result in handler.reply(for: request) {
                switch result {
                case .response:
                    break
                case .data(let chunk):
                    body.append(chunk)
                @unknown default:
                    Issue.record("Unexpected URL scheme task result")
                }
            }
            return body
        }

        private static func reviewMetadataSnapshotEnvelope(
            _ frameJSON: String
        ) throws -> WorktreeFileIntakeEnvelope<ReviewMetadataSnapshotTestPayload> {
            let frameData = try #require(frameJSON.data(using: .utf8))
            return try JSONDecoder().decode(
                WorktreeFileIntakeEnvelope<ReviewMetadataSnapshotTestPayload>.self,
                from: frameData
            )
        }
    }
}

private struct ReviewMetadataSnapshotTestPayload: Decodable {
    let frameKind: String
    let comparison: ReviewMetadataSnapshotComparisonTestPayload
    let selectedItemId: String?
    let itemMetadata: [ReviewMetadataSnapshotItemTestPayload]
}

private struct ReviewMetadataSnapshotComparisonTestPayload: Decodable {
    let contentDescriptors: [SnapshotAttachedDescriptorPayload]
}

private struct SnapshotAttachedDescriptorPayload: Decodable {
    let descriptor: SnapshotResourceDescriptorPayload
}

private struct SnapshotResourceDescriptorPayload: Decodable {
    let descriptorId: String
}

private struct ReviewMetadataSnapshotItemTestPayload: Decodable {
    let itemId: String
    let contentRoles: [String]
    let contentDescriptorIdsByRole: SnapshotRoleDescriptorIdsPayload?
}

private struct SnapshotRoleDescriptorIdsPayload: Decodable {
    let base: String?
    let head: String?
}
