import AgentStudioCore
import Foundation

struct RepoExplorerLeafSortKey {
    let name: String
    let activityAt: Date?
    let identity: UUID
}

/// Shared detached leaf ordering for Repos, Panes and direct pinned navigation.
enum RepoExplorerLeafOrdering {
    static func precedes(
        _ lhs: RepoExplorerLeafSortKey,
        _ rhs: RepoExplorerLeafSortKey,
        sortField: SidebarSortField,
        sortOrder: SidebarSortDirection,
        referenceDate: Date
    ) -> Bool {
        if sortField == .activity {
            let left = validActivity(lhs.activityAt, referenceDate: referenceDate)
            let right = validActivity(rhs.activityAt, referenceDate: referenceDate)
            if (left == nil) != (right == nil) { return left != nil }
            if let left, let right, left != right {
                return sortOrder == .ascending ? left < right : left > right
            }
        }
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == (sortOrder == .ascending ? .orderedAscending : .orderedDescending)
        }
        return lhs.identity.uuidString < rhs.identity.uuidString
    }

    private static func validActivity(_ date: Date?, referenceDate: Date) -> Date? {
        guard let date, date.timeIntervalSince1970.isFinite,
            referenceDate.timeIntervalSince1970.isFinite, date <= referenceDate
        else { return nil }
        return date
    }
}
