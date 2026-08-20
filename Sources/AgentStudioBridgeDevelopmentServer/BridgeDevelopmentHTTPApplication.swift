import AgentStudioBridge
import Foundation
import HTTPTypes
import Hummingbird
import WebKit

enum BridgeDevelopmentHTTPApplication {
    private static let bootstrapBodyLimit = 8 * 1024
    private static let productBodyLimit = 128 * 1024

    static func make(
        host: BridgeDevelopmentProductHost,
        configuration: ApplicationConfiguration = .init(),
        healthIsReady: @escaping @Sendable () async -> Bool = { true }
    ) -> some ApplicationProtocol {
        let router = Router()
        router.get("/__bridge-product/health") { _, _ -> Response in
            Response(status: await healthIsReady() ? .noContent : .serviceUnavailable)
        }
        router.post("/__bridge-product/bootstrap") { request, _ -> Response in
            try await bootstrapResponse(request: request, host: host)
        }
        registerProductRoute(
            "/__bridge-product/command",
            destination: "agentstudio://rpc/command",
            router: router,
            host: host
        )
        registerProductRoute(
            "/__bridge-product/stream",
            destination: "agentstudio://rpc/stream",
            router: router,
            host: host
        )
        registerProductRoute(
            "/__bridge-product/content",
            destination: "agentstudio://rpc/content",
            router: router,
            host: host
        )
        return Application(
            responder: router.buildResponder(),
            configuration: configuration
        )
    }

    private static func registerProductRoute(
        _ path: RouterPath,
        destination: String,
        router: Router<BasicRequestContext>,
        host: BridgeDevelopmentProductHost
    ) {
        router.post(path) { request, _ -> Response in
            let body = try await request.body.collect(upTo: productBodyLimit)
            guard let destinationURL = URL(string: destination) else {
                throw HTTPError(.internalServerError)
            }
            let forwardedRequest = forwardedProductRequest(
                destinationURL: destinationURL,
                body: Data(body.readableBytesView),
                headers: request.headers
            )
            return try await BridgeDevelopmentHTTPProductResponse.make(
                from: await host.route(forwardedRequest)
            )
        }
    }

    static func forwardedProductRequest(
        destinationURL: URL,
        body: Data,
        headers: HTTPFields
    ) -> URLRequest {
        var request = URLRequest(url: destinationURL)
        request.httpMethod = "POST"
        request.httpBody = body
        if let contentType = headers[.contentType] {
            request.setValue(contentType, forHTTPHeaderField: HTTPField.Name.contentType.rawName)
        }
        if let capabilityName = HTTPField.Name(BridgeProductWireContract.capabilityHeaderName),
            let capability = headers[capabilityName]
        {
            request.setValue(capability, forHTTPHeaderField: capabilityName.rawName)
        }
        return request
    }

    private static func bootstrapResponse(
        request: Request,
        host: BridgeDevelopmentProductHost
    ) async throws -> Response {
        guard request.headers[.contentType]?.lowercased() == "application/json" else {
            throw HTTPError(.unsupportedMediaType)
        }
        let body = try await request.body.collect(upTo: bootstrapBodyLimit)
        let bootstrapRequest: BridgeDevelopmentProductBootstrapRequest
        do {
            bootstrapRequest = try JSONDecoder().decode(
                BridgeDevelopmentProductBootstrapRequest.self,
                from: Data(body.readableBytesView)
            )
        } catch {
            throw HTTPError(.badRequest)
        }
        let delivery = try await host.issueBootstrap(for: bootstrapRequest)
        return Response(
            status: .ok,
            headers: [.contentType: "application/octet-stream"],
            body: .init(byteBuffer: ByteBuffer(bytes: delivery))
        )
    }
}

enum BridgeDevelopmentHTTPProductResponse {
    static func make(
        from results: AsyncThrowingStream<URLSchemeTaskResult, any Error>
    ) async throws -> Response {
        let (responseHeads, responseHeadContinuation) =
            AsyncThrowingStream<HTTPURLResponse, any Error>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
        let (responseBody, responseBodyContinuation) =
            AsyncThrowingStream<ByteBuffer, any Error>.makeStream(
                bufferingPolicy: .unbounded
            )
        let routeTask = Task {
            do {
                var receivedResponseHead = false
                for try await result in results {
                    try Task.checkCancellation()
                    switch result {
                    case .response(let response):
                        guard !receivedResponseHead,
                            let httpResponse = response as? HTTPURLResponse
                        else {
                            throw BridgeDevelopmentHTTPResponseError.invalidResponseSequence
                        }
                        receivedResponseHead = true
                        guard case .enqueued = responseHeadContinuation.yield(httpResponse) else {
                            throw BridgeDevelopmentHTTPResponseError.invalidResponseSequence
                        }
                        responseHeadContinuation.finish()
                    case .data(let data):
                        guard receivedResponseHead else {
                            throw BridgeDevelopmentHTTPResponseError.invalidResponseSequence
                        }
                        guard
                            case .enqueued = responseBodyContinuation.yield(ByteBuffer(bytes: data))
                        else {
                            throw BridgeDevelopmentHTTPResponseError.invalidResponseSequence
                        }
                    @unknown default:
                        throw BridgeDevelopmentHTTPResponseError.invalidResponseSequence
                    }
                }
                guard receivedResponseHead else {
                    throw BridgeDevelopmentHTTPResponseError.missingResponseHead
                }
                responseBodyContinuation.finish()
            } catch {
                responseHeadContinuation.finish(throwing: error)
                responseBodyContinuation.finish(throwing: error)
            }
        }
        responseBodyContinuation.onTermination = { _ in routeTask.cancel() }

        var responseHeadIterator = responseHeads.makeAsyncIterator()
        guard let responseHead = try await responseHeadIterator.next() else {
            routeTask.cancel()
            throw BridgeDevelopmentHTTPResponseError.missingResponseHead
        }
        return Response(
            status: .init(code: responseHead.statusCode),
            headers: forwardedHeaders(responseHead),
            body: .init(asyncSequence: responseBody)
        )
    }

    private static func forwardedHeaders(_ response: HTTPURLResponse) -> HTTPFields {
        var fields = HTTPFields()
        let forwardedNames: [HTTPField.Name] = [
            .contentType,
            .accessControlAllowCredentials,
            .accessControlAllowHeaders,
            .accessControlAllowMethods,
            .accessControlAllowOrigin,
        ]
        for name in forwardedNames {
            if let value = response.value(forHTTPHeaderField: name.rawName) {
                fields[name] = value
            }
        }
        return fields
    }
}

private enum BridgeDevelopmentHTTPResponseError: Error {
    case invalidResponseSequence
    case missingResponseHead
}
