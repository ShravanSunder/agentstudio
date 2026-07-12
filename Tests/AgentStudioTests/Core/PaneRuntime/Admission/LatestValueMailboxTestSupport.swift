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
