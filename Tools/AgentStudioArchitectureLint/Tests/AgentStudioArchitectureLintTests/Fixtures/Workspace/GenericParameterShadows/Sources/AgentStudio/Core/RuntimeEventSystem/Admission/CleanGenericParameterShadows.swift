extension OrderedFactJournal {
    func retainGenericStateShadow<State>(_ value: State) {
        func retainNestedValue(_ nestedValue: State) {
            _ = nestedValue
        }
        retainNestedValue(value)
    }
}

func retainGenericJournalShadow<OrderedFactJournal>(
    journal: OrderedFactJournal,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

func retainGenericTokenShadow<AdmissionProtectedRegionToken>(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

func retainGenericRawLockShadow<OSAllocatedUnfairLock>(
    lock: OSAllocatedUnfairLock
) {
    _ = lock
}

typealias GenericJournalPlaceholder<OrderedFactJournal> = OrderedFactJournal

func retainGenericJournalPlaceholder<Value>(
    journal: GenericJournalPlaceholder<Value>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

struct GenericJournalNamespace<OrderedFactJournal> {
    typealias Placeholder = OrderedFactJournal
}

func retainNestedGenericJournalPlaceholder<Value>(
    journal: GenericJournalNamespace<Value>.Placeholder,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

protocol AssociatedTypeIdentityShadows {
    associatedtype OrderedFactJournal
    associatedtype AdmissionProtectedRegionToken

    func retainAssociatedIdentityShadows(
        journal: OrderedFactJournal,
        token: borrowing AdmissionProtectedRegionToken
    )
}

enum NominalIdentityShadows {
    final class AdmissionProtectedRegionToken {}
    struct OSAllocatedUnfairLock {}
    enum State {}
    actor OrderedFactJournal {}
    protocol AgentStudio {}

    static func retainNominalIdentityShadows(
        journal: OrderedFactJournal,
        token: AdmissionProtectedRegionToken,
        lock: OSAllocatedUnfairLock,
        state: State
    ) {
        _ = journal
        _ = token
        _ = lock
        _ = state
    }
}

func retainLocalNominalIdentityShadows() {
    struct OrderedFactJournal {}
    struct AdmissionProtectedRegionToken {}

    func retain(
        journal: OrderedFactJournal,
        token: AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }

    _ = retain
}
