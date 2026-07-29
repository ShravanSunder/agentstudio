@MainActor
package final class AtomMutationContext {
    private let aggregateRevision: AtomRevision
    private var hasAcceptedChange = false
    private var hasCommitted = false

    package init(aggregateRevision: AtomRevision) {
        self.aggregateRevision = aggregateRevision
    }

    package func recordAcceptedChange() {
        assertMutable()
        hasAcceptedChange = true
    }

    package func assertMutable() {
        precondition(!hasCommitted, "Cannot mutate AtomLib state after AtomMutationContext commit")
    }

    package func commit() {
        guard !hasCommitted else { return }
        hasCommitted = true
        if hasAcceptedChange {
            aggregateRevision.bump()
        }
    }
}
