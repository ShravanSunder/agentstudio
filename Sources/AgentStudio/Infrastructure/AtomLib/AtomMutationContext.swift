@MainActor
final class AtomMutationContext {
    private let aggregateRevision: AtomRevision
    private var hasAcceptedChange = false
    private var hasCommitted = false

    init(aggregateRevision: AtomRevision) {
        self.aggregateRevision = aggregateRevision
    }

    func recordAcceptedChange() {
        assertMutable()
        hasAcceptedChange = true
    }

    func assertMutable() {
        precondition(!hasCommitted, "Cannot mutate AtomLib state after AtomMutationContext commit")
    }

    func commit() {
        guard !hasCommitted else { return }
        hasCommitted = true
        if hasAcceptedChange {
            aggregateRevision.bump()
        }
    }
}
