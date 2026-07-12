@testable import AgentStudio

func makeLatestValueTestLimits(
    cleanupQuantum: AdmissionCleanupQuantum,
    maximumValuesPerLease: Int = 512
) -> LatestValueLimits {
    LatestValueLimits(
        maximumValuesPerLease: maximumValuesPerLease,
        maximumAuxiliaryRetainedValues: maximumValuesPerLease * 2,
        cleanupQuantum: cleanupQuantum
    )
}

func latestValuesByKey<Key, Value>(
    _ drain: LatestValueDrain<Key, Value>
) -> [Key: Value] where Key: Hashable & Sendable, Value: Sendable {
    var valuesByKey: [Key: Value] = [:]
    drain.values.forEach { entry in
        valuesByKey[entry.key] = entry.value
    }
    return valuesByKey
}
