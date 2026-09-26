import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product sealed native batch")
struct BridgeProductSealedViewBatchTests {
    @Test("a frozen batch larger than the credit window emits in order as receipts arrive")
    func sealedBatchProgressesThroughReceiptCredits() throws {
        let viewDomain = BridgeProductViewDomainKey(
            viewId: "review-subscription-1",
            domain: .singleDomain,
            incarnation: "review-incarnation-1"
        )
        let scope: BridgeProductJSONValue = .object(["kind": .string("review")])
        var producerParts: [BridgeProductBatchPart] = [
            .put(key: "item/a", revision: 4, value: .object(["itemId": .string("a")])),
            .delete(key: "item/old", revision: 4),
            .evict(key: "item/outside"),
        ]
        let sealed = try BridgeProductSealedViewBatch(
            viewDomain: viewDomain,
            producerScanGeneration: 1,
            handle: "review-handle-1",
            subscriptionKind: .reviewMetadata,
            scopeRevision: 2,
            baseRevision: 0,
            targetRevision: 4,
            mode: .snapshot,
            scope: scope,
            coveredScope: scope,
            requiresCollection: nil,
            firstDeliverySequence: 1,
            parts: producerParts
        )
        producerParts.removeAll()
        #expect(sealed.parts.count == 3)
        #expect(sealed.frameCount == 5)

        let stream = BridgeProductMetadataStreamCorrelation(
            metadataStreamId: "metadata-stream-1",
            paneSessionId: "pane-session-1",
            wireVersion: BridgeProductWireContract.version,
            workerInstanceId: "worker-instance-1"
        )
        let decoder = try BridgeProductMetadataFrameDecoder()
        let frames = try (0..<sealed.frameCount).map { ordinal in
            try sealed.frame(atOrdinal: ordinal, stream: stream, streamSequence: ordinal + 11)
        }
        for frame in frames {
            #expect(try decoder.append(BridgeProductMetadataFrameCodec.encode(frame)) == [frame])
        }
        try decoder.finish()

        var credits = BridgeProductViewCreditWindow(maximumParts: 2, maximumBytes: 1_000_000)
        credits.open(viewDomain, handle: sealed.handle)
        let firstAdmitted = credits.admitPart(for: viewDomain, handle: sealed.handle, sequence: 1, byteCount: 100)
        let secondAdmitted = credits.admitPart(for: viewDomain, handle: sealed.handle, sequence: 2, byteCount: 100)
        let thirdBeforeReceipt = credits.admitPart(for: viewDomain, handle: sealed.handle, sequence: 3, byteCount: 100)
        let firstReceived = credits.acknowledge(for: viewDomain, handle: sealed.handle, through: 1)
        let thirdAfterReceipt = credits.admitPart(for: viewDomain, handle: sealed.handle, sequence: 3, byteCount: 100)
        #expect(firstAdmitted && secondAdmitted && !thirdBeforeReceipt)
        #expect(firstReceived && thirdAfterReceipt)
    }
}
