import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product view sender state")
struct BridgeProductViewSenderStateTests {
    @Test("a credit-starved domain yields to its sibling and resumes on receipt")
    func domainsShareCreditsWithoutStarvation() throws {
        var sender = BridgeProductViewSenderState(maximumDirtyKeys: 2, creditParts: 1, creditBytes: 100_000)
        let first = BridgeProductViewDomainKey(
            viewId: "file-view",
            domain: .singleDomain,
            incarnation: "first"
        )
        let second = BridgeProductViewDomainKey(
            viewId: "file-view",
            domain: .init(rawValue: "member-b"),
            incarnation: "first"
        )
        sender.open(first, handle: "handle-1", scanGeneration: 1)
        sender.open(second, handle: "handle-1", scanGeneration: 1)
        let scope: BridgeProductJSONValue = .object([
            "kind": .string("file"),
            "changeFilter": .object(["kind": .string("none")]),
        ])
        for (key, recordKey) in [(first, "a"), (second, "b")] {
            let batch = try BridgeProductSealedViewBatch(
                viewDomain: key,
                producerScanGeneration: 1,
                handle: "handle-1",
                subscriptionKind: .fileMetadata,
                scopeRevision: 1,
                baseRevision: 0,
                targetRevision: 1,
                mode: .snapshot,
                scope: scope,
                coveredScope: scope,
                requiresCollection: nil,
                firstDeliverySequence: 1,
                parts: [.put(key: recordKey, revision: 1, value: .object(["id": .string(recordKey)]))]
            )
            try sender.seal(batch)
        }
        let stream = BridgeProductMetadataStreamCorrelation(
            metadataStreamId: "stream-1",
            paneSessionId: "pane-1",
            wireVersion: BridgeProductWireContract.version,
            workerInstanceId: "worker-1"
        )
        let firstBegin = try sender.nextFrame(stream: stream, streamSequence: 1)
        let secondBegin = try sender.nextFrame(stream: stream, streamSequence: 2)
        let firstPart = try sender.nextFrame(stream: stream, streamSequence: 3)
        let firstComplete = try sender.nextFrame(stream: stream, streamSequence: 4)
        let blocked = try sender.nextFrame(stream: stream, streamSequence: 5)

        #expect(firstBegin?.kind == "subscription.batchBegin")
        #expect(secondBegin?.kind == "subscription.batchBegin")
        #expect(firstPart?.kind == "subscription.batchPart")
        #expect(firstComplete?.kind == "subscription.batchComplete")
        #expect(blocked == nil)
        #expect(sender.outstandingPartCount(for: first) == 1)
        #expect(sender.outstandingPartCount(for: second) == 0)

        let received = sender.acknowledge(for: first, handle: "handle-1", through: 1)
        let secondPart = try sender.nextFrame(stream: stream, streamSequence: 5)
        #expect(received)
        #expect(secondPart?.kind == "subscription.batchPart")
        #expect(sender.outstandingPartCount(for: second) == 1)
    }

    @Test("a stale scan cannot seal and an ack failure resnapshots only its domain")
    func staleProducerAndScopedResnapshot() throws {
        var sender = BridgeProductViewSenderState(maximumDirtyKeys: 1, creditParts: 1, creditBytes: 100_000)
        let first = BridgeProductViewDomainKey(viewId: "file-view", domain: .singleDomain, incarnation: "first")
        let sibling = BridgeProductViewDomainKey(
            viewId: "file-view",
            domain: .init(rawValue: "member-b"),
            incarnation: "first"
        )
        sender.open(first, handle: "handle-1", scanGeneration: 2)
        sender.open(sibling, handle: "handle-1", scanGeneration: 1)
        _ = sender.takePending(for: first)
        _ = sender.takePending(for: sibling)
        let staleInput = sender.recordChange(for: first, scanGeneration: 1, recordKey: "old", revision: 1)
        let siblingInput = sender.recordChange(for: sibling, scanGeneration: 1, recordKey: "new", revision: 2)
        sender.resnapshot(first)
        #expect(!staleInput && siblingInput)
        #expect(sender.pending(for: first) == .snapshotRequired)
        #expect(sender.pending(for: sibling) == .keys(["new": 2]))
    }
}
