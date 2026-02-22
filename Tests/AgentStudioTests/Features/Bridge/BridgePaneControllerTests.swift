import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerTests {
        private struct DiffRequestFileContentsMethod: RPCMethod {
            struct Params: Decodable {
                let fileId: String
            }

            typealias Result = RPCNoResponse
            static let method = "diff.requestFileContents"
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

        private actor SendableBox<Value> {
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

        private func makeController() -> BridgePaneController {
            BridgePaneController(
                paneId: UUID(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil)
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
            let executedFileId = SendableBox<String?>(nil)

            controller.router.register(method: DiffRequestFileContentsMethod.self) { params in
                await executedFileId.set(params.fileId)
                return nil
            }

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{"fileId":"abc123"},"id":1}"#
            )

            // Assert
            #expect(controller.isBridgeReady == false)
            #expect((await executedFileId.get()) == nil)
        }

        @Test("ready command executes handler")
        func ready_command_executes_handler() async {
            // Arrange
            let controller = makeController()
            defer { controller.teardown() }
            let executedFileId = SendableBox<String?>(nil)

            controller.router.register(method: DiffRequestFileContentsMethod.self) { params in
                await executedFileId.set(params.fileId)
                return nil
            }

            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            #expect(controller.isBridgeReady == true)
            controller.paneState.connection.setHealth(.connected)

            // Act
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{"fileId":"abc123"},"id":1}"#
            )

            // Assert
            #expect((await executedFileId.get()) == "abc123")
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
                #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{},"id":1}"#
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

        @Test("handler failure emits rejected ack with reason")
        func handler_failure_emits_rejected_ack_with_reason() async {
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
            #expect(ack?.reason?.contains("simulated handler failure") == true)
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
                store: .diff,
                op: .merge,
                level: .hot,
                revision: 1,
                epoch: 1,
                json: Data([0xFF])
            )

            #expect(controller.paneState.connection.health == .connected)
        }

        @Test("pushJSON transport failure marks connection health as error")
        func pushJSON_transport_failure_marks_connection_error() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            controller.paneState.connection.setHealth(.connected)

            let validPayload = try JSONEncoder().encode(["ok": true])
            await controller.pushJSON(
                store: .diff,
                op: .merge,
                level: .hot,
                revision: 1,
                epoch: 1,
                json: validPayload
            )

            #expect(controller.paneState.connection.health == .error)
        }

        @Test("failed transport does not poison content dedup cache")
        func pushJSON_failed_transport_does_not_poison_dedup_cache() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            let validPayload = try JSONEncoder().encode(["ok": true])

            controller.paneState.connection.setHealth(.connected)
            await controller.pushJSON(
                store: .diff,
                op: .merge,
                level: .hot,
                revision: 1,
                epoch: 1,
                json: validPayload
            )
            #expect(controller.paneState.connection.health == .error)

            // Reset health and retry identical payload. If dedup was poisoned before successful
            // transport, this call would be skipped and health would stay connected.
            controller.paneState.connection.setHealth(.connected)
            await controller.pushJSON(
                store: .diff,
                op: .merge,
                level: .hot,
                revision: 2,
                epoch: 1,
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
    }
}
