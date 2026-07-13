import Foundation

enum OrderedFactCleanupCustody<FactCustody: Sendable, SnapshotCustody: Sendable>: Sendable {
    case facts(FactCustody)
    case snapshots(NonEmptyAdmissionBatch<SnapshotCustody>)
    case factsAndSnapshots(FactCustody, NonEmptyAdmissionBatch<SnapshotCustody>)
}

func releaseOrderedFactIncomingOffer<Fact: Sendable, Snapshot: Sendable>(
    _ transition: consuming OrderedFactOfferTransition<Fact, Snapshot>
) -> OrderedFactOfferResult {
    switch consume transition {
    case .retained(let result):
        return result
    case .released(let result, let release):
        switch consume release {
        case .fact(let fact):
            withExtendedLifetime(fact) {}
        case .factAndSnapshot(let fact, let snapshotReplacement):
            withExtendedLifetime(fact) {}
            withExtendedLifetime(snapshotReplacement) {}
        }
        return result
    }
}

func releaseOrderedFactCleanupCustody<FactCustody: Sendable, SnapshotCustody: Sendable>(
    _ custody: consuming OrderedFactCleanupCustody<FactCustody, SnapshotCustody>
) {
    switch consume custody {
    case .facts(let facts):
        withExtendedLifetime(facts) {}
    case .snapshots(let snapshots):
        withExtendedLifetime(snapshots.first) {}
        for snapshot in snapshots.remaining {
            withExtendedLifetime(snapshot) {}
        }
    case .factsAndSnapshots(let facts, let snapshots):
        withExtendedLifetime(facts) {}
        withExtendedLifetime(snapshots.first) {}
        for snapshot in snapshots.remaining {
            withExtendedLifetime(snapshot) {}
        }
    }
}

func makeOrderedFactDrainResult<Fact: Sendable>(
    token: AdmissionDrainToken,
    payload: OrderedFactDrainPayload<Fact>,
    firstRetainedAt: Duration,
    now: Duration
) -> OrderedFactTakeDrainResult<Fact> {
    .drain(
        OrderedFactDrain(
            token: token,
            payload: payload,
            oldestRetainedAge: ExactAdmissionAge(
                duration: Swift.max(.zero, now - firstRetainedAt)
            )
        ))
}

struct OrderedFactHistoryLease<Fact: Sendable>: Sendable {
    fileprivate let firstNode: OrderedFactHistoryNode<Fact>
    fileprivate let lastNode: OrderedFactHistoryNode<Fact>
    fileprivate let followingNode: OrderedFactHistoryNode<Fact>?
    let factCount: Int
    let byteCount: Int

    var firstRetainedAt: Duration {
        firstNode.record.firstRetainedAt
    }

    var sequencedFacts: NonEmptyAdmissionBatch<SequencedFact<Fact>> {
        var facts: [SequencedFact<Fact>] = []
        facts.reserveCapacity(factCount)
        var currentNode: OrderedFactHistoryNode<Fact>? = firstNode
        while let node = currentNode {
            facts.append(node.record.sequencedFact)
            if node === lastNode { break }
            currentNode = node.next
        }
        guard let firstFact = facts.first else {
            preconditionFailure("Ordered fact history lease cannot be empty")
        }
        return NonEmptyAdmissionBatch(
            first: firstFact,
            remaining: Array(facts.dropFirst())
        )
    }
}

struct OrderedFactDetachedHistory<Fact: Sendable>: Sendable {
    let head: OrderedFactHistoryNode<Fact>
    let tail: OrderedFactHistoryNode<Fact>
    let factCount: Int
    let byteCount: Int
    let oldestRetainedAt: Duration
}

struct OrderedFactReplayBounds<Fact: Sendable>: Sendable {
    let firstNode: OrderedFactHistoryNode<Fact>?
    let stopNode: OrderedFactHistoryNode<Fact>?
}

struct OrderedFactHistoryOperationSnapshot: Sendable, Equatable {
    let offerNodeVisits: UInt64
    let takeNodeVisits: UInt64
    let acknowledgementNodeVisits: UInt64
    let evictionNodeVisits: UInt64
}

struct OrderedFactHistory<Fact: Sendable>: Sendable {
    private var head: OrderedFactHistoryNode<Fact>?
    private var tail: OrderedFactHistoryNode<Fact>?
    private var firstPending: OrderedFactHistoryNode<Fact>?
    private var transferredTail: OrderedFactHistoryNode<Fact>?

    private(set) var retainedFactCount = 0
    private(set) var retainedByteCount = 0
    private(set) var pendingFactCount = 0
    private(set) var pendingByteCount = 0
    private(set) var transferredFactCount = 0
    private(set) var transferredByteCount = 0

    private var offerNodeVisits: UInt64 = 0
    private var takeNodeVisits: UInt64 = 0
    private var acknowledgementNodeVisits: UInt64 = 0
    private var evictionNodeVisits: UInt64 = 0

    var firstPendingSequence: UInt64? {
        firstPending?.record.sequencedFact.sequence
    }

    var oldestPendingRetainedAt: Duration? {
        firstPending?.record.firstRetainedAt
    }

    var replayBounds: OrderedFactReplayBounds<Fact> {
        OrderedFactReplayBounds(firstNode: head, stopNode: tail)
    }

    var operationSnapshot: OrderedFactHistoryOperationSnapshot {
        OrderedFactHistoryOperationSnapshot(
            offerNodeVisits: offerNodeVisits,
            takeNodeVisits: takeNodeVisits,
            acknowledgementNodeVisits: acknowledgementNodeVisits,
            evictionNodeVisits: evictionNodeVisits
        )
    }

    func canRetain(
        additionalBytes: Int,
        maximumRetainedFacts: Int,
        maximumRetainedBytes: Int
    ) -> Bool {
        retainedFactCount < maximumRetainedFacts
            && additionalBytes <= maximumRetainedBytes - retainedByteCount
    }

    mutating func append(
        _ sequencedFact: SequencedFact<Fact>,
        estimatedBytes: Int,
        firstRetainedAt: Duration
    ) {
        let node = OrderedFactHistoryNode(
            record: OrderedFactHistoryRecord(
                sequencedFact: sequencedFact,
                estimatedBytes: estimatedBytes,
                firstRetainedAt: firstRetainedAt
            ))
        if let tail {
            tail.next = node
        } else {
            head = node
        }
        tail = node
        firstPending = firstPending ?? node
        retainedFactCount += 1
        retainedByteCount += estimatedBytes
        pendingFactCount += 1
        pendingByteCount += estimatedBytes
        incrementAdmissionCounter(&offerNodeVisits)
    }

    mutating func takeLease(
        quantum: OrderedFactDrainQuantum
    ) -> OrderedFactHistoryLease<Fact>? {
        guard let firstPending else { return nil }

        var factCount = 0
        var byteCount = 0
        var lastNode = firstPending
        var currentNode: OrderedFactHistoryNode<Fact>? = firstPending
        while let node = currentNode, factCount < quantum.maximumFacts {
            factCount += 1
            byteCount += node.record.estimatedBytes
            lastNode = node
            incrementAdmissionCounter(&takeNodeVisits)
            currentNode = node.next
        }
        return OrderedFactHistoryLease(
            firstNode: firstPending,
            lastNode: lastNode,
            followingNode: currentNode,
            factCount: factCount,
            byteCount: byteCount
        )
    }

    mutating func acknowledgeTransferredLease(
        _ lease: OrderedFactHistoryLease<Fact>
    ) -> Bool {
        guard firstPending === lease.firstNode else { return false }
        firstPending = lease.followingNode
        transferredTail = lease.lastNode
        pendingFactCount -= lease.factCount
        pendingByteCount -= lease.byteCount
        transferredFactCount += lease.factCount
        transferredByteCount += lease.byteCount
        incrementAdmissionCounter(
            &acknowledgementNodeVisits,
            by: UInt64(lease.factCount)
        )
        return true
    }

    mutating func detachTransferredPrefix() -> (
        history: OrderedFactDetachedHistory<Fact>,
        unavailableThrough: UInt64
    )? {
        guard transferredFactCount > 0,
            let detachedHead = head,
            let detachedTail = transferredTail
        else { return nil }

        let nextHead = detachedTail.next
        detachedTail.next = nil
        head = nextHead
        if nextHead == nil { tail = nil }

        let detached = OrderedFactDetachedHistory(
            head: detachedHead,
            tail: detachedTail,
            factCount: transferredFactCount,
            byteCount: transferredByteCount,
            oldestRetainedAt: detachedHead.record.firstRetainedAt
        )
        retainedFactCount -= transferredFactCount
        retainedByteCount -= transferredByteCount
        transferredFactCount = 0
        transferredByteCount = 0
        transferredTail = nil
        incrementAdmissionCounter(&evictionNodeVisits)
        return (detached, detachedTail.record.sequencedFact.sequence)
    }

    mutating func detachAll() -> OrderedFactDetachedHistory<Fact>? {
        guard let detachedHead = head, let detachedTail = tail else { return nil }
        let detached = OrderedFactDetachedHistory(
            head: detachedHead,
            tail: detachedTail,
            factCount: retainedFactCount,
            byteCount: retainedByteCount,
            oldestRetainedAt: detachedHead.record.firstRetainedAt
        )
        head = nil
        tail = nil
        firstPending = nil
        transferredTail = nil
        retainedFactCount = 0
        retainedByteCount = 0
        pendingFactCount = 0
        pendingByteCount = 0
        transferredFactCount = 0
        transferredByteCount = 0
        return detached
    }
}

struct OrderedFactHistoryRecord<Fact: Sendable>: Sendable {
    let sequencedFact: SequencedFact<Fact>
    let estimatedBytes: Int
    let firstRetainedAt: Duration
}

final class OrderedFactHistoryNode<Fact: Sendable>: @unchecked Sendable {
    let record: OrderedFactHistoryRecord<Fact>
    var next: OrderedFactHistoryNode?

    init(record: OrderedFactHistoryRecord<Fact>) {
        self.record = record
    }
}
