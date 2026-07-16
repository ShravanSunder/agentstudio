import Foundation

@MainActor
extension AppDelegate {
    #if DEBUG
        func runBridgeProductStreamWebKitFeasibilityDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.bridge_product_stream_webkit.activation_started",
                phase: "startup_diagnostic_action",
                attributes: startupDiagnosticTraceAttributes(for: action)
            )

            let result: BridgeProductStreamFeasibilityDiagnosticResult
            do {
                let workerAsset = try await BridgeAppAssetStore().load(
                    relativePath: "assets/bridge-product-stream-webkit-feasibility-worker.js"
                )
                guard let workerSource = String(data: workerAsset.data, encoding: .utf8) else {
                    recordBridgeProductStreamWebKitFeasibilityResult(
                        action: action,
                        result: .unavailable(reason: "worker_asset_invalid_utf8")
                    )
                    return
                }
                let proof = await BridgeProductStreamWebKitFeasibilityDiagnostic.run(
                    workerSource: workerSource,
                    timeout: .seconds(8)
                )
                result = BridgeProductStreamFeasibilityDiagnosticResult(proof: proof)
            } catch {
                result = .unavailable(reason: "worker_asset_unavailable")
            }

            recordBridgeProductStreamWebKitFeasibilityResult(action: action, result: result)
        }

        private func recordBridgeProductStreamWebKitFeasibilityResult(
            action: AgentStudioStartupDiagnosticAction,
            result: BridgeProductStreamFeasibilityDiagnosticResult
        ) {
            let outcome = result.carrierSucceeded ? "succeeded" : "blocked"
            let attributes = startupDiagnosticTraceAttributes(for: action).merging(
                result.attributes
            ) { _, newValue in newValue }

            if result.carrierSucceeded {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.command_exercised",
                    phase: "startup_diagnostic_action",
                    outcome: outcome,
                    attributes: attributes
                )
            }
            startupTraceRecorder.recordAppStartup(
                result.carrierSucceeded
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
        }
    #endif
}

#if DEBUG
    struct BridgeProductStreamFeasibilityDiagnosticResult: Equatable {
        private static let expectedCancellationOrder: [BridgeWebKitFeasibilityCancellationEvent] = [
            .producerStopped, .producerUnregistered, .resultAcknowledged,
        ]

        let carrierSucceeded: Bool
        let authenticationBeforeBodySucceeded: Bool
        let bodyCapBeforeDecodeSucceeded: Bool
        let strictRouteDecodeSucceeded: Bool
        let missingContentLengthAccepted: Bool
        let exactRequestBodyBytesSucceeded: Bool
        let bodyReadCount: Int
        let bodyReadByteCount: Int
        let decodeCallCount: Int
        let providerCallCount: Int
        let unauthorizedBodyReadCount: Int
        let validBodyByteCount: Int
        let firstFrameByteCount: Int
        let validStreamEnded: Bool
        let workerStartPostObserved: Bool
        let workerObservedExactFrames: Bool
        let workerObservedIncrementalFrames: Bool
        let framedStreamSucceeded: Bool
        let workerObservedCancellation: Bool
        let abortCausalCancellationSucceeded: Bool
        let frameReceiptCount: Int
        let cancellationEventCount: Int
        let activeProducerCount: Int
        let activeProducerTaskCount: Int
        let queuedFrameCount: Int
        let maximumQueuedFrameCount: Int
        let producerOverflowCount: Int
        let postTerminalFrameCount: Int
        let failureReason: String

        init(proof: BridgeProductStreamWebKitFeasibilityProof) {
            let framedStreamSucceeded =
                proof.validStreamEnded
                && proof.workerObservedExactFrames
                && proof.workerObservedIncrementalFrames
                && proof.frameReceiptCount == 4
            let abortCausalCancellationSucceeded =
                proof.workerObservedCancellation
                && proof.cancellationOrder == Self.expectedCancellationOrder
                && proof.activeProducerCount == 0
                && proof.activeProducerTaskCount == 0
                && proof.queuedFrameCount == 0
                && proof.producerOverflowCount == 0
                && proof.postTerminalFrameCount == 0

            carrierSucceeded = proof.succeeded && framedStreamSucceeded && abortCausalCancellationSucceeded
            authenticationBeforeBodySucceeded = proof.authenticationBeforeBodySucceeded
            bodyCapBeforeDecodeSucceeded = proof.bodyCapBeforeDecodeSucceeded
            strictRouteDecodeSucceeded = proof.strictRouteDecodeSucceeded
            missingContentLengthAccepted = proof.missingContentLengthAccepted
            exactRequestBodyBytesSucceeded = proof.exactRequestBodyBytesSucceeded
            bodyReadCount = proof.bodyReadCount
            bodyReadByteCount = proof.bodyReadByteCount
            decodeCallCount = proof.decodeCallCount
            providerCallCount = proof.providerCallCount
            unauthorizedBodyReadCount = proof.unauthorizedBodyReadCount
            validBodyByteCount = proof.validBodyByteCount
            firstFrameByteCount = proof.firstFrameByteCount
            validStreamEnded = proof.validStreamEnded
            workerStartPostObserved = proof.workerStartPostObserved
            workerObservedExactFrames = proof.workerObservedExactFrames
            workerObservedIncrementalFrames = proof.workerObservedIncrementalFrames
            self.framedStreamSucceeded = framedStreamSucceeded
            workerObservedCancellation = proof.workerObservedCancellation
            self.abortCausalCancellationSucceeded = abortCausalCancellationSucceeded
            frameReceiptCount = proof.frameReceiptCount
            cancellationEventCount = proof.cancellationOrder.count
            activeProducerCount = proof.activeProducerCount
            activeProducerTaskCount = proof.activeProducerTaskCount
            queuedFrameCount = proof.queuedFrameCount
            maximumQueuedFrameCount = proof.maximumQueuedFrameCount
            producerOverflowCount = proof.producerOverflowCount
            postTerminalFrameCount = proof.postTerminalFrameCount
            failureReason = proof.failureReason
        }

        var attributes: [String: AgentStudioTraceValue] {
            let prefix = "agentstudio.startup_diagnostic.bridge.product_stream_webkit"
            return [
                "\(prefix).carrier.succeeded": .bool(carrierSucceeded),
                "\(prefix).authentication_before_body.succeeded": .bool(authenticationBeforeBodySucceeded),
                "\(prefix).body_cap_before_decode.succeeded": .bool(bodyCapBeforeDecodeSucceeded),
                "\(prefix).strict_route_decode.succeeded": .bool(strictRouteDecodeSucceeded),
                "\(prefix).missing_content_length.accepted": .bool(missingContentLengthAccepted),
                "\(prefix).exact_request_body_bytes.succeeded": .bool(exactRequestBodyBytesSucceeded),
                "\(prefix).total_body_read.count": .int(bodyReadCount),
                "\(prefix).total_body_read_byte.count": .int(bodyReadByteCount),
                "\(prefix).total_decode_call.count": .int(decodeCallCount),
                "\(prefix).total_provider_call.count": .int(providerCallCount),
                "\(prefix).unauthorized_body_read.count": .int(unauthorizedBodyReadCount),
                "\(prefix).valid_body_byte.count": .int(validBodyByteCount),
                "\(prefix).first_frame_byte.count": .int(firstFrameByteCount),
                "\(prefix).valid_stream_ended": .bool(validStreamEnded),
                "\(prefix).worker_start_post.observed": .bool(workerStartPostObserved),
                "\(prefix).worker_observed_exact_frames": .bool(workerObservedExactFrames),
                "\(prefix).worker_observed_incremental_frames": .bool(workerObservedIncrementalFrames),
                "\(prefix).framed_stream.succeeded": .bool(framedStreamSucceeded),
                "\(prefix).worker_observed_cancellation": .bool(workerObservedCancellation),
                "\(prefix).abort_causal_cancellation.succeeded": .bool(abortCausalCancellationSucceeded),
                "\(prefix).frame_receipt.count": .int(frameReceiptCount),
                "\(prefix).cancellation_event.count": .int(cancellationEventCount),
                "\(prefix).active_producer.count": .int(activeProducerCount),
                "\(prefix).active_producer_task.count": .int(activeProducerTaskCount),
                "\(prefix).queued_frame.count": .int(queuedFrameCount),
                "\(prefix).maximum_queued_frame.count": .int(maximumQueuedFrameCount),
                "\(prefix).producer_overflow.count": .int(producerOverflowCount),
                "\(prefix).post_terminal_frame.count": .int(postTerminalFrameCount),
                "\(prefix).failure.reason": .string(failureReason),
            ]
        }

        static func unavailable(reason: String) -> Self {
            Self(proof: .failed(reason: reason))
        }
    }
#endif
