import Foundation
import WebKit
import os.log

private let bridgeProductSchemeAdapterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeProductSchemeAdapter"
)

enum BridgeProductSchemeAdapterError: Error, Sendable {
    case frameAcknowledgementRejected
    case frameDeliveryRejected
    case invalidRequestURL
    case producerRetirementFailed
    case responseDeliveryRejected
}

typealias BridgeProductSchemeReplyContinuation =
    AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation

struct BridgeProductSchemeAdapter: Sendable {
    let session: BridgeProductSession
    let provider: any BridgeProductSchemeProvider
    let productAdmissionGate: BridgeProductAdmissionGate
    let telemetryRecorder: (any BridgePerformanceTraceRecording)?

    init(
        session: BridgeProductSession,
        provider: any BridgeProductSchemeProvider,
        productAdmissionGate: BridgeProductAdmissionGate,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil
    ) {
        self.session = session
        self.provider = provider
        self.productAdmissionGate = productAdmissionGate
        self.telemetryRecorder = telemetryRecorder
    }

    func route(
        _ request: URLRequest,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async {
        guard productAdmission.wasMinted(by: productAdmissionGate) else {
            continuation.finish(throwing: CancellationError())
            return
        }
        do {
            switch await BridgeProductSchemeRequestAdmission(
                session: session,
                productAdmission: productAdmission
            ).admit(request) {
            case .rejected(let rejection):
                let route =
                    rejection.url.flatMap(BridgeProductSchemeRoute.classify)?.diagnosticName
                    ?? "unclassified"
                bridgeProductSchemeAdapterLogger.error(
                    "Product request admission rejected route=\(route, privacy: .public) status=\(rejection.statusCode) body_source=\(rejection.bodySource.rawValue, privacy: .public)"
                )
                guard let url = rejection.url else {
                    throw BridgeProductSchemeAdapterError.invalidRequestURL
                }
                try await sendResponse(
                    statusCode: rejection.statusCode,
                    url: url,
                    contentType: "application/json",
                    contentLength: 0,
                    productAdmission: productAdmission,
                    continuation: continuation
                )
                continuation.finish()
            case .preflight(_, let url):
                try await sendResponse(
                    statusCode: 204,
                    url: url,
                    contentType: "application/json",
                    contentLength: 0,
                    productAdmission: productAdmission,
                    continuation: continuation
                )
                continuation.finish()
            case .accepted(let acceptedRequest):
                try await routeAccepted(
                    acceptedRequest,
                    productAdmission: productAdmission,
                    continuation: continuation
                )
            }
        } catch is CancellationError {
            bridgeProductSchemeAdapterLogger.debug("Product request routing cancelled")
            continuation.finish(throwing: CancellationError())
        } catch {
            let failureReason = BridgeProductSchemeContainedFailureReason(error: error)
            bridgeProductSchemeAdapterLogger.error(
                "Product request routing failed reason=\(failureReason.rawValue, privacy: .public)"
            )
            await recordContainedFailure(reason: failureReason)
            continuation.finish()
        }
    }

    private func recordContainedFailure(
        reason: BridgeProductSchemeContainedFailureReason
    ) async {
        guard let telemetryRecorder else { return }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .webKit,
                name: "performance.bridge.webkit.product_scheme_failure_contained",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "error",
                    "agentstudio.bridge.plane": "observability",
                    "agentstudio.bridge.priority": "hot",
                    "agentstudio.bridge.result": "failure",
                    "agentstudio.bridge.result_reason": reason.rawValue,
                    "agentstudio.bridge.slice": "connection_health",
                    "agentstudio.bridge.transport": "scheme",
                ],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func routeAccepted(
        _ request: BridgeProductSchemeAcceptedRequest,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        switch request.route {
        case .command:
            try await routeControl(
                request,
                productAdmission: productAdmission,
                continuation: continuation
            )
        case .metadataStream:
            try await routeMetadataStream(
                request,
                productAdmission: productAdmission,
                continuation: continuation
            )
        case .content:
            try await routeContent(
                request,
                productAdmission: productAdmission,
                continuation: continuation
            )
        }
    }

    private func routeControl(
        _ request: BridgeProductSchemeAcceptedRequest,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            let commandPackage = try? BridgeProductStrictJSON.decode(
                BridgeProductCommandPackage.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(
                url: request.url,
                productAdmission: productAdmission,
                continuation: continuation
            )
            return
        }
        switch commandPackage {
        case .contentFrameAcknowledgement(let acknowledgement):
            try await routeContentFrameAcknowledgement(
                acknowledgement,
                responseURL: request.url,
                productAdmission: productAdmission,
                continuation: continuation
            )
            return
        case .metadataFrameAcknowledgement(let acknowledgement):
            try await routeMetadataFrameAcknowledgement(
                acknowledgement,
                responseURL: request.url,
                productAdmission: productAdmission,
                continuation: continuation
            )
            return
        case .control:
            break
        }
        let result = try await BridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider,
            productAdmission: productAdmission
        ).dispatch(
            exactRequestBytes: request.exactBodyBytes,
            presentedCapability: request.presentedCapability
        )
        switch result {
        case .admissionClosed:
            try await sendResponse(
                statusCode: 409,
                url: request.url,
                contentType: "application/json",
                contentLength: 0,
                productAdmission: productAdmission,
                continuation: continuation
            )
        case .rejected(let rejection):
            try await sendResponse(
                statusCode: Self.statusCode(for: rejection),
                url: request.url,
                contentType: "application/json",
                contentLength: 0,
                productAdmission: productAdmission,
                continuation: continuation
            )
        case .response(let exactResponseBytes):
            try await sendResponse(
                statusCode: 200,
                url: request.url,
                contentType: "application/json",
                contentLength: exactResponseBytes.count,
                productAdmission: productAdmission,
                continuation: continuation
            )
            try emit(
                .data(exactResponseBytes),
                productAdmission: productAdmission,
                continuation: continuation
            )
        }
        continuation.finish()
    }

    private func routeContentFrameAcknowledgement(
        _ acknowledgement: BridgeProductContentFrameAcknowledgement,
        responseURL: URL,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            await session.acknowledgeContentFrameObservation(
                acknowledgement,
                productAdmission: productAdmission
            )
        else {
            try await sendResponse(
                statusCode: 409,
                url: responseURL,
                contentType: "application/json",
                contentLength: 0,
                productAdmission: productAdmission,
                continuation: continuation
            )
            continuation.finish()
            return
        }
        try await sendResponse(
            statusCode: 204,
            url: responseURL,
            contentType: "application/json",
            contentLength: 0,
            productAdmission: productAdmission,
            continuation: continuation
        )
        continuation.finish()
    }

    private func routeMetadataFrameAcknowledgement(
        _ acknowledgement: BridgeProductMetadataFrameAcknowledgement,
        responseURL: URL,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            await session.acknowledgeMetadataFrameObservation(
                acknowledgement,
                productAdmission: productAdmission
            )
        else {
            try await sendResponse(
                statusCode: 409,
                url: responseURL,
                contentType: "application/json",
                contentLength: 0,
                productAdmission: productAdmission,
                continuation: continuation
            )
            continuation.finish()
            return
        }
        try await sendResponse(
            statusCode: 204,
            url: responseURL,
            contentType: "application/json",
            contentLength: 0,
            productAdmission: productAdmission,
            continuation: continuation
        )
        continuation.finish()
    }

    private func routeMetadataStream(
        _ request: BridgeProductSchemeAcceptedRequest,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            let metadataRequest = try? BridgeProductStrictJSON.decode(
                BridgeProductMetadataStreamRequest.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(
                url: request.url,
                productAdmission: productAdmission,
                continuation: continuation
            )
            return
        }
        let registration = await session.registerMetadataProducer(
            request: metadataRequest,
            productAdmission: productAdmission
        ) { lease in
            await provider.runMetadataProducer(
                request: metadataRequest,
                lease: lease,
                productAdmission: productAdmission,
                session: session
            )
        }
        try await routeProducerRegistration(
            registration,
            responseURL: request.url,
            productAdmission: productAdmission,
            continuation: continuation
        )
    }

    private func routeContent(
        _ request: BridgeProductSchemeAcceptedRequest,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            let contentRequest = try? BridgeProductStrictJSON.decode(
                BridgeProductContentRequest.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(
                url: request.url,
                productAdmission: productAdmission,
                continuation: continuation
            )
            return
        }
        let operation = provider.makeContentProducerOperation(
            request: contentRequest,
            productAdmission: productAdmission,
            session: session
        )
        let registration = await session.registerContentProducer(
            request: contentRequest,
            productAdmission: productAdmission,
            operation: operation
        )
        try await routeProducerRegistration(
            registration,
            responseURL: request.url,
            productAdmission: productAdmission,
            continuation: continuation
        )
    }

    private func routeProducerRegistration(
        _ registration: BridgeProductProducerRegistration,
        responseURL: URL,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        switch registration {
        case .rejected(let rejection):
            bridgeProductSchemeAdapterLogger.error(
                "Product producer registration rejected reason=\(String(describing: rejection), privacy: .public)"
            )
            try await sendResponse(
                statusCode: 409,
                url: responseURL,
                contentType: "application/json",
                contentLength: 0,
                productAdmission: productAdmission,
                continuation: continuation
            )
            continuation.finish()
        case .accepted(let producerLease):
            let pump = BridgeProductSchemeFramePump(
                session: session,
                producerLease: producerLease,
                productAdmission: productAdmission,
                acknowledgeLifecycle: { acknowledgement in
                    await provider.acknowledgeLifecycle(acknowledgement)
                }
            )
            do {
                try await sendResponse(
                    statusCode: 200,
                    url: responseURL,
                    contentType: "application/octet-stream",
                    contentLength: nil,
                    productAdmission: productAdmission,
                    continuation: continuation
                )
                try await pumpFrames(
                    pump,
                    productAdmission: productAdmission,
                    continuation: continuation
                )
            } catch {
                guard await pump.cancel() else {
                    throw BridgeProductSchemeAdapterError.producerRetirementFailed
                }
                throw error
            }
        }
    }

    private func pumpFrames(
        _ pump: BridgeProductSchemeFramePump,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        while true {
            switch await pump.nextFrame() {
            case .frame(let delivery):
                try emit(
                    .data(delivery.frame.data),
                    productAdmission: productAdmission,
                    continuation: continuation
                )
                let frameAccepted =
                    if pump.frameRequiresWorkerObservation(delivery.receipt) {
                        await pump.waitUntilFrameObserved(delivery.receipt)
                    } else {
                        await pump.acknowledgeFrameConsumed(delivery.receipt)
                    }
                guard frameAccepted else {
                    throw BridgeProductSchemeAdapterError.frameAcknowledgementRejected
                }
            case .finished:
                bridgeProductSchemeAdapterLogger.debug("Product producer pump reached terminal frame")
                continuation.finish()
                return
            case .cancelled:
                bridgeProductSchemeAdapterLogger.debug("Product producer pump cancelled")
                throw CancellationError()
            case .rejected(let rejection):
                bridgeProductSchemeAdapterLogger.error(
                    "Product producer pump rejected frame reason=\(String(describing: rejection), privacy: .public)"
                )
                throw BridgeProductSchemeAdapterError.frameDeliveryRejected
            }
        }
    }

    private func sendRejectedBody(
        url: URL,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        try await sendResponse(
            statusCode: 400,
            url: url,
            contentType: "application/json",
            contentLength: 0,
            productAdmission: productAdmission,
            continuation: continuation
        )
        continuation.finish()
    }

    private func sendResponse(
        statusCode: Int,
        url: URL,
        contentType: String,
        contentLength: Int?,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        try emit(
            .response(
                Self.response(
                    statusCode: statusCode,
                    url: url,
                    contentType: contentType,
                    contentLength: contentLength
                )
            ),
            productAdmission: productAdmission,
            continuation: continuation
        )
    }

    private func emit(
        _ result: URLSchemeTaskResult,
        productAdmission: BridgeProductAdmissionContext,
        continuation: BridgeProductSchemeReplyContinuation
    ) throws {
        guard
            let yieldResult = productAdmission.withValidAdmission({
                continuation.yield(result)
            })
        else {
            throw CancellationError()
        }
        switch yieldResult {
        case .enqueued:
            return
        case .dropped:
            throw BridgeProductSchemeAdapterError.responseDeliveryRejected
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw BridgeProductSchemeAdapterError.responseDeliveryRejected
        }
    }

    private static func response(
        statusCode: Int,
        url: URL,
        contentType: String,
        contentLength: Int?
    ) -> URLResponse {
        var headers = [
            "Access-Control-Allow-Headers":
                "Content-Type, \(BridgeProductWireContract.capabilityHeaderName)",
            "Access-Control-Allow-Methods": "OPTIONS, POST",
            "Access-Control-Allow-Origin": "*",
            "Content-Type": contentType,
        ]
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )
            ?? URLResponse(
                url: url,
                mimeType: contentType,
                expectedContentLength: contentLength ?? -1,
                textEncodingName: contentType == "application/json" ? "utf-8" : nil
            )
    }

    private static func statusCode(
        for rejection: BridgeProductSessionControlRejection
    ) -> Int {
        switch rejection {
        case .invalidRequest: 400
        case .payloadTooLarge: 413
        case .unauthorized: 403
        case .inactiveSession, .requestInFlight, .revoked, .sequenceConflict,
            .sequenceExhausted, .staleDerivationEpoch, .staleWorker,
            .streamSequenceConflict:
            409
        }
    }
}

private enum BridgeProductSchemeContainedFailureReason: String {
    case frameAcknowledgementRejected = "frame_acknowledgement_rejected"
    case frameDeliveryRejected = "frame_delivery_rejected"
    case invalidRequestURL = "invalid_request_url"
    case producerRetirementFailed = "producer_retirement_failed"
    case responseDeliveryRejected = "response_delivery_rejected"
    case unexpected

    init(error: any Error) {
        switch error as? BridgeProductSchemeAdapterError {
        case .frameAcknowledgementRejected:
            self = .frameAcknowledgementRejected
        case .frameDeliveryRejected:
            self = .frameDeliveryRejected
        case .invalidRequestURL:
            self = .invalidRequestURL
        case .producerRetirementFailed:
            self = .producerRetirementFailed
        case .responseDeliveryRejected:
            self = .responseDeliveryRejected
        case nil:
            self = .unexpected
        }
    }
}
