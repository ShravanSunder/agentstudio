struct OrderedFactReplayHistoryCapture<Fact: Sendable, Snapshot: Sendable>: Sendable {
    let bounds: OrderedFactReplayBounds<Fact>
    let afterSequence: UInt64
    let latestSequence: UInt64
    let historyUnavailableThrough: UInt64
    let snapshot: SequencedSnapshot<Snapshot>?
    let recovery: OrderedFactReplayRecovery
}

enum OrderedFactReplayCapture<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case immediate(OrderedFactImmediateReplayResult)
    case registered(
        readerIdentity: AdmissionOpaqueIdentity,
        history: OrderedFactReplayHistoryCapture<Fact, Snapshot>
    )
}

func materializeOrderedFactRegisteredReplay<Fact: Sendable, Snapshot: Sendable>(
    _ capture: OrderedFactReplayHistoryCapture<Fact, Snapshot>,
    generation: AdmissionGeneration
) -> OrderedFactRegisteredReplayResult<Fact, Snapshot> {
    let followingFacts = materializeOrderedFactReplayFacts(
        bounds: capture.bounds,
        after: capture.afterSequence
    )
    guard capture.historyUnavailableThrough > 0,
        capture.afterSequence <= capture.historyUnavailableThrough
    else {
        return .facts(followingFacts, nextSequence: capture.latestSequence)
    }

    let nextSequence = capture.afterSequence.addingReportingOverflow(1)
    let missingLowerBound =
        nextSequence.overflow
        ? capture.historyUnavailableThrough
        : Swift.min(nextSequence.partialValue, capture.historyUnavailableThrough)
    let missing = missingLowerBound...capture.historyUnavailableThrough
    if capture.recovery == .currentSnapshot,
        let snapshot = capture.snapshot,
        snapshot.throughSequence >= missing.upperBound
    {
        return .snapshot(
            snapshot,
            followingFacts: followingFacts.filter {
                $0.sequence > snapshot.throughSequence
            },
            nextSequence: capture.latestSequence
        )
    }
    return .historyGap(
        ReplayHistoryGap(
            generation: generation,
            missingSequences: missing,
            availableFacts: followingFacts,
            nextSequence: capture.latestSequence
        ))
}

private func materializeOrderedFactReplayFacts<Fact: Sendable>(
    bounds: OrderedFactReplayBounds<Fact>,
    after sequence: UInt64
) -> [SequencedFact<Fact>] {
    guard let stopNode = bounds.stopNode else { return [] }
    var facts: [SequencedFact<Fact>] = []
    var currentNode = bounds.firstNode
    while let node = currentNode {
        if node.record.sequencedFact.sequence > sequence {
            facts.append(node.record.sequencedFact)
        }
        if node === stopNode { break }
        currentNode = node.next
    }
    return facts
}
