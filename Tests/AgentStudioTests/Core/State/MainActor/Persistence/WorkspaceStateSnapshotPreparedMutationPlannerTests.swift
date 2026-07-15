import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceStateSnapshotPreparedMutationPlannerTests {
    @Test("prepared projection reads only keys touched by the mutation batch")
    func preparedProjectionReadsOnlyTouchedKeys() {
        // Arrange
        let originalKey = 9999
        let replacementKey = 10_000
        var baselineLookupCount = 0
        var projectedMembership = SnapshotProjectedMembership<Int>(
            keyCount: 10_000,
            totalRawKeyByteCount: 80_000,
            physicalSlotCount: 10_000,
            reusableSlotCount: 0,
            baselineRawKeyByteCount: { key in
                baselineLookupCount += 1
                return key < 10_000 ? 8 : nil
            }
        )

        // Act
        let rejection = SnapshotParticipantMutationPlanner.validate(
            [
                WorkspaceStateSnapshotParticipantMutation<Int, String>.replaceMembership(
                    removing: .init(key: originalKey, currentValue: .value("original")),
                    inserting: .init(key: replacementKey, rawKeyByteCount: 8)
                )
            ],
            limits: .init(maximumKeyCount: 10_000, maximumRawKeyBytes: 80_000),
            projectedMembership: &projectedMembership,
            validateValueReplacement: { _, _ in nil },
            removalValidator: { _ in .success(.init(makesSlotReusable: false)) }
        )

        // Assert
        #expect(rejection == nil)
        #expect(baselineLookupCount == 2)
        #expect(projectedMembership.keyCount == 10_000)
        #expect(projectedMembership.totalRawKeyByteCount == 80_000)
        #expect(projectedMembership.physicalSlotCount == 10_001)
    }
}
