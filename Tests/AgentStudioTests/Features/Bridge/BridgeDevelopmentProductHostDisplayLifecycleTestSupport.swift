import Foundation
import Testing

@testable import AgentStudioBridge

struct DevelopmentDisplayReviewReplayObservation {
    let identity: BridgeProductReviewMetadataIdentity
    let itemCount: Int
    let windowCount: Int
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
        var identity: BridgeProductReviewMetadataIdentity?
        var itemCount = 0
        var sourceAcceptedCount = 0
        var treeRowCount = 0
        var windowCount = 0

        func completeObservation() throws -> DevelopmentDisplayReviewReplayObservation {
            guard acceptedReviewSubscription, sourceAcceptedCount == 1, let identity else {
                throw DevelopmentDisplayWorkerClientError.incompleteReviewMetadataLifecycle
            }
            guard itemCount == expectedItemCount else {
                throw DevelopmentDisplayWorkerClientError.unexpectedReviewItemCount(
                    expected: expectedItemCount,
                    received: itemCount
                )
            }
            return DevelopmentDisplayReviewReplayObservation(
                identity: identity,
                itemCount: itemCount,
                windowCount: windowCount
            )
        }

        while true {
            let frame = try await nextFrame()
            try await worker.acknowledge(frame.producerFrameIdentity)
            switch frame {
            case .subscriptionAccepted(let accepted):
                if accepted.subscriptionIdentity.subscriptionKind == .reviewMetadata {
                    acceptedReviewSubscription = true
                }
            case .subscriptionData(let data):
                guard let event = data.data.reviewMetadataEvent else { continue }
                switch event {
                case .sourceAccepted(let sourceAccepted):
                    sourceAcceptedCount += 1
                    identity = sourceAccepted.identity
                case .snapshot(let snapshot):
                    try requireMatchingReviewReplayIdentity(identity, snapshot.identity)
                    #expect(snapshot.itemWindow.startIndex == itemCount)
                    #expect(snapshot.treeWindow.startIndex == treeRowCount)
                    itemCount += snapshot.itemMetadata.count
                    treeRowCount += snapshot.treeRows.count
                    windowCount += 1
                    if snapshot.itemWindow.finalWindow && snapshot.treeWindow.finalWindow {
                        return try completeObservation()
                    }
                case .window(let window):
                    try requireMatchingReviewReplayIdentity(identity, window.identity)
                    #expect(window.itemWindow.startIndex == itemCount)
                    #expect(window.treeWindow.startIndex == treeRowCount)
                    itemCount += window.itemMetadata.count
                    treeRowCount += window.treeRows.count
                    windowCount += 1
                    if window.itemWindow.finalWindow && window.treeWindow.finalWindow {
                        return try completeObservation()
                    }
                case .delta, .invalidated, .reset:
                    throw DevelopmentDisplayWorkerClientError.unexpectedReviewMetadataEvent
                }
            case .metadataStreamError, .subscriptionReset, .subscriptionEnd:
                throw DevelopmentDisplayWorkerClientError.reviewMetadataTerminatedBeforeFinalWindow
            case .contentCancelled, .metadataStreamAccepted, .panePresentation,
                .paneSurfaceSelectionRequested, .subscriptionCancelled,
                .subscriptionInterestsCommitted:
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
        let response = try await collectRouteResponse(
            try routedRequest(route: BridgeProductWireContract.commandRoute, body: body)
        )
        #expect(response.statusCode == 200)
        return try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: response.body
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
    surface: String = "review"
) throws -> BridgeDevelopmentProductBootstrapRequest {
    var request: [String: Any] = [
        "navigationIntent": [
            "commandId": "open-\(surface)-view",
            "commandKind": "activateContext",
            "surface": surface,
        ],
        "reason": reason,
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

private func requireMatchingReviewReplayIdentity(
    _ expected: BridgeProductReviewMetadataIdentity?,
    _ received: BridgeProductReviewMetadataIdentity
) throws {
    guard expected == received else {
        throw DevelopmentDisplayWorkerClientError.reviewPublicationIdentityChanged
    }
}

private enum DevelopmentDisplayWorkerClientError: Error {
    case expectedMetadataStreamOpening
    case incompleteReviewMetadataLifecycle
    case invalidRoute
    case metadataStreamEndedBeforeExpectedFrame
    case reviewMetadataTerminatedBeforeFinalWindow
    case reviewPublicationIdentityChanged
    case unexpectedControlResponse
    case unexpectedFrameAcknowledgementResponse
    case unexpectedMetadataStreamResponse
    case unexpectedReviewItemCount(expected: Int, received: Int)
    case unexpectedReviewMetadataEvent
}
