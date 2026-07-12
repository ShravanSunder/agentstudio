import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission strict type-state contracts")
struct AdmissionTypeStateContractTests {
    @Test("cleanup modes carry every required value in their case")
    func cleanupModesCarryRequiredValues() {
        let quantumCases: [AdmissionCleanupQuantum] = [
            .entries(maximumEntries: 3),
            .entriesAndBytes(maximumEntries: 3, maximumBytes: 1024),
        ]
        let releaseCases: [AdmissionCleanupRelease] = [
            .entries(count: 2),
            .entriesAndBytes(count: 2, bytes: 512),
        ]

        #expect(quantumCases[0].isValid)
        #expect(quantumCases[1].isValid)
        #expect(releaseCases[0] == .entries(count: 2))
        #expect(releaseCases[1] == .entriesAndBytes(count: 2, bytes: 512))
    }

    @Test("nonempty batches always own a first element")
    func nonemptyBatchesOwnFirstElement() {
        let batch = NonEmptyAdmissionBatch(first: "first", remaining: ["second"])
        var visited: [String] = []

        batch.forEach { visited.append($0) }

        #expect(batch.count == 2)
        #expect(visited == ["first", "second"])
    }

    @Test("doorbell snapshots expose only reachable storage states")
    func doorbellSnapshotsExposeReachableStates() {
        let states: [AdmissionDoorbellStateSnapshot] = [
            .idle,
            .signalPending,
            .consumerWaiting,
            .finished,
        ]

        #expect(states == [.idle, .signalPending, .consumerWaiting, .finished])
    }

    @Test("exact drain age cannot select conservative diagnostic precision")
    func exactDrainAgeOwnsOnlyDuration() {
        let age = ExactAdmissionAge(duration: .milliseconds(250))

        #expect(age == ExactAdmissionAge(duration: .milliseconds(250)))
    }
}
