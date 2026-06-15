import Testing

@testable import AgentStudio

@MainActor
struct AtomRevisionTransactionTests {
    @Test
    func aggregateRevisionBumpsOncePerCommittedSemanticMutation() {
        let aggregateRevision = AtomRevision()
        let firstValue = AtomValue<Int>(initialValue: 0)
        let secondValue = AtomValue<Int>(initialValue: 10)

        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        firstValue.setValue(1, mutation: mutation)
        secondValue.setValue(11, mutation: mutation)
        mutation.commit()

        #expect(aggregateRevision.value == 1)
    }

    @Test
    func aggregateRevisionDoesNotBumpForEqualWritesOrEmptyCommit() {
        let aggregateRevision = AtomRevision()
        let value = AtomValue<Int>(initialValue: 3)

        let equalWriteMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        value.setValue(3, mutation: equalWriteMutation)
        equalWriteMutation.commit()

        let emptyMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        emptyMutation.commit()

        #expect(aggregateRevision.value == 0)
    }

    @Test
    func committedMutationIsIdempotent() {
        let aggregateRevision = AtomRevision()
        let value = AtomValue<Int>(initialValue: 0)
        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)

        value.setValue(1, mutation: mutation)
        mutation.commit()
        mutation.commit()

        #expect(aggregateRevision.value == 1)
    }
}
