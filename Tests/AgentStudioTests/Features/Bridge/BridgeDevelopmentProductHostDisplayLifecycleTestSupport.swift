import Foundation
import Testing

@testable import AgentStudioBridge

struct DevelopmentDisplayReviewReplayObservation {
    let identity: BridgeProductReviewBatchPublicationRecord
    let itemCount: Int
    let partCount: Int
}

@MainActor
struct DevelopmentDisplayMetadataStream {
    private var frameIterator: AsyncThrowingStream<BridgeProductMetadataFrame, any Error>.Iterator
    private let consumer: Task<Void, Never>

    init(
        frameIterator: AsyncThrowingStream<BridgeProductMetadataFrame, any Error>.Iterator,
        consumer: Task<Void, Never>
    ) {
        self.frameIterator = frameIterator
        self.consumer = consumer
    }

    mutating func requireOpeningFrameAndAcknowledge(
        using worker: DevelopmentDisplayWorkerClient
    ) async throws {
        let frame = try await nextFrame()
        try await worker.acknowledge(frame.producerFrameIdentity)
        guard case .metadataStreamAccepted = frame else {
            throw DevelopmentDisplayWorkerClientError.expectedMetadataStreamOpening
        }
    }

    mutating func consumeCompleteReviewPublication(
        expectedItemCount: Int,
        using worker: DevelopmentDisplayWorkerClient
    ) async throws -> DevelopmentDisplayReviewReplayObservation {
        var acceptedReviewSubscription = false
        var activeBegin: BridgeProductBatchBeginFrame?
        var partsByIndex: [Int: BridgeProductBatchPart] = [:]

        while true {
            let frame = try await nextFrame()
            if case .batch(.part(let part)) = frame {
                try await worker.acknowledge(part)
            } else if case .batch = frame {
                // Batch boundaries have no E3 stream-frame receipt.
            } else {
                try await worker.acknowledge(frame.producerFrameIdentity)
            }
            switch frame {
            case .subscriptionAccepted(let accepted):
                if accepted.subscriptionIdentity.subscriptionKind == .reviewMetadata {
                    acceptedReviewSubscription = true
                }
            case .batch(let batch):
                guard batch.identity.subscriptionKind == .reviewMetadata else { continue }
                switch batch {
                case .begin(let begin):
                    activeBegin = begin
                    partsByIndex.removeAll(keepingCapacity: true)
                case .part(let part):
                    guard part.identity.batchId == activeBegin?.identity.batchId else {
                        throw DevelopmentDisplayWorkerClientError.incompleteReviewMetadataLifecycle
                    }
                    partsByIndex[part.partIndex] = part.part
                case .complete(let complete):
                    guard acceptedReviewSubscription, let begin = activeBegin,
                        complete.identity.batchId == begin.identity.batchId,
                        complete.coveredScope == begin.scope,
                        partsByIndex.count == begin.partCount
                    else {
                        throw DevelopmentDisplayWorkerClientError.incompleteReviewMetadataLifecycle
                    }
                    var publication: BridgeProductReviewBatchPublicationRecord?
                    var itemIDs: Set<String> = []
                    for index in 0..<begin.partCount {
                        guard let part = partsByIndex[index],
                            case .put(let key, let revision, let value) = part,
                            revision <= begin.targetRevision
                        else {
                            throw DevelopmentDisplayWorkerClientError.incompleteReviewMetadataLifecycle
                        }
                        let record = try BridgeProductStrictJSON.decode(
                            BridgeProductReviewBatchRecord.self,
                            from: JSONEncoder().encode(value)
                        )
                        switch record {
                        case .item(let item):
                            guard key == item.itemId, itemIDs.insert(item.itemId).inserted else {
                                throw DevelopmentDisplayWorkerClientError.incompleteReviewMetadataLifecycle
                            }
                        case .publication(let installedPublication):
                            guard key == "publication", publication == nil else {
                                throw DevelopmentDisplayWorkerClientError.incompleteReviewMetadataLifecycle
                            }
                            publication = installedPublication
                        }
                    }
                    guard let publication, itemIDs.count == expectedItemCount,
                        begin.publicationId == publication.publicationId
                    else {
                        throw DevelopmentDisplayWorkerClientError.unexpectedReviewItemCount(
                            expected: expectedItemCount,
                            received: itemIDs.count
                        )
                    }
                    return .init(
                        identity: publication,
                        itemCount: itemIDs.count,
                        partCount: begin.partCount
                    )
                }
            case .metadataStreamError, .subscriptionReset, .subscriptionEnd:
                throw DevelopmentDisplayWorkerClientError.reviewMetadataTerminatedBeforeFinalWindow
            case .contentCancelled, .metadataStreamAccepted, .panePresentation,
                .paneSurfaceSelectionRequested, .subscriptionCancelled:
                continue
            }
        }
    }

    func stop() async {
        consumer.cancel()
        await consumer.value
    }

    private mutating func nextFrame() async throws -> BridgeProductMetadataFrame {
        // One sequential consumer owns this iterator; do not lend an actor-isolated
        // stored property to a mutating async call across its suspension.
        var iterator = frameIterator
        defer { frameIterator = iterator }
        guard let frame = try await iterator.next(isolation: #isolation) else {
            throw DevelopmentDisplayWorkerClientError.metadataStreamEndedBeforeExpectedFrame
        }
        return frame
    }
}

@MainActor
final class DevelopmentDisplayWorkerClient {
    private let capabilityHeader: String
    private let host: BridgeDevelopmentProductHost
    private var nextRequestSequence = 1
    let paneSessionId: String
    let workerInstanceId: String

    init(host: BridgeDevelopmentProductHost, delivery: Data) throws {
        let envelope = try decodeDevelopmentDisplayBootstrapEnvelope(delivery)
        capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            Array(envelope.capabilityBytes)
        )
        self.host = host
        paneSessionId = envelope.bootstrap.paneSessionId
        workerInstanceId = envelope.bootstrap.workerInstanceId
    }

    func openSession() async throws {
        let response = try await sendControl(
            body: [
                "kind": "workerSession.open",
                "paneSessionId": paneSessionId,
                "request": NSNull(),
                "requestId": requestId("open"),
                "requestSequence": takeRequestSequence(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": workerInstanceId,
            ]
        )
        guard case .workerSessionAccepted(let accepted) = response else {
            Issue.record("Expected the development-host worker session to open")
            return
        }
        #expect(accepted.correlation.paneSessionId == paneSessionId)
        #expect(accepted.correlation.workerInstanceId == workerInstanceId)
    }

    func admitReviewPublication(
        candidatePublicationId: UUID,
        expectedDisplayedPublicationId: UUID?,
        workerDerivationEpoch: Int = 0
    ) async throws -> Bool {
        let expectedDisplayedPublicationValue: Any =
            if let expectedDisplayedPublicationId {
                expectedDisplayedPublicationId.uuidString.lowercased()
            } else {
                NSNull()
            }
        let response = try await sendProductCall(
            method: "review.publication.install.admit",
            request: [
                "candidatePublicationId": candidatePublicationId.uuidString.lowercased(),
                "expectedDisplayedPublicationId": expectedDisplayedPublicationValue,
            ],
            workerDerivationEpoch: workerDerivationEpoch
        )
        guard case .callCompleted(let completed) = response,
            case .reviewPublicationInstallAdmission(let result) = completed.call
        else {
            Issue.record("Expected a typed Review publication install-admission result")
            return false
        }
        return result.status == .admitted
    }

    func applyReviewPublication(
        _ publicationId: UUID,
        workerDerivationEpoch: Int = 0
    ) async throws {
        let response = try await sendProductCall(
            method: "review.publication.applied",
            request: ["publicationId": publicationId.uuidString.lowercased()],
            workerDerivationEpoch: workerDerivationEpoch
        )
        guard case .callCompleted(let completed) = response,
            completed.call == .reviewPublicationApplied
        else {
            Issue.record("Expected a typed Review publication applied result")
            return
        }
    }

    func activateReviewViewerMode() async throws {
        let response = try await sendProductCall(
            method: "review.activeViewerMode.update",
            request: [
                "activeSource": NSNull(),
                "nativeSelectionRequestId": NSNull(),
                "sequence": 1,
                "sessionId": "development-display-viewer-mode",
            ]
        )
        guard case .callCompleted(let completed) = response,
            completed.call == .reviewActiveViewerModeUpdate
        else {
            Issue.record("Expected a typed Review active-viewer update result")
            return
        }
    }

    func openReviewMetadataSubscription(workerDerivationEpoch: Int = 1) async throws {
        let response = try await sendControl(
            body: controlIdentity(
                kind: "subscription.open",
                workerDerivationEpoch: workerDerivationEpoch
            ).merging([
                "subscription": ["subscriptionKind": "review.metadata"],
                "subscriptionId": "review-subscription-\(workerInstanceId.lowercased())",
            ]) { _, new in new }
        )
        guard case .subscriptionOpenAccepted(let accepted) = response,
            accepted.subscriptionKind == .reviewMetadata
        else {
            throw DevelopmentDisplayWorkerClientError.unexpectedControlResponse
        }
        let scopeResponse = try await sendControl(
            body: controlIdentity(
                kind: "subscription.setScope",
                workerDerivationEpoch: workerDerivationEpoch
            ).merging([
                "domain": "default",
                "handle": "review-view-\(workerInstanceId.lowercased())",
                "incarnation": "review-incarnation-\(workerInstanceId.lowercased())",
                "scopeRevision": 1,
                "scope": ["kind": "review", "interests": []],
                "subscriptionId": accepted.subscriptionId,
                "subscriptionKind": "review.metadata",
            ]) { _, new in new }
        )
        guard case .viewAccepted(let scope) = scopeResponse, scope.kind == .scope else {
            throw DevelopmentDisplayWorkerClientError.unexpectedControlResponse
        }
    }

    func startMetadataStream() throws -> DevelopmentDisplayMetadataStream {
        let metadataStreamId = "metadata-stream-\(workerInstanceId.lowercased())"
        let request = try routedRequest(
            route: BridgeProductWireContract.streamRoute,
            body: [
                "kind": "metadataStream.open",
                "metadataStreamId": metadataStreamId,
                "paneSessionId": paneSessionId,
                "resumeFromStreamSequence": NSNull(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": workerInstanceId,
            ]
        )
        let (frames, continuation) =
            AsyncThrowingStream<BridgeProductMetadataFrame, any Error>.makeStream()
        let consumer = Task { [host] in
            do {
                let decoder = try BridgeProductMetadataFrameDecoder()
                for try await result in await host.route(request) {
                    switch result {
                    case .response(let response):
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                            throw DevelopmentDisplayWorkerClientError.unexpectedMetadataStreamResponse
                        }
                    case .data(let data):
                        for frame in try decoder.append(data) {
                            continuation.yield(frame)
                        }
                    @unknown default:
                        throw DevelopmentDisplayWorkerClientError.unexpectedMetadataStreamResponse
                    }
                }
                try decoder.finish()
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return DevelopmentDisplayMetadataStream(
            frameIterator: frames.makeAsyncIterator(),
            consumer: consumer
        )
    }

    func acknowledge(_ frameIdentity: BridgeProductMetadataFrameIdentity) async throws {
        let response = try await collectRouteResponse(
            try routedRequest(
                route: BridgeProductWireContract.commandRoute,
                body: [
                    "kind": "stream.frameObserved",
                    "metadataStreamId": frameIdentity.metadataStreamId,
                    "paneSessionId": frameIdentity.paneSessionId,
                    "streamKind": "metadata",
                    "streamSequence": frameIdentity.streamSequence,
                    "wireVersion": frameIdentity.wireVersion,
                    "workerInstanceId": frameIdentity.workerInstanceId,
                ]
            )
        )
        guard response.statusCode == 204, response.body.isEmpty else {
            throw DevelopmentDisplayWorkerClientError.unexpectedFrameAcknowledgementResponse
        }
    }

    func acknowledge(_ part: BridgeProductBatchPartFrame) async throws {
        let identity = part.identity
        let requestObject: [String: Any] = [
            "kind": "subscription.acknowledge",
            "domain": identity.domain,
            "handle": identity.handle,
            "incarnation": identity.incarnation,
            "paneSessionId": identity.frame.paneSessionId,
            "receivedThroughDeliverySequence": part.deliverySequence,
            "subscriptionId": identity.subscriptionId,
            "wireVersion": identity.frame.wireVersion,
            "workerInstanceId": identity.frame.workerInstanceId,
        ]
        let requestBytes = try JSONSerialization.data(withJSONObject: requestObject, options: [.sortedKeys])
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductViewAcknowledgementRequest.self,
            from: requestBytes
        )
        let response = try await collectRouteResponse(
            try routedRequest(
                route: BridgeProductWireContract.commandRoute,
                body: requestObject
            )
        )
        guard response.statusCode == 200 else {
            throw DevelopmentDisplayWorkerClientError.unexpectedFrameAcknowledgementResponse
        }
        let acknowledged = try BridgeProductStrictJSON.decode(
            BridgeProductViewAcknowledgedResponse.self,
            from: response.body
        )
        #expect(acknowledged == .init(correlating: request))
    }

    private func sendProductCall(
        method: String,
        request: [String: Any],
        workerDerivationEpoch: Int = 0
    ) async throws -> BridgeProductControlResponse {
        try await sendControl(
            body: controlIdentity(
                kind: "product.call",
                workerDerivationEpoch: workerDerivationEpoch
            ).merging([
                "call": ["method": method, "request": request]
            ]) { _, new in new }
        )
    }

    private func sendControl(body: [String: Any]) async throws -> BridgeProductControlResponse {
        let admissionReply = try await collectRouteResponse(
            try routedRequest(route: BridgeProductWireContract.commandRoute, body: body)
        )
        #expect(admissionReply.statusCode == 200)
        let admission = try BridgeProductStrictJSON.decode(
            BridgeProductOperationAdmittedResponse.self,
            from: admissionReply.body
        )
        let resultReply = try await collectRouteResponse(
            try routedRequest(
                route: BridgeProductWireContract.commandRoute,
                body: [
                    "kind": "operation.result",
                    "operationId": admission.operationId,
                    "paneSessionId": paneSessionId,
                    "wireVersion": BridgeProductWireContract.version,
                    "workerInstanceId": workerInstanceId,
                ]
            )
        )
        #expect(resultReply.statusCode == 200)
        let result = try BridgeProductStrictJSON.decode(
            BridgeProductOperationResultResponse.self,
            from: resultReply.body
        )
        let acknowledgementReply = try await collectRouteResponse(
            try routedRequest(
                route: BridgeProductWireContract.commandRoute,
                body: [
                    "kind": "operation.resultAcknowledgement",
                    "operationId": admission.operationId,
                    "paneSessionId": paneSessionId,
                    "requestId": requestId("result-ack"),
                    "requestSequence": takeRequestSequence(),
                    "wireVersion": BridgeProductWireContract.version,
                    "workerInstanceId": workerInstanceId,
                ]
            )
        )
        #expect(acknowledgementReply.statusCode == 200)
        _ = try BridgeProductStrictJSON.decode(
            BridgeProductOperationResultAcknowledgedResponse.self,
            from: acknowledgementReply.body
        )
        guard result.outcome == .succeeded, let responseValue = result.result else {
            throw DevelopmentDisplayWorkerClientError.unexpectedControlResponse
        }
        return try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: JSONEncoder().encode(responseValue)
        )
    }

    private func routedRequest(route: String, body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: route) else {
            throw DevelopmentDisplayWorkerClientError.invalidRoute
        }
        var request = URLRequest(url: url)
        request.httpMethod = BridgeProductWireContract.requestMethod
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            capabilityHeader,
            forHTTPHeaderField: BridgeProductWireContract.capabilityHeaderName
        )
        return request
    }

    private func collectRouteResponse(
        _ request: URLRequest
    ) async throws -> (statusCode: Int, body: Data) {
        var body = Data()
        var statusCode: Int?
        for try await result in await host.route(request) {
            switch result {
            case .response(let response):
                statusCode = (response as? HTTPURLResponse)?.statusCode
            case .data(let data):
                body.append(data)
            @unknown default:
                throw DevelopmentDisplayWorkerClientError.unexpectedControlResponse
            }
        }
        guard let statusCode else {
            throw DevelopmentDisplayWorkerClientError.unexpectedControlResponse
        }
        return (statusCode, body)
    }

    private func controlIdentity(
        kind: String,
        workerDerivationEpoch: Int
    ) -> [String: Any] {
        [
            "kind": kind,
            "paneSessionId": paneSessionId,
            "requestId": requestId(kind),
            "requestSequence": takeRequestSequence(),
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": workerDerivationEpoch,
            "workerInstanceId": workerInstanceId,
        ]
    }

    private func takeRequestSequence() -> Int {
        defer { nextRequestSequence += 1 }
        return nextRequestSequence
    }

    private func requestId(_ operation: String) -> String {
        "development-display-\(workerInstanceId)-\(nextRequestSequence)-\(operation)"
    }
}

@MainActor
func withMainActorShutdownDevelopmentProductHost<Result>(
    _ host: BridgeDevelopmentProductHost,
    operation: () async throws -> Result
) async throws -> Result {
    do {
        let result = try await operation()
        await host.shutdown()
        return result
    } catch {
        await host.shutdown()
        throw error
    }
}

func developmentDisplayBootstrapRequest(
    paneSessionId: String? = nil,
    reason: String,
    surface: String = "review",
    tabId: String = "owner-tab-1"
) throws -> BridgeDevelopmentProductBootstrapRequest {
    var request: [String: Any] = [
        "navigationIntent": [
            "commandId": "open-\(surface)-view",
            "commandKind": "activateContext",
            "surface": surface,
        ],
        "reason": reason,
        "tabId": tabId,
    ]
    if let paneSessionId {
        request["paneSessionId"] = paneSessionId
    }
    return try JSONDecoder().decode(
        BridgeDevelopmentProductBootstrapRequest.self,
        from: JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    )
}

private struct DecodedDevelopmentDisplayBootstrapEnvelope {
    let bootstrap: BridgeProductSessionBootstrap
    let capabilityBytes: Data
}

private func decodeDevelopmentDisplayBootstrapEnvelope(
    _ data: Data
) throws -> DecodedDevelopmentDisplayBootstrapEnvelope {
    let prefixByteCount = 5
    guard data.count >= prefixByteCount + BridgeProductWireContract.capabilityByteLength else {
        throw CocoaError(.fileReadCorruptFile)
    }
    #expect(data[0] == 1)
    let metadataByteCount = data[1..<prefixByteCount].reduce(0) { length, byte in
        (length << 8) | Int(byte)
    }
    let metadataRange = prefixByteCount..<(prefixByteCount + metadataByteCount)
    guard metadataRange.upperBound <= data.count else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let capabilityRange = metadataRange.upperBound..<data.count
    guard capabilityRange.count == BridgeProductWireContract.capabilityByteLength else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return try DecodedDevelopmentDisplayBootstrapEnvelope(
        bootstrap: JSONDecoder().decode(
            BridgeProductSessionBootstrap.self,
            from: data.subdata(in: metadataRange)
        ),
        capabilityBytes: data.subdata(in: capabilityRange)
    )
}

private enum DevelopmentDisplayWorkerClientError: Error {
    case expectedMetadataStreamOpening
    case incompleteReviewMetadataLifecycle
    case invalidRoute
    case metadataStreamEndedBeforeExpectedFrame
    case reviewMetadataTerminatedBeforeFinalWindow
    case unexpectedControlResponse
    case unexpectedFrameAcknowledgementResponse
    case unexpectedMetadataStreamResponse
    case unexpectedReviewItemCount(expected: Int, received: Int)
}
