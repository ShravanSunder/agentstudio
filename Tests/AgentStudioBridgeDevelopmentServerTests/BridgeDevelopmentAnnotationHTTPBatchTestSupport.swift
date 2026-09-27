import AgentStudioTestSupport
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer

struct HTTPAnnotationBatchObservation: Sendable {
    let batchId: String
    let putRecordKeys: Set<String>
    let targetRevision: Int
}

private enum HTTPAnnotationBatchObservationError: Error {
    case incompleteBatch
    case mismatchedRecord
    case missingSession
}

func waitForHTTPAnnotationCatalogCommit(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder
) async throws -> HTTPAnnotationBatchObservation {
    var activeBegin: BridgeProductBatchBeginFrame?
    var partsByIndex: [Int: BridgeProductBatchPart] = [:]
    while true {
        let frame = try await recorder.nextFrame()
        try await acknowledgeHTTPMetadataFrame(client: client, connection: connection, frame: frame)
        guard case .batch(let batch) = frame,
            batch.identity.subscriptionKind == .fileAnnotations
        else { continue }
        switch batch {
        case .begin(let begin):
            activeBegin = begin
            partsByIndex.removeAll(keepingCapacity: true)
        case .part(let part):
            guard part.identity.batchId == activeBegin?.identity.batchId else {
                throw HTTPAnnotationBatchObservationError.incompleteBatch
            }
            partsByIndex[part.partIndex] = part.part
        case .complete(let complete):
            guard let begin = activeBegin,
                complete.identity.batchId == begin.identity.batchId,
                complete.coveredScope == begin.scope,
                partsByIndex.count == begin.partCount
            else { throw HTTPAnnotationBatchObservationError.incompleteBatch }
            var putRecordKeys: Set<String> = []
            for partIndex in 0..<begin.partCount {
                guard let part = partsByIndex[partIndex] else {
                    throw HTTPAnnotationBatchObservationError.incompleteBatch
                }
                guard case .put(let key, let revision, let value) = part else { continue }
                let record = try BridgeProductStrictJSON.decode(
                    BridgeProductCommentCatalogRecord.self,
                    from: JSONEncoder().encode(value)
                )
                guard record.recordKey == key, record.revision == revision,
                    revision <= begin.targetRevision
                else { throw HTTPAnnotationBatchObservationError.mismatchedRecord }
                putRecordKeys.insert(key)
            }
            return .init(
                batchId: begin.identity.batchId,
                putRecordKeys: putRecordKeys,
                targetRevision: begin.targetRevision
            )
        }
    }
}

func waitForHTTPAnnotationSessionChange(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    recorder: HTTPMetadataFrameRecorder,
    expectedSessionID: UUID
) async throws -> HTTPAnnotationBatchObservation {
    let batch = try await waitForHTTPAnnotationCatalogCommit(
        client: client,
        connection: connection,
        recorder: recorder
    )
    guard batch.putRecordKeys.contains("session:\(expectedSessionID.uuidString.lowercased())") else {
        throw HTTPAnnotationBatchObservationError.missingSession
    }
    return batch
}

func acknowledgeHTTPViewPart(
    client: some TestClientProtocol,
    connection: HTTPProductConnection,
    part: BridgeProductBatchPartFrame
) async throws {
    let identity = part.identity
    let capabilityHeader = try #require(HTTPField.Name(BridgeProductWireContract.capabilityHeaderName))
    let requestBytes = try JSONSerialization.data(
        withJSONObject: [
            "kind": "subscription.acknowledge",
            "domain": identity.domain,
            "handle": identity.handle,
            "incarnation": identity.incarnation,
            "paneSessionId": identity.frame.paneSessionId,
            "receivedThroughDeliverySequence": part.deliverySequence,
            "subscriptionId": identity.subscriptionId,
            "wireVersion": identity.frame.wireVersion,
            "workerInstanceId": identity.frame.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    let request = try BridgeProductStrictJSON.decode(
        BridgeProductViewAcknowledgementRequest.self,
        from: requestBytes
    )
    let response = try await client.execute(
        uri: "/__bridge-product/command",
        method: .post,
        headers: [.contentType: "application/json", capabilityHeader: connection.capability],
        body: ByteBuffer(data: requestBytes)
    )
    guard response.status == .ok else {
        throw unexpectedHTTPAnnotationResponse(response, context: "subscription.acknowledge")
    }
    let acknowledged = try BridgeProductStrictJSON.decode(
        BridgeProductViewAcknowledgedResponse.self,
        from: Data(response.body.readableBytesView)
    )
    #expect(acknowledged == .init(correlating: request))
}
