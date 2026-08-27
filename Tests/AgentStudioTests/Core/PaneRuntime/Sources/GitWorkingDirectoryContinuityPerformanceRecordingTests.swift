import Testing

@testable import AgentStudioCore

@Suite("Git working-directory continuity performance recording")
struct GitContinuityPerformanceRecordingTests {
    @Test("bounded continuity outcomes and gauges survive one aggregate interval")
    func boundedContinuityOutcomesAndGaugesSurviveOneAggregateInterval() {
        var accumulator = GitWorkingDirectoryPerformanceAccumulator()

        accumulator.recordExactCleanBaselinePrepared()
        accumulator.recordExactCleanBaselineAccepted()
        accumulator.recordExactCleanBaselineRejected()
        accumulator.recordExactCleanContinuityRenewed()
        accumulator.recordExactCleanMutationInvalidated()
        accumulator.recordExactFallbackAdmitted()
        accumulator.recordExactFallbackCoalesced()
        accumulator.recordAvoidedPhysicalFactsRead()
        accumulator.recordAvoidedPhysicalDetailRead()
        let uncertaintyReasons: [GitCleanContinuityFailureReason] = [
            .unsupportedObservation,
            .registrationMissing,
            .registrationReplaced,
            .identityChanged,
            .mutationObserved,
            .eventStreamUncertain,
            .streamStartFailed,
            .shutdown,
        ]
        for reason in uncertaintyReasons {
            accumulator.recordContinuityUncertainty(reason)
        }
        accumulator.recordExactCleanContinuityState(
            authorityCount: 17,
            oldestCheckpointAgeMilliseconds: 1250
        )

        let snapshot = accumulator.takeSnapshot()
        #expect(snapshot.exactCleanBaselinePrepared == 1)
        #expect(snapshot.exactCleanBaselineAccepted == 1)
        #expect(snapshot.exactCleanBaselineRejected == 1)
        #expect(snapshot.exactCleanContinuityRenewed == 1)
        #expect(snapshot.exactCleanMutationInvalidated == 1)
        #expect(snapshot.exactFallbackAdmitted == 1)
        #expect(snapshot.exactFallbackCoalesced == 1)
        #expect(snapshot.avoidedPhysicalFactsRead == 1)
        #expect(snapshot.avoidedPhysicalDetailRead == 1)
        #expect(snapshot.continuityUncertaintyUnsupportedObservation == 1)
        #expect(snapshot.continuityUncertaintyRegistrationMissing == 1)
        #expect(snapshot.continuityUncertaintyRegistrationReplaced == 1)
        #expect(snapshot.continuityUncertaintyIdentityChanged == 1)
        #expect(snapshot.continuityUncertaintyMutationObserved == 1)
        #expect(snapshot.continuityUncertaintyEventStreamUncertain == 1)
        #expect(snapshot.continuityUncertaintyStreamStartFailed == 1)
        #expect(snapshot.continuityUncertaintyShutdown == 1)
        #expect(snapshot.exactCleanAuthorityCurrent == 17)
        #expect(snapshot.exactCleanOldestCheckpointAgeMilliseconds == 1250)
        #expect(accumulator.takeSnapshot() == GitWorkingDirectoryPerformanceSnapshot())
    }
}
