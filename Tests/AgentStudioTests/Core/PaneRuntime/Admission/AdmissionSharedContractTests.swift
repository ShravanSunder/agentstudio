import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission shared contracts")
struct AdmissionSharedContractTests {
    @Test("shared result algebra distinguishes pressure and cleanup contention")
    func sharedResultAlgebraDistinguishesPressureAndCleanupContention() {
        #expect(AdmissionReceipt.physicalCapacityExceeded == .physicalCapacityExceeded)
        #expect(AdmissionCleanupTurnResult.alreadyCleaning == .alreadyCleaning)
        #expect(AdmissionCleanupTurnResult.blockedByReplayReader == .blockedByReplayReader)
    }

    @Test("shared diagnostics account for capacity rejection and cleanup authority")
    func sharedDiagnosticsAccountForCapacityRejectionAndCleanupAuthority() {
        let admission = AdmissionDiagnostics(
            offered: 1,
            admitted: 0,
            contracted: 0,
            rejectedStale: 0,
            rejectedUndeclared: 0,
            rejectedInvalid: 0,
            rejectedCapacity: 1,
            rejectedClosed: 0,
            repairEscalations: 0,
            pendingKeyCount: 0,
            pendingKeyHighWater: 0,
            oldestPendingAge: nil
        )
        let latest = LatestValueAdmissionDiagnostics(
            admission: admission,
            semanticRetainedValueCount: 0,
            semanticRetainedValueHighWater: 0,
            pendingValueCount: 0,
            leasedValueCount: 0,
            cleanupValueCount: 0,
            cleanupValueHighWater: 0,
            physicalRetainedValueCount: 0,
            physicalRetainedValueHighWater: 0,
            oldestCleanupAge: nil,
            outstandingLeaseCount: 0,
            outstandingCleanupTurnCount: 0,
            isQuiescent: true
        )

        #expect(admission.rejectedCapacity == 1)
        #expect(latest.outstandingCleanupTurnCount == 0)
    }

    @Test("latest and journal physical limits are explicit value contracts")
    func latestAndJournalPhysicalLimitsAreExplicitValueContracts() {
        let cleanupQuantum = AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: nil)
        let latest = LatestValueLimits(
            maximumValuesPerLease: 1,
            maximumAuxiliaryRetainedValues: 2,
            cleanupQuantum: cleanupQuantum
        )
        let snapshots = OrderedFactSnapshotLimits(
            maximumSnapshotBytes: 8,
            maximumPhysicalSnapshotCount: 2,
            maximumPhysicalSnapshotBytes: 16
        )

        #expect(latest.maximumValuesPerLease == 1)
        #expect(latest.maximumAuxiliaryRetainedValues == 2)
        #expect(snapshots.maximumPhysicalSnapshotCount == 2)
    }

    @Test("protected region token vocabulary exists without public construction")
    func protectedRegionTokenVocabularyExists() {
        #expect(String(describing: AdmissionProtectedRegionToken.self).isEmpty == false)
    }

    @Test("all concrete consumer and lifecycle ports expose bounded cleanup")
    func allConcreteConsumerAndLifecyclePortsExposeBoundedCleanup() {
        requireCleanupConsumer(LatestValueConsumerPort<Int, Int>.self)
        requireCleanupConsumer(LatestValueLifecyclePort<Int, Int>.self)
        requireCleanupConsumer(GatherConsumerPort<Int, Int>.self)
        requireCleanupConsumer(GatherLifecyclePort<Int, Int>.self)
        requireCleanupConsumer(OrderedFactConsumerPort<Int, Int>.self)
        requireCleanupConsumer(OrderedFactLifecyclePort<Int, Int>.self)
    }

    private func requireCleanupConsumer<Consumer: AdmissionCleanupConsumer>(_: Consumer.Type) {}
}
