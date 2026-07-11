import Foundation
import WebKit

enum BridgeProductSchemeAdapterError: Error, Sendable {
    case frameAcknowledgementRejected
    case frameDeliveryRejected
    case invalidRequestURL
    case producerRetirementFailed
}

struct BridgeProductSchemeAdapter: URLSchemeHandler, Sendable {
    let session: BridgeProductSession
    let provider: any BridgeProductSchemeProvider

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        let channel = BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>()
        let producerTask = Task {
            await route(request, channel: channel)
        }
        channel.attachProducerTask(producerTask)
        return channel
    }

    private func route(
        _ request: URLRequest,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async {
        do {
            switch await BridgeProductSchemeRequestAdmission(session: session).admit(request) {
            case .rejected(let rejection):
                guard let url = rejection.url else {
                    throw BridgeProductSchemeAdapterError.invalidRequestURL
                }
                try await sendResponse(
                    statusCode: rejection.statusCode,
                    url: url,
                    contentType: "application/json",
                    contentLength: 0,
                    channel: channel
                )
                await channel.finish()
            case .preflight(_, let url):
                try await sendResponse(
                    statusCode: 204,
                    url: url,
                    contentType: "application/json",
                    contentLength: 0,
                    channel: channel
                )
                await channel.finish()
            case .accepted(let acceptedRequest):
                try await routeAccepted(acceptedRequest, channel: channel)
            }
        } catch is CancellationError {
            await channel.finish()
        } catch {
            await channel.fail(error)
        }
    }

    private func routeAccepted(
        _ request: BridgeProductSchemeAcceptedRequest,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        switch request.route {
        case .command:
            try await routeControl(request, channel: channel)
        case .metadataStream:
            try await routeMetadataStream(request, channel: channel)
        case .content:
            try await routeContent(request, channel: channel)
        }
    }

    private func routeControl(
        _ request: BridgeProductSchemeAcceptedRequest,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
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
                channel: channel
            )
        case .response(let exactResponseBytes):
            try await sendResponse(
                statusCode: 200,
                url: request.url,
                contentType: "application/json",
                contentLength: exactResponseBytes.count,
                channel: channel
            )
            try await channel.send(.data(exactResponseBytes))
        }
        await channel.finish()
    }

    private func routeMetadataStream(
        _ request: BridgeProductSchemeAcceptedRequest,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        guard
            let metadataRequest = try? BridgeProductStrictJSON.decode(
                BridgeProductMetadataStreamRequest.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(url: request.url, channel: channel)
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
            channel: channel
        )
    }

    private func routeContent(
        _ request: BridgeProductSchemeAcceptedRequest,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        guard
            let contentRequest = try? BridgeProductStrictJSON.decode(
                BridgeProductContentRequest.self,
                from: request.exactBodyBytes
            )
        else {
            try await sendRejectedBody(url: request.url, channel: channel)
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
            channel: channel
        )
    }

    private func routeProducerRegistration(
        _ registration: BridgeProductProducerRegistration,
        responseURL: URL,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        switch registration {
        case .rejected:
            try await sendResponse(
                statusCode: 409,
                url: responseURL,
                contentType: "application/json",
                contentLength: 0,
                channel: channel
            )
            await channel.finish()
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
                    channel: channel
                )
                try await pumpFrames(pump, channel: channel)
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
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        while true {
            switch await pump.nextFrame() {
            case .frame(let delivery):
                try await channel.send(.data(delivery.frame.data))
                guard await pump.acknowledgeFrameConsumed(delivery.receipt) else {
                    throw BridgeProductSchemeAdapterError.frameAcknowledgementRejected
                }
            case .finished:
                await channel.finish()
                return
            case .cancelled:
                throw CancellationError()
            case .rejected:
                throw BridgeProductSchemeAdapterError.frameDeliveryRejected
            }
        }
    }

    private func sendRejectedBody(
        url: URL,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        try await sendResponse(
            statusCode: 400,
            url: url,
            contentType: "application/json",
            contentLength: 0,
            channel: channel
        )
        await channel.finish()
    }

    private func sendResponse(
        statusCode: Int,
        url: URL,
        contentType: String,
        contentLength: Int?,
        channel: BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>
    ) async throws {
        try await channel.send(
            .response(
                Self.response(
                    statusCode: statusCode,
                    url: url,
                    contentType: contentType,
                    contentLength: contentLength
                )
            )
        )
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
