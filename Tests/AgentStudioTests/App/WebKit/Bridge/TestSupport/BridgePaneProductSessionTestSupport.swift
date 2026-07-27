import Foundation
import Testing

@testable import AgentStudioBridge

func openBridgePaneProductSession(
    _ installation: BridgeProductSessionInstallation
) async throws {
    let requestBody = try JSONSerialization.data(
        withJSONObject: [
            "kind": "workerSession.open",
            "paneSessionId": installation.bootstrap.paneSessionId,
            "request": NSNull(),
            "requestId": "request-open-pane-owner",
            "requestSequence": 1,
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": installation.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
        installation.capabilityBytes
    )
    let observation = try await collectBridgeProductSchemeReply(
        adapter: installation.productAdapter,
        request: bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: capabilityHeader,
            body: requestBody
        )
    )
    #expect(observation.response?.statusCode == 200)
}

func startBridgePaneProductMetadataReply(
    installation: BridgeProductSessionInstallation,
    provider: BridgePaneProductSessionProviderGate,
    handler: BridgeSchemeHandler? = nil
) async throws -> Task<BridgeProductSchemeReplyObservation, any Error> {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-pane-owner",
            "paneSessionId": installation.bootstrap.paneSessionId,
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": installation.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
        installation.capabilityBytes
    )
    let replyTask = Task {
        try await collectPaneOwnerProductReply(
            handler: handler,
            adapter: installation.productAdapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.streamRoute,
                capability: capabilityHeader,
                body: body
            )
        )
    }
    await provider.waitUntilMetadataProducerStarted()
    return replyTask
}

private func collectPaneOwnerProductReply(
    handler: BridgeSchemeHandler?,
    adapter: BridgeProductSchemeAdapter,
    request: URLRequest
) async throws -> BridgeProductSchemeReplyObservation {
    if let handler {
        return try await collectBridgeSchemeHandlerProductReply(
            handler: handler,
            request: request
        )
    }
    return try await collectBridgeProductSchemeReply(
        adapter: adapter,
        request: request
    )
}

private func collectBridgeSchemeHandlerProductReply(
    handler: BridgeSchemeHandler,
    request: URLRequest
) async throws -> BridgeProductSchemeReplyObservation {
    var body = Data()
    var events: [BridgeProductSchemeReplyObservation.Event] = []
    var response: HTTPURLResponse?
    for try await result in handler.reply(for: request) {
        switch result {
        case .response(let emittedResponse):
            events.append(.response)
            response = emittedResponse as? HTTPURLResponse
        case .data(let chunk):
            events.append(.data)
            body.append(chunk)
        @unknown default:
            Issue.record("Unexpected URL scheme task result")
        }
    }
    return .init(body: body, events: events, response: response)
}

actor BridgePaneProductSessionProviderGate: BridgeProductSchemeProvider {
    private enum AcknowledgementMode {
        case fail
        case failOnceThenHold
        case hold
        case succeed
    }

    private var acknowledgementMode = AcknowledgementMode.succeed
    private var acknowledgementWaiters: [CheckedContinuation<Bool, Never>] = []
    private var invocationWaiters: [(Int, CheckedContinuation<BridgeProductProducerLifecycleAcknowledgement, Never>)] =
        []
    private let contentOperation = BridgeProductSessionProducerOperationGate()
    private let metadataOperation = BridgeProductSessionProducerOperationGate()
    private var productCallResponseContinuation: CheckedContinuation<Void, Never>?
    private var productCallStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldProductCallResponses = false
    private(set) var lifecycleAcknowledgements: [BridgeProductProducerLifecycleAcknowledgement] = []
    private(set) var lifecycleAcknowledgementsWereReleased = false

    func response(
        for request: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse {
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .productCall:
                let waiters = productCallStartWaiters
                productCallStartWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
                if shouldHoldProductCallResponses {
                    await withCheckedContinuation { continuation in
                        productCallResponseContinuation = continuation
                    }
                }
                return try .callCompleted(
                    correlating: request,
                    result: .reviewMarkFileViewed
                )
            case .subscriptionOpen, .subscriptionUpdateBatch, .subscriptionCancel,
                .workerSessionResync:
                preconditionFailure("Unexpected pane-owner control request")
            }
        } catch {
            preconditionFailure("Could not build pane-owner control response")
        }
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        do {
            _ = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                productAdmission: productAdmission,
                build: { sequence in
                    try bridgeProductMetadataAcceptedFrame(
                        request: request,
                        streamSequence: sequence,
                        resumeDisposition: .snapshotRequired
                    )
                }
            )
            await metadataOperation.run(lease)
        } catch {
            Issue.record("Metadata producer failed before retirement")
        }
    }

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        do {
            _ = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                productAdmission: productAdmission,
                build: { _ in producerRegistryContentOpeningFrame(for: request) }
            )
            await contentOperation.run(lease)
        } catch {
            Issue.record("Content producer failed before retirement")
        }
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        lifecycleAcknowledgements.append(acknowledgement)
        resumeInvocationWaiters()
        switch acknowledgementMode {
        case .fail:
            return false
        case .failOnceThenHold:
            acknowledgementMode = .hold
            return false
        case .hold:
            return await withCheckedContinuation { continuation in
                acknowledgementWaiters.append(continuation)
            }
        case .succeed:
            return true
        }
    }

    func waitUntilMetadataProducerStarted() async {
        _ = await metadataOperation.waitUntilStarted()
    }

    func waitUntilContentProducerStarted() async {
        _ = await contentOperation.waitUntilStarted()
    }

    func holdProductCallResponses() {
        shouldHoldProductCallResponses = true
    }

    func waitUntilProductCallStarted() async {
        if productCallResponseContinuation != nil { return }
        await withCheckedContinuation { continuation in
            productCallStartWaiters.append(continuation)
        }
    }

    func releaseProductCallResponses() {
        shouldHoldProductCallResponses = false
        productCallResponseContinuation?.resume()
        productCallResponseContinuation = nil
    }

    func holdLifecycleAcknowledgements() {
        acknowledgementMode = .hold
        lifecycleAcknowledgementsWereReleased = false
    }

    func failLifecycleAcknowledgements() {
        acknowledgementMode = .fail
    }

    func failNextLifecycleAcknowledgementThenHoldRetries() {
        acknowledgementMode = .failOnceThenHold
        lifecycleAcknowledgementsWereReleased = false
    }

    func succeedLifecycleAcknowledgements() {
        acknowledgementMode = .succeed
    }

    func releaseLifecycleAcknowledgements(result: Bool) {
        acknowledgementMode = result ? .succeed : .fail
        lifecycleAcknowledgementsWereReleased = true
        let waiters = acknowledgementWaiters
        acknowledgementWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
    }

    func waitForLifecycleAcknowledgement(
        count: Int
    ) async -> BridgeProductProducerLifecycleAcknowledgement {
        if lifecycleAcknowledgements.count >= count {
            return lifecycleAcknowledgements[count - 1]
        }
        return await withCheckedContinuation { continuation in
            invocationWaiters.append((count, continuation))
        }
    }

    private func resumeInvocationWaiters() {
        let readyWaiters = invocationWaiters.filter { $0.0 <= lifecycleAcknowledgements.count }
        invocationWaiters.removeAll { $0.0 <= lifecycleAcknowledgements.count }
        for (count, waiter) in readyWaiters {
            waiter.resume(returning: lifecycleAcknowledgements[count - 1])
        }
    }
}
