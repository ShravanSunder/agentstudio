import AgentStudioTestSupport
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer
@testable import AgentStudioCore

@MainActor
struct HTTPDevelopmentProductRuntime {
    let composition: BridgeDevelopmentServerCoreComposition
    let host: BridgeDevelopmentProductHost
}

@MainActor
struct HTTPAnnotationAuthoringContext {
    let descriptor: BridgeProductFileContentDescriptor
    let fileSource: BridgeProductFileSourceSpec
    let metadataStream: HTTPMetadataStreamHandle
}

@MainActor
struct HTTPAnnotationLocatedRestoreContext {
    let connection: HTTPProductConnection
    let metadataStream: HTTPMetadataStreamHandle
}

@MainActor
func makeHTTPDevelopmentProductRuntime(
    dataRoot: URL,
    paneID: UUID,
    worktreeRoot: URL
) async throws -> HTTPDevelopmentProductRuntime {
    let configuration = try BridgeDevelopmentServerConfiguration(
        dataRoot: dataRoot,
        paneID: paneID,
        port: 43_871,
        seedContributionTarget: .ref(name: "HEAD"),
        seedWorktreeRoot: worktreeRoot
    )
    let composition = try await BridgeDevelopmentServerCoreComposition.prepare(
        configuration: configuration
    )
    return try await HTTPDevelopmentProductRuntime(
        composition: composition,
        host: BridgeDevelopmentProductHost(
            source: composition.productSource,
            worktreeAnnotationStore: composition.worktreeAnnotationStore,
            worktreeAnnotationOutputCoordinator:
                composition.worktreeAnnotationOutputCoordinator,
            originatingWorkspaceID: composition.originatingWorkspaceID,
            contributionTargetCommit: { target in
                composition.applyContributionTarget(target)
            }
        )
    )
}

@MainActor
func prepareHTTPAnnotationAuthoring(
    client: some TestClientProtocol,
    runtime: HTTPDevelopmentProductRuntime,
    connection: HTTPProductConnection
) async throws -> HTTPAnnotationAuthoringContext {
    let metadataStream = try await startHTTPMetadataStream(
        host: runtime.host,
        connection: connection,
        streamID: "metadata-stream-annotation-authoring"
    )
    let _: BridgeProductMetadataStreamAcceptedFrame = try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { frame in
        guard case .metadataStreamAccepted(let accepted) = frame else { return nil }
        return accepted
    }
    let fileSource = try await queryHTTPFileSource(
        client: client,
        connection: connection,
        requestSequence: 2
    )
    _ = try await openHTTPSubscription(
        client: client,
        connection: connection,
        requestSequence: 3,
        subscription: [
            "source": try jsonObject(fileSource),
            "subscriptionKind": "file.metadata",
        ],
        subscriptionID: "file-metadata-annotation-authoring"
    )
    _ = try await waitForAcknowledgedSubscription(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder,
        subscriptionID: "file-metadata-annotation-authoring"
    )
    let descriptor: BridgeProductFileContentDescriptor =
        try await waitForAcknowledgedMetadataFrame(
            client: client,
            connection: connection,
            recorder: metadataStream.recorder
        ) { frame in
            guard case .subscriptionData(let dataFrame) = frame,
                case .fileMetadata(.descriptorReady(let event)) = dataFrame.data,
                case .available(let descriptor) = event.payload.availability
            else { return nil }
            return descriptor
        }
    let _: BridgeProductFileSourceIdentity = try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { frame in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileMetadata(.sourceAccepted(let event)) = dataFrame.data
        else { return nil }
        return event.source
    }
    _ = try await openHTTPSubscription(
        client: client,
        connection: connection,
        requestSequence: 4,
        subscription: ["subscriptionKind": "file.annotations"],
        subscriptionID: "file-annotations-authoring"
    )
    _ = try await waitForAcknowledgedSubscription(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder,
        subscriptionID: "file-annotations-authoring"
    )
    try await executeHTTPAnnotationCommand(
        client: client,
        connection: connection,
        operation: ["kind": "session.discover"],
        requestID: "annotation-discover-authoring",
        requestSequence: 5
    )
    _ = try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { frame -> BridgeProductWorktreeAnnotationProjectionState? in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileAnnotations(.projectionState(let state)) = dataFrame.data
        else { return nil }
        return state
    }
    return .init(
        descriptor: descriptor,
        fileSource: fileSource,
        metadataStream: metadataStream
    )
}

@MainActor
func prepareHTTPAnnotationLocatedRestore(
    client: some TestClientProtocol,
    runtime: HTTPDevelopmentProductRuntime,
    sessionID: UUID,
    threadID: UUID,
    messageID: UUID
) async throws -> HTTPAnnotationLocatedRestoreContext {
    let connection = try await openHTTPProductConnection(client: client)
    let metadataStream = try await startHTTPMetadataStream(
        host: runtime.host,
        connection: connection,
        streamID: "metadata-stream-located-annotation-restore"
    )
    let _: BridgeProductMetadataStreamAcceptedFrame = try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { frame in
        guard case .metadataStreamAccepted(let accepted) = frame else { return nil }
        return accepted
    }
    let fileSource = try await queryHTTPFileSource(
        client: client,
        connection: connection,
        requestSequence: 2
    )
    _ = try await openHTTPSubscription(
        client: client,
        connection: connection,
        requestSequence: 3,
        subscription: [
            "source": try jsonObject(fileSource),
            "subscriptionKind": "file.metadata",
        ],
        subscriptionID: "file-metadata-located-restore"
    )
    _ = try await waitForAcknowledgedSubscription(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder,
        subscriptionID: "file-metadata-located-restore"
    )
    let _: BridgeProductFileSourceIdentity = try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { frame in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileMetadata(.sourceAccepted(let event)) = dataFrame.data
        else { return nil }
        return event.source
    }
    _ = try await openHTTPSubscription(
        client: client,
        connection: connection,
        requestSequence: 4,
        subscription: ["subscriptionKind": "file.annotations"],
        subscriptionID: "file-annotations-located-restore"
    )
    _ = try await waitForAcknowledgedSubscription(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder,
        subscriptionID: "file-annotations-located-restore"
    )
    try await executeHTTPAnnotationCommand(
        client: client,
        connection: connection,
        operation: ["kind": "session.discover"],
        requestID: "annotation-discover-located-after-restart",
        requestSequence: 5
    )
    _ = try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { frame -> BridgeProductWorktreeAnnotationSessionSummary? in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileAnnotations(.projectionState(let state)) = dataFrame.data
        else { return nil }
        return state.sessions.first(where: { $0.sessionId == sessionID })
    }
    try await executeHTTPAnnotationCommand(
        client: client,
        connection: connection,
        operation: [
            "kind": "demand.acquire",
            "sessionId": sessionID.uuidString.lowercased(),
        ],
        requestID: "annotation-demand-located-after-restart",
        requestSequence: 6
    )
    _ = try await waitForHTTPAnnotationMessageBatch(
        client: client,
        connection: connection,
        recorder: metadataStream.recorder
    ) { batch in
        batch.context.threadId == threadID
            && batch.messages.contains(where: { $0.messageId == messageID })
    }
    return .init(connection: connection, metadataStream: metadataStream)
}

struct HTTPProductConnection: Sendable {
    let bootstrap: BridgeProductSessionBootstrap
    let capability: String
}

struct HTTPMetadataStreamHandle {
    let recorder: HTTPMetadataFrameRecorder
    let drain: Task<Void, any Error>
}

enum HTTPAnnotationIntegrationError: Error {
    case annotationCommandFailed
    case invalidJSONObject
    case metadataStreamEnded
    case unexpectedControlResponse
    case unexpectedHTTPResponse
}

func startHTTPMetadataStream(
    host: BridgeDevelopmentProductHost,
    connection: HTTPProductConnection,
    streamID: String
) async throws -> HTTPMetadataStreamHandle {
    let capabilityHeader = try #require(
        HTTPField.Name(BridgeProductWireContract.capabilityHeaderName)
    )
    let body = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": streamID,
            "paneSessionId": connection.bootstrap.paneSessionId,
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": connection.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    var request = URLRequest(url: try #require(URL(string: "agentstudio://rpc/stream")))
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: HTTPField.Name.contentType.rawName)
    request.setValue(connection.capability, forHTTPHeaderField: capabilityHeader.rawName)
    let response = try await BridgeDevelopmentHTTPProductResponse.make(
        from: await host.route(request)
    )
    guard response.status == .ok,
        response.headers[.contentType] == "application/octet-stream"
    else {
        throw HTTPAnnotationIntegrationError.unexpectedHTTPResponse
    }
    let recorder = try HTTPMetadataFrameRecorder()
    let responseBody = response.body
    let drain = Task {
        try await responseBody.write(recorder)
    }
    return .init(recorder: recorder, drain: drain)
}

func waitForHTTPAnnotationCommandOutcome(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder,
    requestID: String
) async throws -> BridgeProductWorktreeAnnotationCommandOutcomeDTO {
    try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: recorder
    ) { frame in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileAnnotations(.projectionState(let state)) = dataFrame.data
        else { return nil }
        return state.commandOutcomes.first(where: { $0.requestId == requestID })
    }
}

func waitForHTTPMetadataStreamTermination(
    _ drain: Task<Void, any Error>
) async throws {
    try await drain.value
}

func openHTTPProductConnection(
    client: some TestClientProtocol
) async throws -> HTTPProductConnection {
    let bootstrapResponse = try await client.execute(
        uri: "/__bridge-product/bootstrap",
        method: .post,
        headers: [.contentType: "application/json"],
        body: ByteBuffer(
            string:
                #"{"navigationIntent":{"commandId":"open-file-view","commandKind":"activateContext","surface":"file"},"reason":"initial"}"#
        )
    )
    let envelope = try decodeHTTPBootstrapEnvelope(
        Data(bootstrapResponse.body.readableBytesView)
    )
    let connection = try HTTPProductConnection(
        bootstrap: envelope.bootstrap,
        capability: BridgeProductCapabilityHeaderEncoding.encode(Array(envelope.capabilityBytes))
    )
    let response = try await executeHTTPControl(
        client: client,
        connection: connection,
        object: httpControlIdentity(
            connection: connection,
            kind: "workerSession.open",
            requestID: "worker-session-open",
            requestSequence: 1
        ).merging(["request": NSNull()]) { _, newValue in newValue }
    )
    guard case .workerSessionAccepted = response else {
        throw HTTPAnnotationIntegrationError.unexpectedControlResponse
    }
    return connection
}

func queryHTTPFileSource(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    requestSequence: Int
) async throws -> BridgeProductFileSourceSpec {
    let response = try await executeHTTPControl(
        client: client,
        connection: connection,
        object: httpSurfaceControlIdentity(
            connection: connection,
            kind: "product.call",
            requestID: "file-source-current",
            requestSequence: requestSequence
        ).merging([
            "call": [
                "method": "file.source.current",
                "request": [:],
            ]
        ]) { _, newValue in newValue }
    )
    guard case .callCompleted(let completed) = response,
        case .fileSourceCurrent(.available(let source)) = completed.call
    else {
        throw HTTPAnnotationIntegrationError.unexpectedControlResponse
    }
    return source
}

func openHTTPSubscription(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    requestSequence: Int,
    subscription: [String: Any],
    subscriptionID: String
) async throws -> BridgeProductSubscriptionOpenAcceptedResponse {
    let response = try await executeHTTPControl(
        client: client,
        connection: connection,
        object: httpSurfaceControlIdentity(
            connection: connection,
            kind: "subscription.open",
            requestID: "subscription-open-\(subscriptionID)",
            requestSequence: requestSequence
        ).merging([
            "subscription": subscription,
            "subscriptionId": subscriptionID,
        ]) { _, newValue in newValue }
    )
    guard case .subscriptionOpenAccepted(let accepted) = response,
        accepted.subscriptionId == subscriptionID
    else {
        throw HTTPAnnotationIntegrationError.unexpectedControlResponse
    }
    return accepted
}

func waitForHTTPAnnotationMessageBatch(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder,
    match: @escaping @Sendable (BridgeProductWorktreeAnnotationMessageBatch) -> Bool
) async throws -> BridgeProductWorktreeAnnotationMessageBatch {
    try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: recorder
    ) { frame -> BridgeProductWorktreeAnnotationMessageBatch? in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileAnnotations(.messageBatch(let batch)) = dataFrame.data,
            match(batch)
        else { return nil }
        return batch
    }
}

func executeHTTPAnnotationCommand(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    operation: [String: Any],
    requestID: String,
    requestSequence: Int
) async throws {
    let response = try await executeHTTPControl(
        client: client,
        connection: connection,
        object: httpSurfaceControlIdentity(
            connection: connection,
            kind: "product.call",
            requestID: requestID,
            requestSequence: requestSequence
        ).merging([
            "call": [
                "method": "file.annotations.command",
                "request": ["operation": operation],
            ]
        ]) { _, newValue in newValue }
    )
    guard case .callCompleted(let completed) = response,
        case .fileAnnotationsCommand(.accepted) = completed.call
    else {
        throw HTTPAnnotationIntegrationError.unexpectedControlResponse
    }
}

private func executeHTTPControl(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    object: [String: Any]
) async throws -> BridgeProductControlResponse {
    let capabilityHeader = try #require(
        HTTPField.Name(BridgeProductWireContract.capabilityHeaderName)
    )
    let response = try await client.execute(
        uri: "/__bridge-product/command",
        method: .post,
        headers: [
            .contentType: "application/json",
            capabilityHeader: connection.capability,
        ],
        body: ByteBuffer(
            data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    )
    guard response.status == .ok,
        response.headers[.contentType] == "application/json"
    else {
        throw HTTPAnnotationIntegrationError.unexpectedHTTPResponse
    }
    return try BridgeProductStrictJSON.decode(
        BridgeProductControlResponse.self,
        from: Data(response.body.readableBytesView)
    )
}

private func httpControlIdentity(
    connection: HTTPProductConnection,
    kind: String,
    requestID: String,
    requestSequence: Int
) -> [String: Any] {
    [
        "kind": kind,
        "paneSessionId": connection.bootstrap.paneSessionId,
        "requestId": requestID,
        "requestSequence": requestSequence,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": connection.bootstrap.workerInstanceId,
    ]
}

private func httpSurfaceControlIdentity(
    connection: HTTPProductConnection,
    kind: String,
    requestID: String,
    requestSequence: Int
) -> [String: Any] {
    httpControlIdentity(
        connection: connection,
        kind: kind,
        requestID: requestID,
        requestSequence: requestSequence
    ).merging(["workerDerivationEpoch": 0]) { _, newValue in newValue }
}

func jsonObject<EncodableValue: Encodable>(
    _ value: EncodableValue
) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw HTTPAnnotationIntegrationError.invalidJSONObject
    }
    return object
}

func waitForAcknowledgedSubscription(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder,
    subscriptionID: String
) async throws -> BridgeProductSubscriptionAcceptedFrame {
    try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: recorder
    ) { frame -> BridgeProductSubscriptionAcceptedFrame? in
        guard case .subscriptionAccepted(let accepted) = frame,
            accepted.subscriptionIdentity.subscriptionId == subscriptionID
        else { return nil }
        return accepted
    }
}

func waitForAcknowledgedDraft(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder,
    body: String,
    sessionID: UUID
) async throws -> BridgeProductWorktreeAnnotationMessageEntry {
    try await waitForAcknowledgedMetadataFrame(
        client: client,
        connection: connection,
        recorder: recorder
    ) { frame -> BridgeProductWorktreeAnnotationMessageEntry? in
        guard case .subscriptionData(let dataFrame) = frame,
            case .fileAnnotations(.messageBatch(let batch)) = dataFrame.data
        else { return nil }
        return batch.messages.first(where: {
            $0.sessionId == sessionID && $0.draft?.body == body
        })
    }
}

func waitForAcknowledgedMetadataFrame<MatchedValue: Sendable>(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder,
    match: @Sendable (BridgeProductMetadataFrame) -> MatchedValue?
) async throws -> MatchedValue {
    while true {
        let frame = try await recorder.nextFrame()
        try await acknowledgeHTTPMetadataFrame(
            client: client,
            connection: connection,
            frame: frame
        )
        if let matchedValue = match(frame) {
            return matchedValue
        }
    }
}

private func acknowledgeHTTPMetadataFrame(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    frame: BridgeProductMetadataFrame
) async throws {
    let identity = metadataFrameIdentity(frame)
    let capabilityHeader = try #require(
        HTTPField.Name(BridgeProductWireContract.capabilityHeaderName)
    )
    let acknowledgement = try JSONSerialization.data(
        withJSONObject: [
            "kind": "stream.frameObserved",
            "metadataStreamId": identity.metadataStreamId,
            "paneSessionId": identity.paneSessionId,
            "streamKind": "metadata",
            "streamSequence": identity.streamSequence,
            "wireVersion": identity.wireVersion,
            "workerInstanceId": identity.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    let response = try await client.execute(
        uri: "/__bridge-product/command",
        method: .post,
        headers: [
            .contentType: "application/json",
            capabilityHeader: connection.capability,
        ],
        body: ByteBuffer(data: acknowledgement)
    )
    guard response.status == .noContent else {
        throw HTTPAnnotationIntegrationError.unexpectedHTTPResponse
    }
}

private func metadataFrameIdentity(
    _ frame: BridgeProductMetadataFrame
) -> BridgeProductMetadataFrameIdentity {
    switch frame {
    case .metadataStreamAccepted(let value): value.frameIdentity
    case .panePresentation(let value): value.frameIdentity
    case .paneSurfaceSelectionRequested(let value): value.frameIdentity
    case .subscriptionAccepted(let value): value.frameIdentity
    case .subscriptionInterestsCommitted(let value): value.identity.frameIdentity
    case .subscriptionData(let value): value.frameIdentity
    case .subscriptionReset(let value): value.identity.frameIdentity
    case .subscriptionEnd(let value): value.identity.frameIdentity
    case .subscriptionCancelled(let value): value.identity.frameIdentity
    case .contentCancelled(let value): value.frameIdentity
    case .metadataStreamError(let value): value.frameIdentity
    }
}

actor HTTPMetadataFrameRecorder: ResponseBodyWriter {
    private let decoder: BridgeProductMetadataFrameDecoder
    private var frames: [BridgeProductMetadataFrame] = []
    private var nextReadIndex = 0
    private var nextFrameWaiters: [CheckedContinuation<Void, Never>] = []
    private var nextFrameSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var terminalResult: Result<Void, any Error>?

    init() throws {
        self.decoder = try BridgeProductMetadataFrameDecoder()
    }

    func write(_ buffer: ByteBuffer) throws {
        let data = Data(buffer.readableBytesView)
        do {
            frames.append(contentsOf: try decoder.append(data))
        } catch {
            complete(.failure(error))
            throw error
        }
        resumeFrameWaiters()
    }

    func finish(_: HTTPFields?) throws {
        do {
            try decoder.finish()
            complete(.success(()))
        } catch {
            complete(.failure(error))
            throw error
        }
    }

    func fail(_ error: any Error) {
        complete(.failure(error))
    }

    func nextFrame() async throws -> BridgeProductMetadataFrame {
        while true {
            if nextReadIndex < frames.count {
                defer { nextReadIndex += 1 }
                return frames[nextReadIndex]
            }
            if let terminalResult {
                try terminalResult.get()
                throw HTTPAnnotationIntegrationError.metadataStreamEnded
            }
            try await waitForAnotherFrame()
        }
    }

    func waitUntilNextFrameSuspends() async {
        if !nextFrameWaiters.isEmpty || terminalResult != nil { return }
        await withCheckedContinuation { continuation in
            nextFrameSuspensionWaiters.append(continuation)
        }
    }

    private func waitForAnotherFrame() async throws {
        await withCheckedContinuation { continuation in
            nextFrameWaiters.append(continuation)
            resumeNextFrameSuspensionWaiters()
        }
    }

    private func complete(_ result: Result<Void, any Error>) {
        guard terminalResult == nil else { return }
        terminalResult = result
        resumeFrameWaiters()
    }

    private func resumeFrameWaiters() {
        let waiters = nextFrameWaiters
        nextFrameWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters { waiter.resume() }
    }

    private func resumeNextFrameSuspensionWaiters() {
        let waiters = nextFrameSuspensionWaiters
        nextFrameSuspensionWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters { waiter.resume() }
    }
}
