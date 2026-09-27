import Foundation

struct BridgeProductFileViewSnapshotInput: Sendable {
    let viewDomain: BridgeProductViewDomainKey
    let handle: String
    let scopeRevision: Int
    let scope: BridgeProductJSONValue
    let firstDeliverySequence: Int
    let snapshot: BridgeWorktreeFileKeyedSnapshot
}

/// Freezes the index's canonical keys and revisions into one certified File snapshot.
enum BridgeProductFileViewBatchFactory {
    static func sealSnapshot(_ input: BridgeProductFileViewSnapshotInput) throws -> BridgeProductSealedViewBatch {
        var parts: [BridgeProductBatchPart] = []
        parts.reserveCapacity(input.snapshot.records.count + input.snapshot.tombstoneRevisionByKey.count + 1)
        for record in input.snapshot.records.sorted(by: { $0.key < $1.key }) {
            let row = try BridgeProductFileBatchRow(
                sourceRow: record.row,
                descriptorOutcome: record.descriptorOutcome
            )
            let encoded = try JSONEncoder().encode(row)
            let value = try JSONDecoder().decode(BridgeProductJSONValue.self, from: encoded)
            parts.append(.put(key: record.key, revision: record.revision, value: value))
        }
        for (key, revision) in input.snapshot.tombstoneRevisionByKey.sorted(by: { $0.key < $1.key }) {
            parts.append(.delete(key: key, revision: revision))
        }
        let encodedStatus = try JSONEncoder().encode(input.snapshot.memberStatus.record)
        let statusValue = try JSONDecoder().decode(BridgeProductJSONValue.self, from: encodedStatus)
        parts.append(
            .put(
                key: BridgeProductFileMemberStatusRecord.recordKey,
                revision: input.snapshot.memberStatus.revision,
                value: statusValue
            ))
        return try BridgeProductSealedViewBatch(
            viewDomain: input.viewDomain,
            producerScanGeneration: input.scopeRevision,
            handle: input.handle,
            subscriptionKind: .fileMetadata,
            scopeRevision: input.scopeRevision,
            baseRevision: 0,
            targetRevision: input.snapshot.targetRevision,
            mode: .snapshot,
            scope: input.scope,
            coveredScope: input.scope,
            requiresCollection: nil,
            firstDeliverySequence: input.firstDeliverySequence,
            parts: parts
        )
    }
}
