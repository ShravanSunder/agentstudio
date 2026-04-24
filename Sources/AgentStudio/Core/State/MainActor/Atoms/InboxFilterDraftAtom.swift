import Observation

@MainActor
@Observable
final class InboxFilterDraftAtom {
    private(set) var pendingFilter: InboxFilter?

    func set(_ filter: InboxFilter?) {
        pendingFilter = filter
    }

    func consume() -> InboxFilter? {
        let filter = pendingFilter
        pendingFilter = nil
        return filter
    }

    func clear() {
        pendingFilter = nil
    }
}
