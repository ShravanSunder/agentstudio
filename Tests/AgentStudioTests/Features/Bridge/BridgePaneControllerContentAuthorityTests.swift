import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerContentAuthorityTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        private actor FailsAfterFirstComparisonReviewSourceProvider: BridgeReviewSourceProvider {
            private let firstComparison: BridgeEndpointComparison
            private var comparisonCount = 0

            init(firstComparison: BridgeEndpointComparison) {
                self.firstComparison = firstComparison
            }

            func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
                request.endpoint
            }

            func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
                comparisonCount += 1
                guard comparisonCount == 1 else {
                    throw BridgeProviderFailure.providerUnavailable
                }
                return BridgeEndpointComparison(
                    baseEndpoint: request.baseEndpoint,
                    headEndpoint: request.headEndpoint,
                    changedFiles: firstComparison.changedFiles
                )
            }

            func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
                BridgeTreeReadResult(endpoint: request.endpoint, descriptors: [])
            }

            func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
                -> BridgeReviewItemDescriptor
            {
                makeBridgeReviewItemDescriptor(itemId: "item-\(request.path)", path: request.path, fileClass: .source)
            }

            func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws
                -> BridgeSourceEndpoint
            {
                makeBridgeEndpoint(endpointId: request.checkpointId, kind: .promptCheckpoint)
            }

            func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
                throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
            }
        }

        @Test("loadDiff revokes previous content authority before failed reload")
        func loadDiff_revokes_previous_content_authority_before_failed_reload() async throws {
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: 100,
                oldContentHash: bridgeSHA256ContentHash("old"),
                newContentHash: bridgeSHA256ContentHash("new")
            )
            let headHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: headEndpoint,
                role: .head,
                reviewGeneration: 1
            )
            let provider = FailsAfterFirstComparisonReviewSourceProvider(
                firstComparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [changedFile]
                )
            )
            let controller = makeController(
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            let firstCommandId = UUID()
            let secondCommandId = UUID()

            let firstResult = await controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: UUIDv7.generate(),
                        worktreeId: headEndpoint.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: firstCommandId,
                correlationId: nil
            )
            let headResource = try #require(
                BridgeTransportResourceURL.parse(
                    headHandle.resourceUrl,
                    allowedResourceKindsByProtocol: ["review": Set(["content"])]
                ))
            #expect(firstResult == .success(commandId: firstCommandId))
            #expect(await controller.resourceLeaseRegistry.contains(headResource, paneId: controller.paneId) == true)

            let secondResult = await controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: UUIDv7.generate(),
                        worktreeId: headEndpoint.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: secondCommandId,
                correlationId: nil
            )

            #expect(secondResult == .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider")))
            #expect(await controller.resourceLeaseRegistry.contains(headResource, paneId: controller.paneId) == false)
        }

        @Test("refresh preserves previous content authority when new metadata is invalid")
        func refresh_preserves_previous_content_authority_when_new_metadata_is_invalid() async throws {
            let fixture = makeRefreshRevisionFixture()
            defer { fixture.controller.teardown() }
            let initialHandle = BridgeReviewPackageBuilder.contentHandle(
                for: makeBridgeEndpointChangedFile(
                    fileId: "old",
                    path: "Sources/App/Old.swift",
                    sizeBytes: 100
                ),
                endpoint: fixture.headEndpoint,
                role: .head,
                reviewGeneration: 1
            )
            let initialResource = try #require(
                BridgeTransportResourceURL.parse(
                    initialHandle.resourceUrl,
                    allowedResourceKindsByProtocol: ["review": Set(["content"])]
                ))
            let loadResult = await fixture.controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: UUIDv7.generate(),
                        worktreeId: fixture.headEndpoint.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: fixture.commandId,
                correlationId: nil
            )
            #expect(loadResult == .success(commandId: fixture.commandId))
            #expect(
                await fixture.controller.resourceLeaseRegistry.contains(
                    initialResource, paneId: fixture.controller.paneId))

            let invalidRefreshFile = makeBridgeEndpointChangedFile(
                fileId: "bad-size",
                path: "Sources/App/BadSize.swift",
                sizeBytes: -1
            )
            await setRefreshComparison(fixture, changedFile: invalidRefreshFile)
            await postRefreshEvent(fixture, path: "Sources/App/BadSize.swift", batchSeq: 50)

            #expect(
                await fixture.controller.resourceLeaseRegistry.contains(
                    initialResource, paneId: fixture.controller.paneId))
            #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-old"])
        }

        @Test("teardown synchronously revokes review content leases")
        func teardown_synchronously_revokes_review_content_leases() async throws {
            let fixture = makeRefreshRevisionFixture()
            let initialHandle = BridgeReviewPackageBuilder.contentHandle(
                for: makeBridgeEndpointChangedFile(
                    fileId: "old",
                    path: "Sources/App/Old.swift",
                    sizeBytes: 100
                ),
                endpoint: fixture.headEndpoint,
                role: .head,
                reviewGeneration: 1
            )
            let initialResource = try #require(
                BridgeTransportResourceURL.parse(
                    initialHandle.resourceUrl,
                    allowedResourceKindsByProtocol: ["review": Set(["content"])]
                ))
            let loadResult = await fixture.controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: UUIDv7.generate(),
                        worktreeId: fixture.headEndpoint.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: fixture.commandId,
                correlationId: nil
            )
            #expect(loadResult == .success(commandId: fixture.commandId))
            #expect(
                await fixture.controller.resourceLeaseRegistry.contains(
                    initialResource, paneId: fixture.controller.paneId))

            fixture.controller.teardown()

            #expect(
                await fixture.controller.resourceLeaseRegistry.contains(
                    initialResource, paneId: fixture.controller.paneId) == false)
        }

        private func makeController(
            state: BridgePaneState,
            reviewSourceProvider: any BridgeReviewSourceProvider
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: state,
                reviewSourceProvider: reviewSourceProvider
            )
        }
    }
}
