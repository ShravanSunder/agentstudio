import Observation
import Testing

@testable import AgentStudio

private final class AtomValueObservationCounter: @unchecked Sendable {
    private(set) var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
struct AtomValueObservationTests {
    @Test
    func equalScalarWriteDoesNotInvalidate() {
        let aggregateRevision = AtomRevision()
        let value = AtomValue<Int>(initialValue: 10)
        let counter = AtomValueObservationCounter()

        withObservationTracking {
            _ = value.value
        } onChange: {
            counter.record()
        }

        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        value.setValue(10, mutation: mutation)
        mutation.commit()

        #expect(!counter.didFire)
        #expect(aggregateRevision.value == 0)
    }

    @Test
    func changedScalarWriteInvalidatesOnceAndBumpsAggregateRevision() {
        let aggregateRevision = AtomRevision()
        let value = AtomValue<Int>(initialValue: 10)
        let counter = AtomValueObservationCounter()

        withObservationTracking {
            _ = value.value
        } onChange: {
            counter.record()
        }

        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        value.setValue(11, mutation: mutation)
        mutation.commit()

        #expect(counter.count == 1)
        #expect(value.value == 11)
        #expect(aggregateRevision.value == 1)
    }

    @Test
    func domainPayloadUsesExplicitContentComparator() {
        struct DomainPayload: Equatable {
            var stableID: String
            var displayName: String
            var rebuildGeneration: Int
        }

        let aggregateRevision = AtomRevision()
        let value = AtomValue(
            initialValue: DomainPayload(
                stableID: "repo-1",
                displayName: "Repo",
                rebuildGeneration: 0
            ),
            isContentEqual: { lhs, rhs in
                lhs.stableID == rhs.stableID && lhs.displayName == rhs.displayName
            }
        )
        let counter = AtomValueObservationCounter()

        withObservationTracking {
            _ = value.value
        } onChange: {
            counter.record()
        }

        let equalContentMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        value.setValue(
            DomainPayload(stableID: "repo-1", displayName: "Repo", rebuildGeneration: 1),
            mutation: equalContentMutation
        )
        equalContentMutation.commit()

        #expect(!counter.didFire)
        #expect(aggregateRevision.value == 0)

        let changedContentMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        value.setValue(
            DomainPayload(stableID: "repo-1", displayName: "Renamed", rebuildGeneration: 2),
            mutation: changedContentMutation
        )
        changedContentMutation.commit()

        #expect(counter.count == 1)
        #expect(value.value.displayName == "Renamed")
        #expect(aggregateRevision.value == 1)
    }
}
