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

    func route(
        _ request: URLRequest,
        continuation: BridgeProductSchemeReplyContinuation
    ) async {
        do {
            switch await BridgeProductSchemeRequestAdmission(session: session).admit(request) {
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
                    continuation: continuation
                )
                continuation.finish()
            case .preflight(_, let url):
                try await sendResponse(
                    statusCode: 204,
                    url: url,
                    contentType: "application/json",
                    contentLength: 0,
                    continuation: continuation
                )
                continuation.finish()
            case .accepted(let acceptedRequest):
                try await routeAccepted(acceptedRequest, continuation: continuation)
            }
        } catch is CancellationError {
            bridgeProductSchemeAdapterLogger.debug("Product request routing cancelled")
            continuation.finish()
        } catch {
            bridgeProductSchemeAdapterLogger.error(
                "Product request routing failed error=\(String(describing: error), privacy: .public)"
            )
            continuation.finish(throwing: error)
        }
    }

    private func routeAccepted(
        _ request: BridgeProductSchemeAcceptedRequest,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        switch request.route {
        case .command:
            try await routeControl(request, continuation: continuation)
        case .metadataStream:
            try await routeMetadataStream(request, continuation: continuation)
        case .content:
            try await routeContent(request, continuation: continuation)
        }
    }

    private func routeControl(
        _ request: BridgeProductSchemeAcceptedRequest,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            let commandPackage = try? BridgeProductStrictJSON.decode(
                BridgeProductCommandPackage.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(url: request.url, continuation: continuation)
            return
        }
        switch commandPackage {
        case .contentFrameAcknowledgement(let acknowledgement):
            try await routeContentFrameAcknowledgement(
                acknowledgement,
                responseURL: request.url,
                continuation: continuation
            )
            return
        case .metadataFrameAcknowledgement(let acknowledgement):
            try await routeMetadataFrameAcknowledgement(
                acknowledgement,
                responseURL: request.url,
                continuation: continuation
            )
            return
        case .control:
            break
        }
        let result = try await BridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider
        ).dispatch(
            exactRequestBytes: request.exactBodyBytes,
            presentedCapability: request.presentedCapability
        )
        switch result {
        case .rejected(let rejection):
            try await sendResponse(
                statusCode: Self.statusCode(for: rejection),
                url: request.url,
                contentType: "application/json",
                contentLength: 0,
                continuation: continuation
            )
        case .response(let exactResponseBytes):
            try await sendResponse(
                statusCode: 200,
                url: request.url,
                contentType: "application/json",
                contentLength: exactResponseBytes.count,
                continuation: continuation
            )
            try emit(.data(exactResponseBytes), continuation: continuation)
        }
        continuation.finish()
    }

    private func routeContentFrameAcknowledgement(
        _ acknowledgement: BridgeProductContentFrameAcknowledgement,
        responseURL: URL,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard await session.acknowledgeContentFrameObservation(acknowledgement) else {
            try await sendResponse(
                statusCode: 409,
                url: responseURL,
                contentType: "application/json",
                contentLength: 0,
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
            continuation: continuation
        )
        continuation.finish()
    }

    private func routeMetadataFrameAcknowledgement(
        _ acknowledgement: BridgeProductMetadataFrameAcknowledgement,
        responseURL: URL,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard await session.acknowledgeMetadataFrameObservation(acknowledgement) else {
            try await sendResponse(
                statusCode: 409,
                url: responseURL,
                contentType: "application/json",
                contentLength: 0,
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
            continuation: continuation
        )
        continuation.finish()
    }

    private func routeMetadataStream(
        _ request: BridgeProductSchemeAcceptedRequest,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            let metadataRequest = try? BridgeProductStrictJSON.decode(
                BridgeProductMetadataStreamRequest.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(url: request.url, continuation: continuation)
            return
        }
        let registration = await session.registerMetadataProducer(
            request: metadataRequest
        ) { lease in
            await provider.runMetadataProducer(
                request: metadataRequest,
                lease: lease,
                session: session
            )
        }
        try await routeProducerRegistration(
            registration,
            responseURL: request.url,
            continuation: continuation
        )
    }

    private func routeContent(
        _ request: BridgeProductSchemeAcceptedRequest,
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        guard
            let contentRequest = try? BridgeProductStrictJSON.decode(
                BridgeProductContentRequest.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(url: request.url, continuation: continuation)
            return
        }
        let registration = await session.registerContentProducer(
            request: contentRequest
        ) { lease in
            await provider.runContentProducer(
                request: contentRequest,
                lease: lease,
                session: session
            )
        }
        try await routeProducerRegistration(
            registration,
            responseURL: request.url,
            continuation: continuation
        )
    }

    private func routeProducerRegistration(
        _ registration: BridgeProductProducerRegistration,
        responseURL: URL,
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
                continuation: continuation
            )
            continuation.finish()
        case .accepted(let producerLease):
            let pump = BridgeProductSchemeFramePump(
                session: session,
                producerLease: producerLease,
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
                    continuation: continuation
                )
                try await pumpFrames(pump, continuation: continuation)
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
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        while true {
            switch await pump.nextFrame() {
            case .frame(let delivery):
                try emit(.data(delivery.frame.data), continuation: continuation)
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
        continuation: BridgeProductSchemeReplyContinuation
    ) async throws {
        try await sendResponse(
            statusCode: 400,
            url: url,
            contentType: "application/json",
            contentLength: 0,
            continuation: continuation
        )
        continuation.finish()
    }

    private func sendResponse(
        statusCode: Int,
        url: URL,
        contentType: String,
        contentLength: Int?,
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
            continuation: continuation
        )
    }

    private func emit(
        _ result: URLSchemeTaskResult,
        continuation: BridgeProductSchemeReplyContinuation
    ) throws {
        switch continuation.yield(result) {
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
