import CryptoKit
import Foundation

@testable import AgentStudio

struct BridgeProductSchemeTranscriptFixture {
    static let expectedSHA256 =
        "9dbb1c5d33f832e0c76b09859fdc9aed6561256033b6acede000df4f2a774112"

    let bytes: Data
    let root: [String: Any]

    static func load() throws -> Self {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let bytes = try Data(
            contentsOf: projectRoot.appending(
                path: "Tests/BridgeContractFixtures/valid/bridge-product-startup-transcript.json"
            )
        )
        let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard let root else { throw BridgeProductSchemeTranscriptFixtureError.invalidRoot }
        return .init(bytes: bytes, root: root)
    }

    var sha256Hex: String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    var transcriptCount: Int {
        (root["transcript"] as? [[String: Any]])?.count ?? 0
    }

    var observationCaseCount: Int {
        (root["observationCases"] as? [[String: Any]])?.count ?? 0
    }

    func transcriptValueData(named name: String) throws -> Data {
        let entry = try namedEntry(name, collection: "transcript")
        guard let value = entry["value"] as? [String: Any] else {
            throw BridgeProductSchemeTranscriptFixtureError.missingValue(name)
        }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    func observationRequestData(named name: String) throws -> Data {
        let entry = try namedEntry(name, collection: "observationCases")
        guard let request = entry["request"] as? [String: Any] else {
            throw BridgeProductSchemeTranscriptFixtureError.missingValue(name)
        }
        return try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    }

    func decodeTranscriptValue<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        named name: String
    ) throws -> DecodedValue {
        try BridgeProductStrictJSON.decode(type, from: transcriptValueData(named: name))
    }

    func decodeObservationRequest<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        named name: String
    ) throws -> DecodedValue {
        try BridgeProductStrictJSON.decode(type, from: observationRequestData(named: name))
    }

    func subscriptionData(named name: String) throws -> BridgeProductSubscriptionData {
        let frame = try decodeTranscriptValue(BridgeProductMetadataFrame.self, named: name)
        guard case .subscriptionData(let dataFrame) = frame else {
            throw BridgeProductSchemeTranscriptFixtureError.unexpectedFrameKind(name)
        }
        return dataFrame.data
    }

    private func namedEntry(
        _ name: String,
        collection: String
    ) throws -> [String: Any] {
        guard let entries = root[collection] as? [[String: Any]],
            let entry = entries.first(where: { $0["name"] as? String == name })
        else {
            throw BridgeProductSchemeTranscriptFixtureError.missingEntry(name)
        }
        return entry
    }
}

enum BridgeProductSchemeTranscriptFixtureError: Error {
    case invalidRoot
    case missingEntry(String)
    case missingValue(String)
    case unexpectedFrameKind(String)
}

struct BridgeProductSchemeAdapterTranscriptHarness {
    struct TeardownResult: Sendable {
        let producerSnapshot: BridgeProductProducerRegistrySnapshot
        let providerSnapshot: BridgeProductSchemeTranscriptProvider.Snapshot
        let revoked: Bool
    }

    let adapter: BridgeProductSchemeAdapter
    let capabilityHeader: String
    let provider: BridgeProductSchemeTranscriptProvider
    let session: BridgeProductSession

    static func make(
        paneSessionId: String,
        workerInstanceId: String,
        reviewSourceData: BridgeProductSubscriptionData,
        fileSourceData: BridgeProductSubscriptionData
    ) throws -> Self {
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: paneSessionId,
            workerInstanceId: workerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = BridgeProductSchemeTranscriptProvider(
            reviewSourceData: reviewSourceData,
            fileSourceData: fileSourceData
        )
        return .init(
            adapter: .init(session: session, provider: provider),
            capabilityHeader: capabilityHeader,
            provider: provider,
            session: session
        )
    }

    func request(
        route: String,
        body: Data,
        capability: String? = nil,
        bodyStream: InputStream? = nil
    ) -> URLRequest {
        bridgeProductSchemeRequest(
            route: route,
            capability: capability ?? capabilityHeader,
            body: bodyStream == nil ? body : nil,
            bodyStream: bodyStream
        )
    }

    func teardown(routingTasks: [Task<Void, Never>]) async -> TeardownResult {
        for routingTask in routingTasks { routingTask.cancel() }
        for routingTask in routingTasks { await routingTask.value }
        let revocation = await session.revoke { acknowledgement in
            await provider.acknowledgeLifecycle(acknowledgement)
        }
        let revoked = await revocation.wait()
        return .init(
            producerSnapshot: await session.producerSnapshot(),
            providerSnapshot: await provider.snapshot,
            revoked: revoked
        )
    }
}

actor BridgeProductSchemeTranscriptProvider: BridgeProductSchemeProvider {
    struct Snapshot: Sendable {
        let acknowledgedLifecycleCount: Int
        let contentRequestCount: Int
        let controlRequestKinds: [String]
        let metadataRequestCount: Int
        let producerFailureCount: Int
    }

    private var acknowledgedLifecycleCount = 0
    private let contentOperationGate = BridgeProductSessionProducerOperationGate()
    private var contentRequestCount = 0
    private var controlRequestKinds: [String] = []
    private let fileSourceData: BridgeProductSubscriptionData
    private var metadataRequestCount = 0
    private let metadataOperationGate = BridgeProductSessionProducerOperationGate()
    private var metadataSession: BridgeProductSession?
    private var producerFailures: [String] = []
    private let reviewSourceData: BridgeProductSubscriptionData

    init(
        reviewSourceData: BridgeProductSubscriptionData,
        fileSourceData: BridgeProductSubscriptionData
    ) {
        self.reviewSourceData = reviewSourceData
        self.fileSourceData = fileSourceData
    }

    func response(for request: BridgeProductControlRequest) async -> BridgeProductControlResponse {
        controlRequestKinds.append(request.kind)
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .subscriptionOpen(let openRequest):
                let emptyInterestState = BridgeProductSubscriptionState.emptyInterestState(
                    for: openRequest.subscription.subscriptionKind
                )
                return try .subscriptionOpenAccepted(
                    correlating: request,
                    interestSha256: emptyInterestState.sha256Hex()
                )
            case .subscriptionUpdateBatch(let updateRequest):
                let disposition: BridgeProductSubscriptionUpdateBatchDisposition =
                    updateRequest.batchIndex + 1 == updateRequest.batchCount ? .committed : .staged
                return try .subscriptionUpdateBatchAccepted(
                    correlating: request,
                    disposition: disposition
                )
            case .subscriptionCancel:
                return try .subscriptionCancelAccepted(correlating: request)
            case .productCall, .workerSessionResync:
                preconditionFailure("Unexpected transcript control request")
            }
        } catch {
            preconditionFailure("Could not build a correlated transcript response")
        }
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        metadataRequestCount += 1
        metadataSession = session
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
            guard case .enqueued = result else {
                producerFailures.append("metadata opening frame rejected")
                return
            }
            await metadataOperationGate.run(lease)
        } catch {
            producerFailures.append("metadata producer failed")
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
            guard case .enqueued = result else {
                producerFailures.append("content opening frame rejected")
                return
            }
            await contentOperationGate.run(lease)
        } catch {
            producerFailures.append("content producer failed")
        }
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        _ = acknowledgement
        acknowledgedLifecycleCount += 1
        return true
    }

    func applyCommittedControlEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        for request: BridgeProductControlRequest
    ) async {
        _ = request
        guard case .subscriptionOpened(let subscription) = effect,
            let metadataSession
        else { return }
        let data: BridgeProductSubscriptionData
        switch subscription.subscriptionKind {
        case .reviewMetadata:
            data = reviewSourceData
        case .fileMetadata:
            data = fileSourceData
        }
        do {
            let result = try await metadataSession.enqueueSubscriptionData(
                subscriptionId: subscription.subscriptionId,
                data: data
            )
            guard case .enqueued = result else {
                producerFailures.append("subscription source frame rejected")
                return
            }
        } catch {
            producerFailures.append("subscription source frame failed")
        }
    }

    var snapshot: Snapshot {
        .init(
            acknowledgedLifecycleCount: acknowledgedLifecycleCount,
            contentRequestCount: contentRequestCount,
            controlRequestKinds: controlRequestKinds,
            metadataRequestCount: metadataRequestCount,
            producerFailureCount: producerFailures.count
        )
    }
}
