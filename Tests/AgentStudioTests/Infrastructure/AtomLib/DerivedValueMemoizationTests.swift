import Testing

@testable import AgentStudio

@MainActor
struct DerivedValueMemoizationTests {
    @Test
    func cacheHitAvoidsRecomputeWhenInputRevisionsAreUnchanged() {
        let sourceRevision = AtomRevision()
        var sourceValue = 2
        var computeCount = 0
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: {
                computeCount += 1
                return sourceValue * 2
            }
        )

        #expect(derived.value == 4)
        sourceValue = 3
        #expect(derived.value == 4)
        #expect(computeCount == 1)
    }

    @Test
    func recomputeWithEqualOutputDoesNotBumpOwnRevision() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        var computeCount = 0
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: {
                computeCount += 1
                return sourceValue % 2
            }
        )

        #expect(derived.value == 1)
        let revisionAfterFirstRead = derived.revision.value

        sourceValue = 3
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(derived.value == 1)
        #expect(computeCount == 2)
        #expect(derived.revision.value == revisionAfterFirstRead)
    }

    @Test
    func recomputeWithChangedOutputBumpsOwnRevisionOnce() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue }
        )

        #expect(derived.value == 1)
        let revisionAfterFirstRead = derived.revision.value

        sourceValue = 2
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(derived.value == 2)
        #expect(derived.revision.value == revisionAfterFirstRead + 1)
    }

    @Test
    func chainedDerivedReadsUpstreamValueBeforeUpstreamRevision() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let upstream = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue * 2 }
        )
        var latestUpstreamValue = 0
        let downstream = DerivedValue<Int>(
            inputRevisions: {
                latestUpstreamValue = upstream.value
                return [upstream.revision.value]
            },
            isContentEqual: ==,
            compute: { latestUpstreamValue + 1 }
        )

        #expect(downstream.value == 3)

        sourceValue = 2
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(downstream.value == 5)
        #expect(upstream.revision.value == 1)
        #expect(downstream.revision.value == 1)
    }
}
