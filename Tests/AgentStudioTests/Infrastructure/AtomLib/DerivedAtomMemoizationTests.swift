import Testing

@testable import AgentStudioInfrastructure

@MainActor
struct DerivedAtomMemoizationTests {
    @Test
    func cacheHitAvoidsRecomputeWhenInputRevisionsAreUnchanged() {
        let sourceRevision = AtomRevision()
        var sourceValue = 2
        var computeCount = 0
        let derived = DerivedAtom<Int>(
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
        let derived = DerivedAtom<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: {
                computeCount += 1
                return sourceValue % 2
            }
        )

        #expect(derived.value == 1)
        let revisionAfterFirstRead = derived.revision

        sourceValue = 3
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(derived.value == 1)
        #expect(computeCount == 2)
        #expect(derived.revision == revisionAfterFirstRead)
    }

    @Test
    func recomputeWithChangedOutputBumpsOwnRevisionOnce() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let derived = DerivedAtom<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue }
        )

        #expect(derived.value == 1)
        let revisionAfterFirstRead = derived.revision

        sourceValue = 2
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(derived.value == 2)
        #expect(derived.revision == revisionAfterFirstRead + 1)
    }

    @Test
    func chainedDerivedReadsUpstreamValueBeforeUpstreamRevision() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let upstream = DerivedAtom<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue * 2 }
        )
        var latestUpstreamValue = 0
        let downstream = DerivedAtom<Int>(
            inputRevisions: {
                [upstream.revision]
            },
            isContentEqual: ==,
            compute: {
                latestUpstreamValue = upstream.value
                return latestUpstreamValue + 1
            }
        )

        #expect(downstream.value == 3)

        sourceValue = 2
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(downstream.value == 5)
        #expect(upstream.revision == 1)
        #expect(downstream.revision == 1)
    }

    @Test
    func readingRevisionMaterializesAnUnmaterializedNode() {
        var computeCount = 0
        let derived = DerivedAtom<Int>(
            inputRevisions: { [0] },
            isContentEqual: ==,
            compute: {
                computeCount += 1
                return 42
            }
        )

        #expect(derived.revision == 0)
        #expect(computeCount == 1)
        #expect(derived.value == 42)
        #expect(computeCount == 1)
    }
}
