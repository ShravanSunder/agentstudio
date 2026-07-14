import Foundation
import WebKit

@testable import AgentStudio

struct BridgeProductSchemeAdapterHarness {
    let adapter: BridgeProductSchemeAdapter
    let capabilityHeader: String
    let provider: BridgeProductSchemeProviderSpy
    let session: BridgeProductSession

    static func make(
        holdFirstControlResponse: Bool = false,
        contentReturnsWithoutTerminal: Bool = false,
        metadataProgressFrameCount: Int = 0
    ) throws -> Self {
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = BridgeProductSchemeProviderSpy(
            holdFirstControlResponse: holdFirstControlResponse,
            contentReturnsWithoutTerminal: contentReturnsWithoutTerminal,
            metadataProgressFrameCount: metadataProgressFrameCount
        )
        return Self(
            adapter: BridgeProductSchemeAdapter(session: session, provider: provider),
            capabilityHeader: capabilityHeader,
            provider: provider,
            session: session
        )
    }

    func openSession(
        body: Data = bridgeProductSchemeWorkerOpenBody(),
        contentType: String = "application/json"
    ) async throws -> BridgeProductSchemeReplyObservation {
        try await collectBridgeProductSchemeReply(
            adapter: adapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: capabilityHeader,
                contentType: contentType,
                body: body
            )
        )
    }
}

actor BridgeProductSchemeProviderSpy: BridgeProductSchemeProvider {
    struct Snapshot: Equatable, Sendable {
        let acknowledgedLifecycleCount: Int
        let contentRequestCount: Int
        let controlCompletionCount: Int
        let controlRequests: [BridgeProductControlRequest]
        let metadataRequestCount: Int
        let producerFailureCount: Int
    }

    private let contentOperationGate = BridgeProductSessionProducerOperationGate()
    private let contentReturnsWithoutTerminal: Bool
    private var controlCompletionCount = 0
    private var controlCompletionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var controlRequests: [BridgeProductControlRequest] = []
    private var controlStartWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private let holdFirstControlResponse: Bool
    private var heldControlContinuation: CheckedContinuation<Void, Never>?
    private let metadataOperationGate = BridgeProductSessionProducerOperationGate()
    private let metadataProgressFrameCount: Int
    private var acknowledgedLifecycleCount = 0
    private var acknowledgedLifecycleWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var contentRequestCount = 0
    private var metadataRequestCount = 0
    private var producerFailures: [String] = []

    init(
        holdFirstControlResponse: Bool,
        contentReturnsWithoutTerminal: Bool,
        metadataProgressFrameCount: Int = 0
    ) {
        self.holdFirstControlResponse = holdFirstControlResponse
        self.contentReturnsWithoutTerminal = contentReturnsWithoutTerminal
        self.metadataProgressFrameCount = metadataProgressFrameCount
    }

    func response(
        for controlRequest: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse {
        controlRequests.append(controlRequest)
        resumeControlStartWaiters()
        if holdFirstControlResponse, controlRequests.count == 1 {
            await withCheckedContinuation { continuation in
                heldControlContinuation = continuation
            }
        }
        let response = makeResponse(for: controlRequest)
        controlCompletionCount += 1
        resumeControlCompletionWaiters()
        return response
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        metadataRequestCount += 1
        do {
            let result = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                build: { sequence in
                    try bridgeProductMetadataAcceptedFrame(
                        request: request,
                        streamSequence: sequence,
                        resumeDisposition: .snapshotRequired
                    )
                }
            )
            guard bridgeProductSchemeFrameWasAdmitted(result) else {
                producerFailures.append("metadata opening frame rejected")
                return
            }
            for progressIndex in 0..<metadataProgressFrameCount {
                let progressResult = try await session.enqueueProducerFrame(
                    for: lease,
                    build: { sequence in
                        try bridgeProductMetadataProgressFrame(
                            request: request,
                            streamSequence: sequence,
                            identitySuffix: "adapter-\(progressIndex)"
                        )
                    },
                    overflowReset: { sequence in
                        try bridgeProductMetadataTerminalFrame(
                            request: request,
                            streamSequence: sequence
                        )
                    }
                )
                guard bridgeProductSchemeFrameWasAdmitted(progressResult) else {
                    producerFailures.append("metadata progress frame rejected")
                    return
                }
            }
            await metadataOperationGate.run(lease)
        } catch {
            producerFailures.append("metadata opening frame threw")
        }
    }

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        contentRequestCount += 1
        do {
            let result = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                build: { _ in producerRegistryContentOpeningFrame(for: request) }
            )
            guard bridgeProductSchemeFrameWasAdmitted(result) else {
                producerFailures.append("content opening frame rejected")
                return
            }
            if contentReturnsWithoutTerminal { return }
            await contentOperationGate.run(lease)
        } catch {
            producerFailures.append("content opening frame threw")
        }
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        _ = acknowledgement
        acknowledgedLifecycleCount += 1
        let ready = acknowledgedLifecycleWaiters.filter {
            $0.0 <= acknowledgedLifecycleCount
        }
        acknowledgedLifecycleWaiters.removeAll {
            $0.0 <= acknowledgedLifecycleCount
        }
        for (_, continuation) in ready { continuation.resume() }
        return true
    }

    func waitUntilAcknowledgedLifecycleCount(_ count: Int) async {
        guard acknowledgedLifecycleCount < count else { return }
        await withCheckedContinuation { continuation in
            acknowledgedLifecycleWaiters.append((count, continuation))
        }
    }

    func waitUntilControlStarted(_ count: Int) async {
        guard controlRequests.count < count else { return }
        await withCheckedContinuation { continuation in
            controlStartWaiters.append((count, continuation))
        }
    }

    func waitUntilControlCompleted(_ count: Int) async {
        guard controlCompletionCount < count else { return }
        await withCheckedContinuation { continuation in
            controlCompletionWaiters.append((count, continuation))
        }
    }

    func releaseHeldControlResponse() {
        heldControlContinuation?.resume()
        heldControlContinuation = nil
    }

    var snapshot: Snapshot {
        .init(
            acknowledgedLifecycleCount: acknowledgedLifecycleCount,
            contentRequestCount: contentRequestCount,
            controlCompletionCount: controlCompletionCount,
            controlRequests: controlRequests,
            metadataRequestCount: metadataRequestCount,
            producerFailureCount: producerFailures.count
        )
    }

    private func makeResponse(
        for request: BridgeProductControlRequest
    ) -> BridgeProductControlResponse {
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .productCall:
                return try .callCompleted(
                    correlating: request,
                    result: .reviewMarkFileViewed
                )
            case .subscriptionOpen, .subscriptionUpdateBatch, .subscriptionCancel,
                .workerSessionResync:
                preconditionFailure("The adapter test provider received an unconfigured control request")
            }
        } catch {
            preconditionFailure("The adapter test provider could not build a correlated response")
        }
    }

    private func resumeControlStartWaiters() {
        let ready = controlStartWaiters.filter { $0.0 <= controlRequests.count }
        controlStartWaiters.removeAll { $0.0 <= controlRequests.count }
        for (_, continuation) in ready { continuation.resume() }
    }

    private func resumeControlCompletionWaiters() {
        let ready = controlCompletionWaiters.filter { $0.0 <= controlCompletionCount }
        controlCompletionWaiters.removeAll { $0.0 <= controlCompletionCount }
        for (_, continuation) in ready { continuation.resume() }
    }
}

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
    request: URLRequest
) -> BridgeProductSchemeReplyWithRoutingTask {
    var replyContinuation: BridgeProductSchemeReplyContinuation?
    let stream = AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
        replyContinuation = continuation
    }
    let routingTask = Task {
        guard let replyContinuation else { return }
        await adapter.route(request, continuation: replyContinuation)
    }
    replyContinuation?.onTermination = { _ in
        routingTask.cancel()
    }
    return .init(routingTask: routingTask, stream: stream)
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

func bridgeProductSchemeWorkerOpenBody() -> Data {
    try! JSONSerialization.data(
        withJSONObject: [
            "kind": "workerSession.open",
            "paneSessionId": bridgeProductTestPaneSessionId,
            "request": NSNull(),
            "requestId": "request-open-adapter",
            "requestSequence": 1,
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": bridgeProductTestWorkerInstanceId,
        ],
        options: [.sortedKeys]
    )
}

func bridgeProductSchemeReviewCallBody(requestSequence: Int = 2) -> Data {
    try! JSONSerialization.data(
        withJSONObject: [
            "call": [
                "method": "review.markFileViewed",
                "request": ["itemId": "review-item-adapter"],
            ],
            "kind": "product.call",
            "paneSessionId": bridgeProductTestPaneSessionId,
            "requestId": "request-call-adapter",
            "requestSequence": requestSequence,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": bridgeProductTestWorkerInstanceId,
        ],
        options: [.sortedKeys]
    )
}

func bridgeProductSchemePaddedBody(_ body: Data, byteCount: Int) -> Data {
    precondition(body.count <= byteCount)
    var padded = body
    padded.append(Data(repeating: 0x20, count: byteCount - body.count))
    return padded
}

final class BridgeProductObservedBodyInputStream: InputStream, @unchecked Sendable {
    private let bytes: [UInt8]
    private let firstReadContinuation: AsyncStream<Void>.Continuation
    private let firstReadEvents: AsyncStream<Void>
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let shouldBlockFirstRead: Bool
    private var offset = 0
    private var readInvocationCountStorage = 0

    init(data: Data, blockFirstRead: Bool = false) {
        self.bytes = Array(data)
        self.shouldBlockFirstRead = blockFirstRead
        let pair = AsyncStream<Void>.makeStream()
        self.firstReadEvents = pair.stream
        self.firstReadContinuation = pair.continuation
        super.init(data: Data())
    }

    override func open() {}

    override func close() {}

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        lock.lock()
        readInvocationCountStorage += 1
        let isFirstRead = readInvocationCountStorage == 1
        lock.unlock()
        if isFirstRead {
            firstReadContinuation.yield()
            if shouldBlockFirstRead { releaseSemaphore.wait() }
        }
        guard offset < bytes.count else { return 0 }
        let count = min(len, bytes.count - offset)
        for index in 0..<count { buffer[index] = bytes[offset + index] }
        offset += count
        return count
    }

    override var hasBytesAvailable: Bool { offset < bytes.count }

    func waitUntilFirstRead() async {
        var iterator = firstReadEvents.makeAsyncIterator()
        _ = await iterator.next()
    }

    func releaseFirstRead() {
        releaseSemaphore.signal()
    }

    var readInvocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readInvocationCountStorage
    }
}

actor BridgeProductSchemeReplyEventRecorder {
    private var events: [BridgeProductSchemeReplyObservation.Event] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ event: BridgeProductSchemeReplyObservation.Event) {
        events.append(event)
        let ready = waiters.filter { $0.0 <= events.count }
        waiters.removeAll { $0.0 <= events.count }
        for (_, continuation) in ready { continuation.resume() }
    }

    func waitUntilCount(_ count: Int) async {
        guard events.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    var snapshot: [BridgeProductSchemeReplyObservation.Event] { events }
}

private func bridgeProductSchemeFrameWasAdmitted(
    _ result: BridgeProductProducerEnqueueResult
) -> Bool {
    switch result {
    case .enqueued, .queueReset:
        true
    case .rejected:
        false
    }
}
