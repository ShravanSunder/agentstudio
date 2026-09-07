import AgentStudioInfrastructure
import Foundation

enum RepoExplorerActivityBucket: Int, CaseIterable, Equatable, Hashable, Sendable {
    case active
    case justNow
    case lastHour
    case today
    case lastSevenDays
    case older
    case noActivity

    var title: String {
        switch self {
        case .active: "Active"
        case .justNow: "Just Now"
        case .lastHour: "Last hour"
        case .today: "Today"
        case .lastSevenDays: "Last 7 days"
        case .older: "Older"
        case .noActivity: "No activity"
        }
    }

    static func classify(activityAt: Date?, now: Date, calendar: Calendar) -> Self {
        guard let activityAt,
            activityAt.timeIntervalSince1970.isFinite,
            now.timeIntervalSince1970.isFinite
        else { return .noActivity }
        let age = now.timeIntervalSince(activityAt)
        guard age >= 0 else { return .noActivity }
        if age < AppPolicies.RepoExplorer.activeActivityDuration { return .active }
        if age < AppPolicies.RepoExplorer.justNowActivityDuration { return .justNow }
        if age < AppPolicies.RepoExplorer.lastHourActivityDuration { return .lastHour }
        if calendar.isDate(activityAt, inSameDayAs: now) { return .today }
        if age < AppPolicies.RepoExplorer.recentActivityDuration { return .lastSevenDays }
        return .older
    }

    static func nextChangeDate(activityAt: Date?, now: Date, calendar: Calendar) -> Date? {
        guard let activityAt,
            activityAt.timeIntervalSince1970.isFinite,
            now.timeIntervalSince1970.isFinite
        else { return nil }
        if activityAt > now { return activityAt }
        switch classify(activityAt: activityAt, now: now, calendar: calendar) {
        case .active:
            return activityAt.addingTimeInterval(AppPolicies.RepoExplorer.activeActivityDuration)
        case .justNow:
            return activityAt.addingTimeInterval(AppPolicies.RepoExplorer.justNowActivityDuration)
        case .lastHour:
            return activityAt.addingTimeInterval(AppPolicies.RepoExplorer.lastHourActivityDuration)
        case .today:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        case .lastSevenDays:
            return activityAt.addingTimeInterval(AppPolicies.RepoExplorer.recentActivityDuration)
        case .older, .noActivity:
            return nil
        }
    }
}
