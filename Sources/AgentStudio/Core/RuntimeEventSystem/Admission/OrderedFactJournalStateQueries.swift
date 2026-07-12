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

struct OrderedFactCleanupRelease: Sendable {
    let factCount: Int
    let factBytes: Int
    let snapshotCount: Int
    let snapshotBytes: Int
    let entryCount: Int
    let byteCount: Int
}

enum OrderedFactOfferPreflight: Sendable {
    case admit
    case staleGeneration
    case closed
    case invalidSize
    case snapshotTooLarge
    case snapshotPhysicalCapacityExceeded
}

func classifyOrderedFactOffer(
    lifecycle: (hasCurrentGeneration: Bool, isOpen: Bool),
    estimatedFactBytes: Int,
    estimatedSnapshotBytes: Int?,
    snapshotLimits: OrderedFactSnapshotLimits,
    snapshotPressure: (count: Int, bytes: Int)
) -> OrderedFactOfferPreflight {
    guard lifecycle.hasCurrentGeneration else { return .staleGeneration }
    guard lifecycle.isOpen else { return .closed }
    guard estimatedFactBytes >= 0, estimatedSnapshotBytes ?? 0 >= 0 else {
        return .invalidSize
    }
    guard let estimatedSnapshotBytes else { return .admit }
    guard estimatedSnapshotBytes <= snapshotLimits.maximumSnapshotBytes else {
        return .snapshotTooLarge
    }
    guard
        orderedFactSnapshotCapacityAllows(
            limits: snapshotLimits,
            currentCount: snapshotPressure.count,
            currentBytes: snapshotPressure.bytes,
            additionalBytes: estimatedSnapshotBytes
        )
    else { return .snapshotPhysicalCapacityExceeded }
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
    initialSnapshot: Snapshot?,
    initialSnapshotBytes: Int
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
    guard cleanupQuantum.isValid,
        let maximumCleanupBytes = cleanupQuantum.maximumBytes,
        maximumCleanupBytes >= Swift.max(maximumRetainedBytes, snapshotLimits.maximumSnapshotBytes)
    else {
        throw OrderedFactJournalConfigurationError.invalidCleanupQuantum
    }
    if initialSnapshot != nil, initialSnapshotBytes < 0 {
        throw OrderedFactJournalConfigurationError.initialSnapshotInvalidSize
    }
    if initialSnapshot != nil,
        initialSnapshotBytes > snapshotLimits.maximumSnapshotBytes
            || snapshotLimits.maximumPhysicalSnapshotCount < 1
            || initialSnapshotBytes > snapshotLimits.maximumPhysicalSnapshotBytes
    {
        throw OrderedFactJournalConfigurationError.initialSnapshotTooLarge
    }
}
