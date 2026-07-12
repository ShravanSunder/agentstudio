import Foundation

enum BridgeProductSubscriptionStateError: Error, Equatable {
    case barrierIntentCapacityExceeded
    case committedUpdateIdCapacityExceeded
    case duplicateSubscriptionId
    case unknownSubscriptionId
    case subscriptionCapacityExceeded
    case subscriptionKindMismatch
    case workerDerivationEpochMismatch
    case interestBaseMismatch
    case updateAlreadyStaged
    case committedUpdateIdReused
    case batchMetadataMismatch
    case batchSequenceGap(expectedBatchIndex: Int, receivedBatchIndex: Int)
    case duplicateDeltaMember
    case deltaItemCountMismatch
    case interestTargetHashMismatch
    case interestRevisionExhausted
}

struct BridgeProductSubscriptionOpenReceipt: Equatable, Sendable {
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int
    let interestRevision: Int
    let interestSha256: String
}

struct BridgeProductSubscriptionCommitBarrierIntent: Equatable, Sendable {
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int
    let interestRevision: Int
    let interestSha256: String
    let updateId: String
}

enum BridgeProductSubscriptionBatchResult: Equatable, Sendable {
    case staged
    case committed(BridgeProductSubscriptionCommitBarrierIntent)
}

struct BridgeProductSubscriptionSnapshot: Equatable, Sendable {
    let subscription: BridgeProductSubscriptionRequest
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int
    let interestRevision: Int
    let interestSha256: String
    let interestState: BridgeProductSubscriptionInterestState
    let hasStagedUpdate: Bool
}

struct BridgeProductSubscriptionResetIntent: Equatable, Sendable {
    let subscription: BridgeProductSubscriptionRequest
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int
    let interestRevision: Int
    let interestSha256: String
}

struct BridgeProductSubscriptionResyncResult: Equatable, Sendable {
    let reconciliation: [BridgeProductResyncReconciliationOutcome]
    let revokedNativeOnlySubscriptionIds: [String]
    let resetIntents: [BridgeProductSubscriptionResetIntent]

    static let empty = Self(
        reconciliation: [],
        revokedNativeOnlySubscriptionIds: [],
        resetIntents: []
    )
}

struct BridgeProductSubscriptionState: Sendable {
    private typealias ExactUTF8Identity = BridgeProductSubscriptionExactUTF8Identity
    private typealias DeltaMemberIdentity = BridgeProductSubscriptionDeltaMemberIdentity

    private struct StagedUpdateMetadata: Equatable, Sendable {
        let updateId: String
        let batchCount: Int
        let totalDeltaItemCount: Int
        let baseInterestRevision: Int
        let baseInterestSha256: String
        let targetInterestRevision: Int
        let targetInterestSha256: String
        let subscriptionKind: BridgeProductSubscriptionKind
        let workerDerivationEpoch: Int

        init(_ request: BridgeProductSubscriptionUpdateBatchRequest) {
            self.updateId = request.updateId
            self.batchCount = request.batchCount
            self.totalDeltaItemCount = request.totalDeltaItemCount
            self.baseInterestRevision = request.baseInterestRevision
            self.baseInterestSha256 = request.baseInterestSha256
            self.targetInterestRevision = request.targetInterestRevision
            self.targetInterestSha256 = request.targetInterestSha256
            self.subscriptionKind = request.subscriptionKind
            self.workerDerivationEpoch = request.workerDerivationEpoch
        }
    }

    private struct StagedUpdate: Sendable {
        let metadata: StagedUpdateMetadata
        var deltas: [BridgeProductSubscriptionInterestDelta]
        var memberIdentities: Set<DeltaMemberIdentity>
        var itemCount: Int

        var nextBatchIndex: Int { deltas.count }
    }

    private struct SubscriptionRecord: Sendable {
        let subscription: BridgeProductSubscriptionRequest
        let subscriptionId: String
        let subscriptionKind: BridgeProductSubscriptionKind
        let workerDerivationEpoch: Int
        var interestRevision: Int
        var interestSha256: String
        var interestState: BridgeProductSubscriptionInterestState
        var stagedUpdate: StagedUpdate?
        var committedUpdateIds: Set<ExactUTF8Identity>
    }

    private struct ActiveSubscriptionReconciliation {
        let candidateRecord: SubscriptionRecord?
        let outcome: BridgeProductResyncReconciliationOutcome
        let resetIntent: BridgeProductSubscriptionResetIntent?
    }

    private static let defaultMaximumCommittedUpdateIdCount = 1024
    private static let defaultMaximumPendingBarrierIntentCount =
        BridgeProductWireContract.maximumQueuedStreamFrames
        - BridgeProductWireContract.terminalFrameReserve

    private let maximumSubscriptionCount: Int
    private let maximumCommittedUpdateIdCount: Int
    private let maximumPendingBarrierIntentCount: Int
    private var recordsBySubscriptionId: [ExactUTF8Identity: SubscriptionRecord] = [:]
    private var barrierIntents: [BridgeProductSubscriptionCommitBarrierIntent] = []

    init(
        maximumSubscriptionCount: Int = BridgeProductWireContract.maximumActiveSubscriptionCount,
        maximumCommittedUpdateIdCount: Int = Self.defaultMaximumCommittedUpdateIdCount,
        maximumPendingBarrierIntentCount: Int = Self.defaultMaximumPendingBarrierIntentCount
    ) {
        precondition(maximumSubscriptionCount > 0)
        precondition(maximumCommittedUpdateIdCount > 0)
        precondition(maximumPendingBarrierIntentCount > 0)
        self.maximumSubscriptionCount = maximumSubscriptionCount
        self.maximumCommittedUpdateIdCount = maximumCommittedUpdateIdCount
        self.maximumPendingBarrierIntentCount = maximumPendingBarrierIntentCount
    }

    var subscriptionCount: Int { recordsBySubscriptionId.count }
    var pendingBarrierIntentCount: Int { barrierIntents.count }

    mutating func open(
        _ request: BridgeProductSubscriptionOpenRequest
    ) throws -> BridgeProductSubscriptionOpenReceipt {
        let subscriptionIdentity = ExactUTF8Identity(request.subscriptionId)
        guard recordsBySubscriptionId[subscriptionIdentity] == nil else {
            throw BridgeProductSubscriptionStateError.duplicateSubscriptionId
        }
        guard recordsBySubscriptionId.count < maximumSubscriptionCount else {
            throw BridgeProductSubscriptionStateError.subscriptionCapacityExceeded
        }

        let interestState = Self.emptyInterestState(for: request.subscription.subscriptionKind)
        let interestSha256 = try interestState.sha256Hex()
        let record = SubscriptionRecord(
            subscription: request.subscription,
            subscriptionId: request.subscriptionId,
            subscriptionKind: request.subscription.subscriptionKind,
            workerDerivationEpoch: request.workerDerivationEpoch,
            interestRevision: 0,
            interestSha256: interestSha256,
            interestState: interestState,
            stagedUpdate: nil,
            committedUpdateIds: []
        )
        recordsBySubscriptionId[subscriptionIdentity] = record
        return BridgeProductSubscriptionOpenReceipt(
            subscriptionId: record.subscriptionId,
            subscriptionKind: record.subscriptionKind,
            workerDerivationEpoch: record.workerDerivationEpoch,
            interestRevision: record.interestRevision,
            interestSha256: record.interestSha256
        )
    }

    mutating func apply(
        _ request: BridgeProductSubscriptionUpdateBatchRequest
    ) throws -> BridgeProductSubscriptionBatchResult {
        let subscriptionIdentity = ExactUTF8Identity(request.subscriptionId)
        guard var record = recordsBySubscriptionId[subscriptionIdentity] else {
            throw BridgeProductSubscriptionStateError.unknownSubscriptionId
        }
        guard record.subscriptionKind == request.subscriptionKind else {
            throw BridgeProductSubscriptionStateError.subscriptionKindMismatch
        }
        guard record.workerDerivationEpoch == request.workerDerivationEpoch else {
            throw BridgeProductSubscriptionStateError.workerDerivationEpochMismatch
        }
        guard record.interestRevision == request.baseInterestRevision,
            record.interestSha256 == request.baseInterestSha256
        else {
            throw BridgeProductSubscriptionStateError.interestBaseMismatch
        }

        let updateIdentity = ExactUTF8Identity(request.updateId)
        guard !record.committedUpdateIds.contains(updateIdentity) else {
            throw BridgeProductSubscriptionStateError.committedUpdateIdReused
        }

        let requestMetadata = StagedUpdateMetadata(request)
        var stagedUpdate: StagedUpdate
        if let existingUpdate = record.stagedUpdate {
            guard existingUpdate.metadata.updateId == request.updateId else {
                throw BridgeProductSubscriptionStateError.updateAlreadyStaged
            }
            guard existingUpdate.metadata == requestMetadata else {
                throw BridgeProductSubscriptionStateError.batchMetadataMismatch
            }
            stagedUpdate = existingUpdate
        } else {
            stagedUpdate = StagedUpdate(
                metadata: requestMetadata,
                deltas: [],
                memberIdentities: [],
                itemCount: 0
            )
        }

        guard request.batchIndex == stagedUpdate.nextBatchIndex else {
            throw BridgeProductSubscriptionStateError.batchSequenceGap(
                expectedBatchIndex: stagedUpdate.nextBatchIndex,
                receivedBatchIndex: request.batchIndex
            )
        }

        let batchMemberIdentities = BridgeProductSubscriptionInterestMutation.memberIdentities(
            in: request.delta
        )
        guard stagedUpdate.memberIdentities.isDisjoint(with: batchMemberIdentities) else {
            throw BridgeProductSubscriptionStateError.duplicateDeltaMember
        }
        let nextItemCount = stagedUpdate.itemCount + request.delta.itemCount
        let remainingBatchCount = request.batchCount - request.batchIndex - 1
        guard nextItemCount <= request.totalDeltaItemCount,
            nextItemCount + remainingBatchCount <= request.totalDeltaItemCount
        else {
            throw BridgeProductSubscriptionStateError.deltaItemCountMismatch
        }

        stagedUpdate.deltas.append(request.delta)
        stagedUpdate.memberIdentities.formUnion(batchMemberIdentities)
        stagedUpdate.itemCount = nextItemCount

        guard stagedUpdate.nextBatchIndex == request.batchCount else {
            record.stagedUpdate = stagedUpdate
            recordsBySubscriptionId[subscriptionIdentity] = record
            return .staged
        }
        guard stagedUpdate.itemCount == request.totalDeltaItemCount else {
            throw BridgeProductSubscriptionStateError.deltaItemCountMismatch
        }
        guard record.committedUpdateIds.count < maximumCommittedUpdateIdCount else {
            throw BridgeProductSubscriptionStateError.committedUpdateIdCapacityExceeded
        }
        guard barrierIntents.count < maximumPendingBarrierIntentCount else {
            throw BridgeProductSubscriptionStateError.barrierIntentCapacityExceeded
        }

        let candidateState = try BridgeProductSubscriptionInterestMutation.apply(
            stagedUpdate.deltas,
            to: record.interestState,
            subscriptionKind: record.subscriptionKind
        )
        let candidateSHA256 = try candidateState.sha256Hex()
        guard candidateSHA256 == request.targetInterestSha256 else {
            throw BridgeProductSubscriptionStateError.interestTargetHashMismatch
        }

        let barrierIntent = BridgeProductSubscriptionCommitBarrierIntent(
            subscriptionId: record.subscriptionId,
            subscriptionKind: record.subscriptionKind,
            workerDerivationEpoch: record.workerDerivationEpoch,
            interestRevision: request.targetInterestRevision,
            interestSha256: candidateSHA256,
            updateId: request.updateId
        )
        record.interestRevision = request.targetInterestRevision
        record.interestSha256 = candidateSHA256
        record.interestState = candidateState
        record.stagedUpdate = nil
        record.committedUpdateIds.insert(updateIdentity)
        recordsBySubscriptionId[subscriptionIdentity] = record
        barrierIntents.append(barrierIntent)
        return .committed(barrierIntent)
    }

    func snapshot(subscriptionId: String) -> BridgeProductSubscriptionSnapshot? {
        guard let record = recordsBySubscriptionId[ExactUTF8Identity(subscriptionId)] else {
            return nil
        }
        return BridgeProductSubscriptionSnapshot(
            subscription: record.subscription,
            subscriptionId: record.subscriptionId,
            subscriptionKind: record.subscriptionKind,
            workerDerivationEpoch: record.workerDerivationEpoch,
            interestRevision: record.interestRevision,
            interestSha256: record.interestSha256,
            interestState: record.interestState,
            hasStagedUpdate: record.stagedUpdate != nil
        )
    }

    mutating func cancel(
        _ request: BridgeProductSubscriptionCancelRequest
    ) throws -> BridgeProductSubscriptionSnapshot {
        let subscriptionIdentity = ExactUTF8Identity(request.subscriptionId)
        guard let record = recordsBySubscriptionId[subscriptionIdentity] else {
            throw BridgeProductSubscriptionStateError.unknownSubscriptionId
        }
        guard record.subscriptionKind == request.subscriptionKind else {
            throw BridgeProductSubscriptionStateError.subscriptionKindMismatch
        }
        guard record.workerDerivationEpoch == request.workerDerivationEpoch else {
            throw BridgeProductSubscriptionStateError.workerDerivationEpochMismatch
        }

        recordsBySubscriptionId.removeValue(forKey: subscriptionIdentity)
        barrierIntents.removeAll {
            ExactUTF8Identity($0.subscriptionId) == subscriptionIdentity
        }
        return Self.snapshot(record)
    }

    mutating func reconcile(
        activeSubscriptions: [BridgeProductActiveSubscription]
    ) throws -> BridgeProductSubscriptionResyncResult {
        let activeIdentities = activeSubscriptions.map {
            ExactUTF8Identity($0.subscriptionId)
        }
        guard Set(activeIdentities).count == activeIdentities.count else {
            throw BridgeProductSubscriptionStateError.duplicateSubscriptionId
        }
        guard activeSubscriptions.count <= maximumSubscriptionCount else {
            throw BridgeProductSubscriptionStateError.subscriptionCapacityExceeded
        }
        let activeByIdentity = Dictionary(
            uniqueKeysWithValues: activeSubscriptions.map {
                (ExactUTF8Identity($0.subscriptionId), $0)
            }
        )
        var candidateRecords = recordsBySubscriptionId
        let revokedNativeOnlySubscriptionIds = recordsBySubscriptionId.values.compactMap { record in
            activeByIdentity[ExactUTF8Identity(record.subscriptionId)] == nil
                ? record.subscriptionId
                : nil
        }
        for subscriptionId in revokedNativeOnlySubscriptionIds {
            candidateRecords.removeValue(forKey: ExactUTF8Identity(subscriptionId))
        }
        var reconciliation: [BridgeProductResyncReconciliationOutcome] = []
        var resetIntents: [BridgeProductSubscriptionResetIntent] = []

        for activeSubscription in activeSubscriptions {
            let identity = ExactUTF8Identity(activeSubscription.subscriptionId)
            let step = try Self.reconcile(
                activeSubscription: activeSubscription,
                record: recordsBySubscriptionId[identity]
            )
            candidateRecords[identity] = step.candidateRecord
            reconciliation.append(step.outcome)
            if let resetIntent = step.resetIntent {
                resetIntents.append(resetIntent)
            }
        }

        let retainedIdentities = Set(candidateRecords.keys)
        let resetIdentities = Set(resetIntents.map { ExactUTF8Identity($0.subscriptionId) })
        barrierIntents.removeAll { intent in
            let intentIdentity = ExactUTF8Identity(intent.subscriptionId)
            return !retainedIdentities.contains(intentIdentity)
                || resetIdentities.contains(intentIdentity)
        }
        recordsBySubscriptionId = candidateRecords
        return BridgeProductSubscriptionResyncResult(
            reconciliation: reconciliation,
            revokedNativeOnlySubscriptionIds: Self.sortedByExactUTF8(
                revokedNativeOnlySubscriptionIds
            ),
            resetIntents: resetIntents.sorted {
                Data($0.subscriptionId.utf8).lexicographicallyPrecedes(
                    Data($1.subscriptionId.utf8)
                )
            }
        )
    }

    private static func reconcile(
        activeSubscription: BridgeProductActiveSubscription,
        record: SubscriptionRecord?
    ) throws -> ActiveSubscriptionReconciliation {
        guard let record else {
            return ActiveSubscriptionReconciliation(
                candidateRecord: nil,
                outcome: .reopenRequired(
                    try .init(
                        subscriptionId: activeSubscription.subscriptionId,
                        subscriptionKind: activeSubscription.subscriptionKind,
                        requiredWorkerDerivationEpoch: activeSubscription.workerDerivationEpoch,
                        reason: .nativeMissing
                    )),
                resetIntent: nil
            )
        }
        guard record.subscriptionKind == activeSubscription.subscriptionKind,
            record.workerDerivationEpoch == activeSubscription.workerDerivationEpoch
        else {
            return ActiveSubscriptionReconciliation(
                candidateRecord: nil,
                outcome: .reopenRequired(
                    try .init(
                        subscriptionId: activeSubscription.subscriptionId,
                        subscriptionKind: activeSubscription.subscriptionKind,
                        requiredWorkerDerivationEpoch: activeSubscription.workerDerivationEpoch,
                        reason: record.subscriptionKind == activeSubscription.subscriptionKind
                            ? .epochAdvanced
                            : .identityMismatch
                    )),
                resetIntent: nil
            )
        }

        var candidateRecord = record
        candidateRecord.stagedUpdate = nil
        if record.interestRevision == activeSubscription.interestRevision,
            record.interestSha256 == activeSubscription.interestSha256
        {
            return ActiveSubscriptionReconciliation(
                candidateRecord: candidateRecord,
                outcome: .retained(
                    try .init(
                        subscriptionId: record.subscriptionId,
                        subscriptionKind: record.subscriptionKind,
                        workerDerivationEpoch: record.workerDerivationEpoch,
                        interestRevision: record.interestRevision,
                        interestSha256: record.interestSha256
                    )),
                resetIntent: nil
            )
        }

        let greatestInterestRevision = max(
            record.interestRevision,
            activeSubscription.interestRevision
        )
        guard greatestInterestRevision < BridgeProductWireContract.maximumSafeInteger else {
            throw BridgeProductSubscriptionStateError.interestRevisionExhausted
        }
        let emptyInterestState = Self.emptyInterestState(for: record.subscriptionKind)
        let emptyInterestSHA256 = try emptyInterestState.sha256Hex()
        candidateRecord.interestRevision = greatestInterestRevision + 1
        candidateRecord.interestSha256 = emptyInterestSHA256
        candidateRecord.interestState = emptyInterestState
        candidateRecord.committedUpdateIds.removeAll(keepingCapacity: false)
        return ActiveSubscriptionReconciliation(
            candidateRecord: candidateRecord,
            outcome: .reset(
                try .init(
                    subscriptionId: record.subscriptionId,
                    subscriptionKind: record.subscriptionKind,
                    workerDerivationEpoch: record.workerDerivationEpoch,
                    interestRevision: candidateRecord.interestRevision,
                    interestSha256: emptyInterestSHA256,
                    reason: .interestMismatch
                )),
            resetIntent: BridgeProductSubscriptionResetIntent(
                subscription: record.subscription,
                subscriptionId: record.subscriptionId,
                subscriptionKind: record.subscriptionKind,
                workerDerivationEpoch: record.workerDerivationEpoch,
                interestRevision: candidateRecord.interestRevision,
                interestSha256: emptyInterestSHA256
            )
        )
    }

    mutating func drainCommitBarrierIntents() -> [BridgeProductSubscriptionCommitBarrierIntent] {
        let drainedIntents = barrierIntents
        barrierIntents.removeAll(keepingCapacity: true)
        return drainedIntents
    }

    mutating func reset(surface: BridgeProductSurface) {
        recordsBySubscriptionId = recordsBySubscriptionId.filter { _, record in
            record.subscriptionKind.surface != surface
        }
        barrierIntents.removeAll { intent in
            intent.subscriptionKind.surface == surface
        }
    }

    mutating func revokeWorker() {
        recordsBySubscriptionId.removeAll(keepingCapacity: false)
        barrierIntents.removeAll(keepingCapacity: false)
    }

    static func emptyInterestState(
        for subscriptionKind: BridgeProductSubscriptionKind
    ) -> BridgeProductSubscriptionInterestState {
        switch subscriptionKind {
        case .fileMetadata:
            .fileMetadata(interests: [], pathScope: [])
        case .reviewMetadata:
            .reviewMetadata(interests: [])
        }
    }

    private static func snapshot(
        _ record: SubscriptionRecord
    ) -> BridgeProductSubscriptionSnapshot {
        BridgeProductSubscriptionSnapshot(
            subscription: record.subscription,
            subscriptionId: record.subscriptionId,
            subscriptionKind: record.subscriptionKind,
            workerDerivationEpoch: record.workerDerivationEpoch,
            interestRevision: record.interestRevision,
            interestSha256: record.interestSha256,
            interestState: record.interestState,
            hasStagedUpdate: record.stagedUpdate != nil
        )
    }

    private static func sortedByExactUTF8(_ values: [String]) -> [String] {
        values.sorted {
            Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8))
        }
    }

}
