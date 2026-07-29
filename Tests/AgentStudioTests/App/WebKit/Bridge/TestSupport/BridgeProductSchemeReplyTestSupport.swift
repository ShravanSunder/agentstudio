import AgentStudioInfrastructure
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
    routingStartGate: BridgeProductSchemeRoutingStartGate? = nil
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
            await routingStartGate.pauseRoutingUntilReleased()
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

final class BridgeProductSchemeRoutingStartGate: @unchecked Sendable {
    private let cancellationContinuation: AsyncStream<Void>.Continuation
    private let cancellationEvents: AsyncStream<Void>
    private let lock = NSLock()
    private let routingPauseContinuation: AsyncStream<Void>.Continuation
    private let routingPauseEvents: AsyncStream<Void>
    private var isRoutingReleased = false
    private var routingRelease: CheckedContinuation<Void, Never>?

    init() {
        let cancellationEvents = AsyncStream<Void>.makeStream()
        self.cancellationEvents = cancellationEvents.stream
        self.cancellationContinuation = cancellationEvents.continuation
        let routingPauseEvents = AsyncStream<Void>.makeStream()
        self.routingPauseEvents = routingPauseEvents.stream
        self.routingPauseContinuation = routingPauseEvents.continuation
    }

    func pauseRoutingUntilReleased() async {
        routingPauseContinuation.yield()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResume = lock.withLock {
                    if isRoutingReleased { return true }
                    routingRelease = continuation
                    return false
                }
                if shouldResume { continuation.resume() }
            }
        } onCancel: {
            cancellationContinuation.yield()
        }
    }

    func waitUntilRoutingPaused() async {
        var iterator = routingPauseEvents.makeAsyncIterator()
        _ = await iterator.next()
    }

    func waitUntilRoutingCancelled() async {
        var iterator = cancellationEvents.makeAsyncIterator()
        _ = await iterator.next()
    }

    func releaseRouting() {
        let release = lock.withLock {
            isRoutingReleased = true
            defer { routingRelease = nil }
            return routingRelease
        }
        release?.resume()
    }
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
