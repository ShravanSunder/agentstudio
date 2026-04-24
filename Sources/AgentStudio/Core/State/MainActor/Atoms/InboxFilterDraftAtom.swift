import Observation

@MainActor
@Observable
final class InboxFilterDraftAtom {
    /// One-shot intent consumed by the inbox surface when it becomes active.
    ///
    /// Views may observe `pendingFilter` to react when the inbox is already mounted, but
    /// ownership still flows through `set`, `consume`, and `clear`.
    private(set) var pendingFilter: InboxFilter?

    func set(_ filter: InboxFilter) {
        pendingFilter = filter
    }

    func peek() -> InboxFilter? {
        pendingFilter
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
