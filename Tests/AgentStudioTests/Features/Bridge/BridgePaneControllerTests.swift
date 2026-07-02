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

        private struct AgentDedupProbeMethod: RPCMethod {
            struct Params: Decodable, Sendable {
                let token: String
            }

            typealias Result = RPCNoResponse
            static let method = "agent.dedupProbe"
        }

        private struct AgentFailureProbeMethod: RPCMethod {
            struct Params: Decodable, Sendable {}

            typealias Result = RPCNoResponse
            static let method = "agent.failureProbe"
        }

        actor SendableBox<Value> {
            private var value: Value

            init(_ value: Value) {
                self.value = value
            }

            func set(_ newValue: Value) {
                value = newValue
            }

            func get() -> Value {
                value
            }

            func update(_ transform: @Sendable (Value) -> Value) {
                value = transform(value)
            }
        }

        private func waitUntil(
            attempts: Int = 40,
            _ condition: @escaping () async -> Bool
        ) async -> Bool {
            for _ in 0..<attempts {
                if await condition() {
                    return true
                }
                await Task.yield()
            }
            return await condition()
        }

        private func settleAsyncCallbacks(turns: Int) async {
            for _ in 0..<turns {
                await Task.yield()
            }
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

        @Test("non-ready command does not execute handler")
        func nonReady_command_does_not_execute_handler() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            let executedToken = SendableBox<String?>(nil)

            controller.router.register(method: AgentDedupProbeMethod.self) { params in
                await executedToken.set(params.token)
                return nil
            }

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"agent.dedupProbe","params":{"token":"abc123"},"id":1}"#
            )

            // Assert
            #expect(controller.isBridgeReady == false)
            #expect((await executedToken.get()) == nil)
        }

        @Test("ready command executes handler")
        func ready_command_executes_handler() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            let executedToken = SendableBox<String?>(nil)

            controller.router.register(method: AgentDedupProbeMethod.self) { params in
                await executedToken.set(params.token)
                return nil
            }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            #expect(controller.isBridgeReady == true)
            controller.paneState.connection.setHealth(.connected)

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"agent.dedupProbe","params":{"token":"abc123"},"id":1}"#
            )

            // Assert
            #expect((await executedToken.get()) == "abc123")
        }

        @Test("non-ready command requests with id return bridge-not-ready error")
        func nonReady_command_requests_with_id_return_bridge_not_ready_error() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            var errorCode: Int?
            controller.router.onError = { code, _, _ in errorCode = code }
            controller.router.onResponse = { _ in }

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"agent.dedupProbe","params":{},"id":1}"#
            )

            // Assert
            #expect(controller.isBridgeReady == false)
            #expect(errorCode == -32_004)
        }

        @Test("implemented review handlers succeed and stub handlers reject")
        func implemented_review_handlers_succeed_and_stub_handlers_reject() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            var errorCode: Int?
            controller.router.onError = { code, _, _ in errorCode = code }

            // Act + Assert: implemented handlers succeed
            errorCode = nil
            await controller.router.dispatch(
                json: #"{"jsonrpc":"2.0","method":"review.markFileViewed","params":{"fileId":"abc"},"id":1}"#,
                isBridgeReady: true
            )
            #expect(errorCode == nil)
            #expect(controller.paneState.review.viewedFiles.contains("abc"))

            errorCode = nil
            await controller.router.dispatch(
                json: #"{"jsonrpc":"2.0","method":"review.unmarkFileViewed","params":{"fileId":"abc"},"id":2}"#,
                isBridgeReady: true
            )
            #expect(errorCode == nil)
            #expect(controller.paneState.review.viewedFiles.contains("abc") == false)

            // Stubbed handlers reject with explicit error path
            errorCode = nil
            await controller.router.dispatch(
                json:
                    #"{"jsonrpc":"2.0","method":"review.addComment","params":{"fileId":"abc","lineNumber":12,"side":"left","text":"hello"},"id":1}"#,
                isBridgeReady: true
            )
            #expect(errorCode == -32_603)

            errorCode = nil
            await controller.router.dispatch(
                json: #"{"jsonrpc":"2.0","method":"agent.cancelTask","params":{"taskId":"task-001"},"id":3}"#,
                isBridgeReady: true
            )
            #expect(errorCode == -32_603)

            errorCode = nil
            await controller.router.dispatch(
                json: #"{"jsonrpc":"2.0","method":"system.resyncAgentEvents","params":{"fromSeq":42},"id":4}"#,
                isBridgeReady: true
            )
            #expect(errorCode == -32_603)
        }

        @Test("diff.loadDiff RPC publishes package metadata")
        func diff_loadDiff_rpc_publishes_package_metadata() async throws {
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
            controller.handleBridgeReady()
            let worktreeId = headEndpoint.worktreeId.uuidString

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"diff.loadDiff","params":{"worktreeId":"\#(worktreeId)"},"id":7}"#
            )

            #expect(controller.paneState.diff.status == DiffStatus.ready)
            #expect(controller.paneState.diff.error == nil)
            #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-source"])
            #expect(controller.paneState.diff.packageMetadata?.summary.filesChanged == 1)
        }

        @Test("diff.loadDiff RPC rejects missing worktree id")
        func diff_loadDiff_rpc_rejects_missing_worktree_id() async {
            let controller = makeController()
            defer { controller.teardown() }
            controller.handleBridgeReady()
            var errorCode: Int?
            controller.router.onError = { code, _, _ in errorCode = code }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"diff.loadDiff","params":{},"id":7}"#
            )

            #expect(errorCode == -32_602)
        }

        @Test("unknown method still returns 32601")
        func unknown_method_returns_32601() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            var errorCode: Int?
            controller.router.onError = { code, _, _ in errorCode = code }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            #expect(controller.isBridgeReady == true)

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"nonexistent.namespaceMethod","params":{},"id":"abc"}"#
            )

            // Assert
            #expect(errorCode == -32_601)
        }

        @Test("diff requestFileContents is not a production RPC surface")
        func diff_requestFileContents_is_not_registered() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            var errorCode: Int?
            controller.router.onError = { code, _, _ in errorCode = code }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            #expect(controller.isBridgeReady == true)

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{"fileId":"abc123"},"id":"content"}"#
            )

            // Assert
            #expect(errorCode == -32_601)
        }

        @Test("command success is emitted as agent ack")
        func command_success_emits_command_ack() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            var observedAck: CommandAck?
            controller.router.onCommandAck = { observedAck = $0 }

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{},"id":1}"#
            )
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"review.markFileViewed","params":{"fileId":"abc"},"__commandId":"cmd-001"}"#
            )

            // Assert
            #expect(observedAck?.commandId == "cmd-001")
            #expect(observedAck?.status == .ok)
            #expect(observedAck?.method == "review.markFileViewed")
        }

        @Test("first unique __commandId records one ack in agent state")
        func first_unique_commandId_records_one_ack_in_agent_state() async {
            let controller = makeController()
            defer { controller.teardown() }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"review.markFileViewed","params":{"fileId":"abc"},"__commandId":"cmd-unique-001"}"#
            )

            let ack = controller.paneState.commandAcks["cmd-unique-001"]
            #expect(controller.paneState.commandAcks.count == 1)
            #expect(ack?.status == .ok)
            #expect(ack?.method == "review.markFileViewed")
            #expect(ack?.reason == nil)
        }

        @Test("duplicate __commandId does not execute twice or emit duplicate ack")
        func duplicate_commandId_does_not_reexecute_or_duplicate_ack() async {
            let controller = makeController()
            defer { controller.teardown() }
            let executionCount = SendableBox(0)
            var ackCount = 0

            let originalCommandAckHandler = controller.router.onCommandAck
            controller.router.onCommandAck = { ack in
                originalCommandAckHandler(ack)
                if ack.commandId == "cmd-dedup-001" {
                    ackCount += 1
                }
            }
            controller.router.register(method: AgentDedupProbeMethod.self) { _ in
                await executionCount.update { $0 + 1 }
                return nil
            }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            let duplicatePayload =
                #"{"jsonrpc":"2.0","method":"agent.dedupProbe","params":{"token":"abc"},"__commandId":"cmd-dedup-001"}"#
            await controller.handleIncomingRPC(duplicatePayload)
            await controller.handleIncomingRPC(duplicatePayload)

            #expect(await executionCount.get() == 1)
            #expect(ackCount == 1)
            #expect(controller.paneState.commandAcks.count == 1)
            #expect(controller.paneState.commandAcks["cmd-dedup-001"]?.status == .ok)
        }

        @Test("handler failure emits rejected ack with stable public reason")
        func handler_failure_emits_rejected_ack_with_stable_public_reason() async {
            let controller = makeController()
            defer { controller.teardown() }

            controller.router.register(method: AgentFailureProbeMethod.self) { _ in
                throw NSError(
                    domain: "BridgePaneControllerTests",
                    code: 901,
                    userInfo: [NSLocalizedDescriptionKey: "simulated handler failure"]
                )
            }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"agent.failureProbe","params":{},"__commandId":"cmd-failure-001"}"#
            )

            let ack = controller.paneState.commandAcks["cmd-failure-001"]
            #expect(ack?.status == .rejected)
            #expect(ack?.method == "agent.failureProbe")
            #expect(ack?.reason == "Internal error")
        }

        @Test("teardown clears command acks")
        func teardown_clears_command_acks() async {
            let controller = makeController()
            defer { controller.teardown() }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"review.markFileViewed","params":{"fileId":"abc"},"__commandId":"cmd-clear-001"}"#
            )
            #expect(controller.paneState.commandAcks["cmd-clear-001"] != nil)

            controller.teardown()

            #expect(controller.paneState.commandAcks.isEmpty)
        }

        @Test("pushJSON encoding failure does not degrade connection health")
        func pushJSON_encoding_failure_does_not_mark_connection_error() async {
            let controller = makeController()
            defer { controller.teardown() }
            controller.paneState.connection.setHealth(.connected)

            await controller.pushJSON(
                metadata: makePushMetadata(revision: 1),
                json: Data([0xFF])
            )

            #expect(controller.paneState.connection.health == .connected)
        }

        @Test("pushJSON transport failure marks connection health as error")
        func pushJSON_transport_failure_marks_connection_error() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                pushEnvelopeSink: { _, _, _ in
                    throw NSError(domain: "BridgePaneControllerTests", code: 902)
                }
            )
            defer { controller.teardown() }
            controller.paneState.connection.setHealth(.connected)

            let validPayload = try JSONEncoder().encode(["ok": true])
            await controller.pushJSON(
                metadata: makePushMetadata(revision: 1),
                json: validPayload
            )

            #expect(controller.paneState.connection.health == .error)
        }

        @Test("failed transport does not poison content dedup cache")
        func pushJSON_failed_transport_does_not_poison_dedup_cache() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                pushEnvelopeSink: { _, _, _ in
                    throw NSError(domain: "BridgePaneControllerTests", code: 903)
                }
            )
            defer { controller.teardown() }
            let validPayload = try JSONEncoder().encode(["ok": true])

            controller.paneState.connection.setHealth(.connected)
            await controller.pushJSON(
                metadata: makePushMetadata(revision: 1),
                json: validPayload
            )
            #expect(controller.paneState.connection.health == .error)

            // Reset health and retry identical payload. If dedup was poisoned before successful
            // transport, this call would be skipped and health would stay connected.
            controller.paneState.connection.setHealth(.connected)
            await controller.pushJSON(
                metadata: makePushMetadata(revision: 2),
                json: validPayload
            )
            #expect(controller.paneState.connection.health == .error)
        }

        @Test("invalid router response payload marks connection health as error")
        func invalid_router_response_payload_marks_connection_error() async {
            let controller = makeController()
            defer { controller.teardown() }
            controller.paneState.connection.setHealth(.connected)

            await controller.router.onResponse("not-json")

            #expect(controller.paneState.connection.health == .error)
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
            let headResource = try #require(
                BridgeTransportResourceURL.parse(
                    headHandle.resourceUrl,
                    allowedResourceKindsByProtocol: ["review": Set(["content"])]
                ))
            #expect(await controller.resourceLeaseRegistry.contains(headResource, paneId: controller.paneId) == true)
        }

        @Test("loadDiff queues review metadata intake until bridge ready")
        func loadDiff_queues_review_metadata_intake_until_bridge_ready() async throws {
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
            let capturedIntakeFrames = SendableBox<[String]>([])
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider,
                pushEnvelopeSink: { _, _, _ in },
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedIntakeFrames.update { frames in
                        frames + [frameJSON]
                    }
                }
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

            #expect(await capturedIntakeFrames.get().isEmpty)
            #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 2)
            controller.handleBridgeReady()
            #expect(await capturedIntakeFrames.get().isEmpty)
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let capturedFrames = await capturedIntakeFrames.get()
            #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 0)
            #expect(capturedFrames.count == 2)
            let resetFrameJSON = try #require(capturedFrames.first)
            let snapshotFrameJSON = try #require(capturedFrames.last)
            let resetFrameObject = try Self.reviewIntakeFrameObject(resetFrameJSON)
            let snapshotFrameObject = try Self.reviewIntakeFrameObject(snapshotFrameJSON)
            let snapshotPayload = try #require(snapshotFrameObject["payload"] as? [String: Any])
            let comparisonObject = try #require(snapshotPayload["comparison"] as? [String: Any])
            #expect(result == .success(commandId: commandId))
            #expect(resetFrameObject["kind"] as? String == "reset")
            #expect(resetFrameObject["sequence"] as? Int == 0)
            #expect(snapshotFrameObject["sequence"] as? Int == 1)
            #expect(snapshotPayload["kind"] as? String == "metadataSnapshot")
            #expect(snapshotPayload["frameKind"] as? String == "review.metadataSnapshot")
            #expect(snapshotPayload["generation"] as? Int == resetFrameObject["generation"] as? Int)
            #expect(snapshotPayload["sequence"] as? Int == 1)
            #expect(comparisonObject["sourceIdentity"] as? String == "query-\(artifact.diffId.uuidString)")
            #expect(comparisonObject["rootDescriptor"] == nil)
            #expect(snapshotPayload["itemMetadata"] != nil)
            #expect(snapshotPayload["treeRows"] != nil)
            #expect(snapshotPayload["extentFacts"] != nil)
        }

        @Test("push and intake delivery share a serialized WebKit lane")
        func pushAndIntakeDeliveryShareSerializedWebKitLane() async throws {
            let events = SendableBox<[String]>([])
            let pushRelease = SendableBox<CheckedContinuation<Void, Never>?>(nil)
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                pushEnvelopeSink: { _, _, _ in
                    await events.update { $0 + ["push-start"] }
                    await withCheckedContinuation { continuation in
                        Task { await pushRelease.set(continuation) }
                    }
                    await events.update { $0 + ["push-end"] }
                },
                intakeFrameSink: { _, _, _ in
                    await events.update { $0 + ["intake-start"] }
                }
            )
            defer { controller.teardown() }

            let pushTask = Task { @MainActor in
                await controller.pushJSON(
                    metadata: BridgePushEnvelopeMetadata(
                        store: .diff,
                        op: .replace,
                        level: .hot,
                        slice: .diffStatus,
                        revision: 1,
                        epoch: 0
                    ),
                    json: Data(#"{"status":"loading","error":null,"epoch":0}"#.utf8)
                )
            }

            let didStartPush = await waitUntil {
                await events.get().contains("push-start")
            }
            #expect(didStartPush)

            let intakeTask = Task { @MainActor in
                await controller.deliverIntakeFrame(
                    #"{"kind":"snapshot","streamId":"review:test","generation":1,"sequence":0,"payload":{"value":true}}"#
                )
            }

            await settleAsyncCallbacks(turns: 20)
            #expect(await events.get() == ["push-start"])

            let release = try #require(await pushRelease.get())
            release.resume()

            let delivered = await intakeTask.value
            await pushTask.value

            #expect(delivered)
            #expect(await events.get() == ["push-start", "push-end", "intake-start"])
        }

        static func reviewIntakeFrameObject(_ frameJSON: String) throws -> [String: Any] {
            let frameData = try #require(frameJSON.data(using: .utf8))
            return try #require(JSONSerialization.jsonObject(with: frameData) as? [String: Any])
        }

        private func makePushMetadata(revision: Int) -> BridgePushEnvelopeMetadata {
            BridgePushEnvelopeMetadata(
                store: .diff,
                op: .merge,
                level: .hot,
                slice: .diffStatus,
                revision: revision,
                epoch: 1
            )
        }
    }
}
