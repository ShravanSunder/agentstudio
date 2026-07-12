func minimumAdmissionTimestamp<T: Comparable>(_ first: T?, _ second: T?) -> T? {
    switch (first, second) {
    case (.some(let first), .some(let second)):
        Swift.min(first, second)
    case (.some(let first), .none):
        first
    case (.none, .some(let second)):
        second
    case (.none, .none):
        nil
    }
}

func orderedFactDiagnosticCurrentness(
    _ lifecycle: OrderedFactJournalLifecycle,
    _ productGap: OrderedFactProductGapState
) -> OrderedFactJournalDiagnosticCurrentness {
    switch (lifecycle, productGap) {
    case (.invalidated, _): .invalidated
    case (_, .noGap): .current
    case (_, .pendingTransfer(let gap, _)), (_, .transferred(let gap, _)): .nonCurrent(gap)
    }
}

func makeOrderedFactJournalDrain<Fact: Sendable>(
    token: AdmissionDrainToken,
    payload: OrderedFactDrainLeasePayload<Fact>,
    now: Duration
) -> OrderedFactTakeDrainResult<Fact> {
    let content: (payload: OrderedFactDrainPayload<Fact>, firstRetainedAt: Duration) =
        switch payload {
        case .facts(let historyLease):
            (.facts(historyLease.sequencedFacts), historyLease.firstRetainedAt)
        case .gap(let gap, let firstRetainedAt):
            (.gap(gap), firstRetainedAt)
        }
    return makeOrderedFactDrainResult(
        token: token,
        payload: content.payload,
        firstRetainedAt: content.firstRetainedAt,
        now: now
    )
}

struct OrderedFactCleanupRelease: Sendable {
    let factCount: Int
    let factBytes: Int
    let snapshotCount: Int
    let snapshotBytes: Int
    let entryCount: Int
    let byteCount: Int
}

func orderedFactCleanupLimits(
    _ quantum: AdmissionCleanupQuantum
) -> (maximumEntries: Int, maximumBytes: Int) {
    guard case .entriesAndBytes(let maximumEntries, let maximumBytes) = quantum else {
        preconditionFailure("Ordered fact cleanup requires an entry-and-byte quantum")
    }
    return (maximumEntries, maximumBytes)
}

enum OrderedFactOfferRejection: Sendable {
    case staleGeneration
    case closed
    case invalidSize
    case snapshotTooLarge
    case snapshotPhysicalCapacityExceeded
}

enum OrderedFactOfferPreflight: Sendable {
    case admit
    case reject(OrderedFactOfferRejection)
}

func applyOrderedFactOfferRejection(
    _ rejection: OrderedFactOfferRejection,
    offered: inout UInt64,
    rejectedStale: inout UInt64,
    rejectedClosed: inout UInt64,
    rejectedInvalid: inout UInt64,
    rejectedCapacity: inout UInt64
) -> OrderedFactOfferResult {
    incrementAdmissionCounter(&offered)
    switch rejection {
    case .staleGeneration:
        incrementAdmissionCounter(&rejectedStale)
        return .staleGeneration
    case .closed:
        incrementAdmissionCounter(&rejectedClosed)
        return .closed
    case .invalidSize:
        incrementAdmissionCounter(&rejectedInvalid)
        return .invalidSize
    case .snapshotTooLarge:
        incrementAdmissionCounter(&rejectedInvalid)
        return .snapshotTooLarge
    case .snapshotPhysicalCapacityExceeded:
        incrementAdmissionCounter(&rejectedCapacity)
        return .snapshotPhysicalCapacityExceeded
    }
}

func classifyOrderedFactOffer(
    lifecycle: (hasCurrentGeneration: Bool, isOpen: Bool),
    estimatedFactBytes: Int,
    estimatedSnapshotBytes: Int?,
    snapshotLimits: OrderedFactSnapshotLimits,
    snapshotPressure: (count: Int, bytes: Int)
) -> OrderedFactOfferPreflight {
    guard lifecycle.hasCurrentGeneration else { return .reject(.staleGeneration) }
    guard lifecycle.isOpen else { return .reject(.closed) }
    guard estimatedFactBytes >= 0, estimatedSnapshotBytes ?? 0 >= 0 else {
        return .reject(.invalidSize)
    }
    guard let estimatedSnapshotBytes else { return .admit }
    guard estimatedSnapshotBytes <= snapshotLimits.maximumSnapshotBytes else {
        return .reject(.snapshotTooLarge)
    }
    guard
        orderedFactSnapshotCapacityAllows(
            limits: snapshotLimits,
            currentCount: snapshotPressure.count,
            currentBytes: snapshotPressure.bytes,
            additionalBytes: estimatedSnapshotBytes
        )
    else { return .reject(.snapshotPhysicalCapacityExceeded) }
    return .admit
}

func normalizedOrderedFactSnapshotLimits(
    _ limits: OrderedFactSnapshotLimits
) -> OrderedFactSnapshotLimits {
    OrderedFactSnapshotLimits(
        maximumSnapshotBytes: Swift.max(0, limits.maximumSnapshotBytes),
        maximumPhysicalSnapshotCount: Swift.max(0, limits.maximumPhysicalSnapshotCount),
        maximumPhysicalSnapshotBytes: Swift.max(0, limits.maximumPhysicalSnapshotBytes)
    )
}

func orderedFactSnapshotCapacityAllows(
    limits: OrderedFactSnapshotLimits,
    currentCount: Int,
    currentBytes: Int,
    additionalBytes: Int
) -> Bool {
    let nextCount = currentCount.addingReportingOverflow(1)
    guard nextCount.overflow == false,
        nextCount.partialValue <= limits.maximumPhysicalSnapshotCount,
        currentBytes <= limits.maximumPhysicalSnapshotBytes
    else { return false }
    return additionalBytes <= limits.maximumPhysicalSnapshotBytes - currentBytes
}

func validateOrderedFactJournalConfiguration<Snapshot>(
    cleanupQuantum: AdmissionCleanupQuantum,
    maximumRetainedBytes: Int,
    snapshotLimits: OrderedFactSnapshotLimits,
    initialSnapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?
) throws {
    let replacementOverlapBytes = snapshotLimits.maximumSnapshotBytes.multipliedReportingOverflow(
        by: 2
    )
    guard replacementOverlapBytes.overflow == false,
        snapshotLimits.maximumPhysicalSnapshotCount >= 2,
        snapshotLimits.maximumPhysicalSnapshotBytes >= replacementOverlapBytes.partialValue
    else {
        throw OrderedFactJournalConfigurationError.invalidSnapshotLimits
    }
    guard cleanupQuantum.isValid else {
        throw OrderedFactJournalConfigurationError.invalidCleanupQuantum
    }
    guard case .entriesAndBytes(_, let maximumCleanupBytes) = cleanupQuantum,
        maximumCleanupBytes >= Swift.max(maximumRetainedBytes, snapshotLimits.maximumSnapshotBytes)
    else {
        throw OrderedFactJournalConfigurationError.invalidCleanupQuantum
    }
    if let initialSnapshotReplacement, initialSnapshotReplacement.estimatedBytes < 0 {
        throw OrderedFactJournalConfigurationError.initialSnapshotInvalidSize
    }
    if let initialSnapshotReplacement,
        initialSnapshotReplacement.estimatedBytes > snapshotLimits.maximumSnapshotBytes
            || snapshotLimits.maximumPhysicalSnapshotCount < 1
            || initialSnapshotReplacement.estimatedBytes > snapshotLimits.maximumPhysicalSnapshotBytes
    {
        throw OrderedFactJournalConfigurationError.initialSnapshotTooLarge
    }
}
