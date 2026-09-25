import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import WebKit

@testable import AgentStudioBridge

struct BridgeProductSchemeReplyObservation: Equatable, Sendable {
    enum Event: Equatable, Sendable {
        case response
        case data
    }

    let body: Data
    let events: [Event]
    let response: HTTPURLResponse?
}

func collectBridgeProductSchemeReply(
    adapter: BridgeProductSchemeAdapter,
    request: URLRequest
) async throws -> BridgeProductSchemeReplyObservation {
    var body = Data()
    var events: [BridgeProductSchemeReplyObservation.Event] = []
    var response: HTTPURLResponse?
    for try await result in bridgeProductSchemeReply(adapter: adapter, request: request) {
        switch result {
        case .response(let emittedResponse):
            events.append(.response)
            response = emittedResponse as? HTTPURLResponse
        case .data(let chunk):
            events.append(.data)
            body.append(chunk)
        @unknown default:
            break
        }
    }
    return .init(body: body, events: events, response: response)
}

func bridgeProductSchemeReply(
    adapter: BridgeProductSchemeAdapter,
    request: URLRequest
) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
    bridgeProductSchemeReplyWithRoutingTask(adapter: adapter, request: request).stream
}

struct BridgeProductSchemeReplyWithRoutingTask {
    let routingTask: Task<Void, Never>
    let stream: AsyncThrowingStream<URLSchemeTaskResult, any Error>
}

func bridgeProductSchemeReplyWithRoutingTask(
    adapter: BridgeProductSchemeAdapter,
    request: URLRequest,
    routingStartGate: HeldStep<Void>? = nil
) -> BridgeProductSchemeReplyWithRoutingTask {
    let (stream, replyContinuation) =
        AsyncThrowingStream<URLSchemeTaskResult, any Error>.makeStream()
    let routingTask = Task {
        guard let productAdmission = adapter.productAdmissionGate.acquire() else {
            replyContinuation.finish(
                throwing: BridgeProductSchemeAdapterTestSupportError.admissionClosed
            )
            return
        }
        if let routingStartGate {
            try? await routingStartGate.arrive(())
        }
        await adapter.route(
            request,
            productAdmission: productAdmission,
            continuation: replyContinuation
        )
    }
    replyContinuation.onTermination = { _ in
        routingTask.cancel()
    }
    return .init(routingTask: routingTask, stream: stream)
}

private enum BridgeProductSchemeAdapterTestSupportError: Error {
    case admissionClosed
}

func bridgeProductSchemeRequest(
    route: String,
    capability: String?,
    method: String = BridgeProductWireContract.requestMethod,
    contentType: String = "application/json",
    body: Data? = nil,
    bodyStream: InputStream? = nil
) -> URLRequest {
    var request = URLRequest(url: URL(string: route)!)
    request.httpMethod = method
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    if let capability {
        request.setValue(capability, forHTTPHeaderField: BridgeProductWireContract.capabilityHeaderName)
    }
    if let body {
        request.httpBody = body
    }
    if let bodyStream {
        request.httpBodyStream = bodyStream
    }
    return request
}
