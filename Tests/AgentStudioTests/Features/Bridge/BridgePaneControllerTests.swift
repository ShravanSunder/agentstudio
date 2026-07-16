import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        actor OutOfOrderBridgeReviewSourceProvider: BridgeReviewSourceProvider {
            private let firstGenerationComparison: BridgeEndpointComparison
            private let laterGenerationComparison: BridgeEndpointComparison
            private var firstGenerationStarted = false
            private var firstGenerationStartWaiters: [CheckedContinuation<Void, Never>] = []
            private var firstGenerationReleaseContinuations: [CheckedContinuation<Void, Never>] = []

            init(
                firstGenerationComparison: BridgeEndpointComparison,
                laterGenerationComparison: BridgeEndpointComparison
            ) {
                self.firstGenerationComparison = firstGenerationComparison
                self.laterGenerationComparison = laterGenerationComparison
            }

            func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
                request.endpoint
            }

            func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
                if request.reviewGeneration == 1 {
                    firstGenerationStarted = true
                    resumeFirstGenerationStartWaiters()
                    await withCheckedContinuation { continuation in
                        firstGenerationReleaseContinuations.append(continuation)
                    }
                    return firstGenerationComparison
                }
                return BridgeEndpointComparison(
                    baseEndpoint: request.baseEndpoint,
                    headEndpoint: request.headEndpoint,
                    changedFiles: laterGenerationComparison.changedFiles
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

            func waitForFirstGenerationStarted() async {
                guard !firstGenerationStarted else { return }
                await withCheckedContinuation { continuation in
                    firstGenerationStartWaiters.append(continuation)
                }
            }

            func releaseFirstGeneration() {
                let continuations = firstGenerationReleaseContinuations
                firstGenerationReleaseContinuations.removeAll()
                for continuation in continuations {
                    continuation.resume()
                }
            }

            private func resumeFirstGenerationStartWaiters() {
                let waiters = firstGenerationStartWaiters
                firstGenerationStartWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        func makeController(
            state: BridgePaneState = BridgePaneState(panelKind: .diffViewer, source: nil),
            reviewSourceProvider: (any BridgeReviewSourceProvider)? = nil,
            telemetryScopeGate: BridgeTelemetryScopeGate? = nil,
            telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil,
            traceContextFactory: BridgeTraceContextFactory = .live
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: state,
                reviewSourceProvider: reviewSourceProvider,
                telemetryScopeGate: telemetryScopeGate,
                telemetryRecorder: telemetryRecorder,
                traceContextFactory: traceContextFactory
            )
        }

        @Test("handleBridgeReady sets bridge readiness and teardown resets it")
        func handleBridgeReady_setsReadyAndTeardownResets() {
            let controller = makeController()
            defer { controller.teardown() }

            #expect(controller.isBridgeReady == false)

            controller.handleBridgeReady()
            #expect(controller.isBridgeReady == true)

            controller.teardown()
            #expect(controller.isBridgeReady == false)
        }

        @Test("handleBridgeReady is idempotent while ready")
        func handleBridgeReady_isIdempotent() {
            let controller = makeController()
            defer { controller.teardown() }

            controller.handleBridgeReady()
            #expect(controller.isBridgeReady == true)

            controller.handleBridgeReady()
            #expect(controller.isBridgeReady == true)
        }

        @Test("teardown allows bridge ready cycle to restart")
        func teardown_allowsReadyToRestartAfterReset() {
            let controller = makeController()
            defer { controller.teardown() }

            controller.handleBridgeReady()
            #expect(controller.isBridgeReady == true)

            controller.teardown()
            #expect(controller.isBridgeReady == false)

            controller.handleBridgeReady()
            #expect(controller.isBridgeReady == true)
        }

        @Test("loadDiff publishes package metadata and registers content handles")
        func loadDiff_publishes_package_metadata_and_registers_content_handles() async throws {
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFile = makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: 100,
                oldContentHash: bridgeSHA256ContentHash("old"),
                newContentHash: bridgeSHA256ContentHash("new")
            )
            let baseHandle = BridgeReviewPackageBuilder.contentHandle(
                for: changedFile,
                endpoint: baseEndpoint,
                role: .base,
                reviewGeneration: 1
            )
            let headHandle = BridgeReviewPackageBuilder.contentHandle(
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
                    baseHandle.handleId: makeContentResult(handle: baseHandle, data: "old"),
                    headHandle.handleId: makeContentResult(handle: headHandle, data: "new"),
                ]
            )
            let controller = makeController(
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider
            )
            defer { controller.teardown() }
            let commandId = UUID()
            let artifact = DiffArtifact(
                diffId: UUIDv7.generate(),
                worktreeId: headEndpoint.worktreeId,
                patchData: Data()
            )

            let result = await controller.handleDiffCommand(
                .loadDiff(artifact),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            #expect(controller.paneState.diff.status == .ready)
            #expect(controller.paneState.diff.error == nil)
            #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-source"])
            #expect(controller.paneState.diff.packageMetadata?.summary.filesChanged == 1)
            #expect(await provider.recordedContentRequestsCount() == 0)
            let registered = try await controller.reviewContentStore.load(
                handleId: headHandle.handleId,
                requestedGeneration: 1
            )
            #expect(registered.handle == headHandle)
        }
    }
}
