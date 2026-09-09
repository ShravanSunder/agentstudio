import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerActivityBucket")
struct RepoExplorerActivityBucketTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("activity buckets use exclusive boundaries and never invent missing activity")
    func exclusiveActivityBoundaries() {
        let now = Date(timeIntervalSince1970: 1_788_804_000)
        let cases: [(TimeInterval?, RepoExplorerActivityBucket)] = [
            (nil, .noActivity), (-1, .noActivity), (0, .active),
            (59, .active), (60, .justNow), (599, .justNow),
            (600, .lastHour), (3599, .lastHour),
            (7 * 86_400, .older),
        ]
        for (age, expected) in cases {
            let date = age.map { now.addingTimeInterval(-$0) }
            #expect(RepoExplorerActivityBucket.classify(activityAt: date, now: now, calendar: calendar) == expected)
        }
        #expect(
            RepoExplorerActivityBucket.classify(
                activityAt: Date(timeIntervalSince1970: .infinity), now: now, calendar: calendar
            ) == .noActivity
        )
    }

    @Test("recent activity takes precedence across midnight without duplicating buckets")
    func recentActivityAcrossMidnight() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 0, minute: 5)))
        #expect(
            RepoExplorerActivityBucket.classify(
                activityAt: now.addingTimeInterval(-8 * 60), now: now, calendar: calendar
            ) == .justNow
        )
        #expect(
            RepoExplorerActivityBucket.classify(
                activityAt: now.addingTimeInterval(-2 * 3600), now: now, calendar: calendar
            ) == .lastSevenDays
        )
    }

    @Test("the next boundary is derived from evidence and calendar, not a polling cadence")
    func nextActivityBoundary() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 23, minute: 55)))
        let activeAt = now.addingTimeInterval(-30)
        #expect(
            RepoExplorerActivityBucket.nextChangeDate(activityAt: activeAt, now: now, calendar: calendar)
                == activeAt.addingTimeInterval(60)
        )
        #expect(
            RepoExplorerActivityBucket.nextChangeDate(
                activityAt: now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar
            ) == calendar.startOfDay(for: now).addingTimeInterval(86_400)
        )
        #expect(RepoExplorerActivityBucket.nextChangeDate(activityAt: nil, now: now, calendar: calendar) == nil)
    }
}
