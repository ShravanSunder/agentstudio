import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerPaneOrganizationPolicyTests")
struct RepoExplorerPaneOrganizationPolicyTests {
    @Test("repository groups and leaves match representative Panes sidebar order")
    func repositoryGroupingMatchesSidebarOrder() {
        let alphaRepositoryID = UUIDv7.generate()
        let zetaRepositoryID = UUIDv7.generate()
        let alphaPaneID = UUIDv7.generate()
        let zetaPaneID = UUIDv7.generate()
        let unassociatedPaneID = UUIDv7.generate()
        let input = organizationInput(
            groupingMode: .repo,
            members: [
                PaneOrganizationMemberFixture(
                    paneID: zetaPaneID,
                    repositoryID: zetaRepositoryID,
                    repositoryName: "Zeta",
                    normalizedTitle: "Zulu"
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: unassociatedPaneID,
                    normalizedTitle: "Middle"
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: alphaPaneID,
                    repositoryID: alphaRepositoryID,
                    repositoryName: "Alpha",
                    normalizedTitle: "Alpha"
                ).member,
            ]
        )

        let groups = RepoExplorerPaneOrganizationPolicy.orderedGroups(input)
        #expect(
            groups.map(\.identity) == [
                .repository(id: alphaRepositoryID, name: "Alpha"),
                .repository(id: nil, name: "No Repository"),
                .repository(id: zetaRepositoryID, name: "Zeta"),
            ])
        #expect(
            groups.flatMap { $0.members.map(\.paneID) } == [
                alphaPaneID, unassociatedPaneID, zetaPaneID,
            ])
    }

    @Test("tab groups follow stored tab order rather than input order")
    func tabGroupingUsesStoredOrder() {
        let firstTabID = UUIDv7.generate()
        let laterTabID = UUIDv7.generate()
        let firstPaneID = UUIDv7.generate()
        let laterPaneID = UUIDv7.generate()
        let input = organizationInput(
            groupingMode: .tab,
            members: [
                PaneOrganizationMemberFixture(
                    paneID: laterPaneID,
                    tabID: laterTabID,
                    tabOrder: 4,
                    normalizedTitle: "Later"
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: firstPaneID,
                    tabID: firstTabID,
                    tabOrder: 0,
                    normalizedTitle: "First"
                ).member,
            ]
        )

        let groups = RepoExplorerPaneOrganizationPolicy.orderedGroups(input)
        #expect(
            groups.map(\.identity) == [
                .tab(id: firstTabID, order: 0),
                .tab(id: laterTabID, order: 4),
            ])
        #expect(groups.flatMap { $0.members.map(\.paneID) } == [firstPaneID, laterPaneID])
    }

    @Test("activity groups classify current, older, missing, and invalid evidence")
    func activityGroupingClassifiesMissingAndInvalidEvidence() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let activePaneID = UUIDv7.generate()
        let lastHourPaneID = UUIDv7.generate()
        let missingPaneID = UUIDv7.generate()
        let invalidPaneID = UUIDv7.generate()
        let input = organizationInput(
            groupingMode: .activity,
            referenceDate: referenceDate,
            members: [
                PaneOrganizationMemberFixture(
                    paneID: invalidPaneID,
                    normalizedTitle: "Invalid",
                    activityAt: Date(timeIntervalSince1970: .infinity)
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: lastHourPaneID,
                    normalizedTitle: "Last hour",
                    activityAt: referenceDate.addingTimeInterval(-1800)
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: missingPaneID,
                    normalizedTitle: "Missing"
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: activePaneID,
                    normalizedTitle: "Active",
                    activityAt: referenceDate.addingTimeInterval(-1)
                ).member,
            ]
        )

        let groups = RepoExplorerPaneOrganizationPolicy.orderedGroups(input)
        #expect(
            groups.map(\.identity) == [
                .activity(.active),
                .activity(.lastHour),
                .activity(.noActivity),
            ])
        #expect(groups.last?.members.map(\.paneID) == [invalidPaneID, missingPaneID])
    }

    @Test("name sort supports both directions and UUID tie breaking")
    func nameSortDirectionsAndIdentityTieBreak() throws {
        let tieIDs = [UUIDv7.generate(), UUIDv7.generate()].sorted { $0.uuidString < $1.uuidString }
        let firstTieID = try #require(tieIDs.first)
        let secondTieID = try #require(tieIDs.last)
        let bravoID = UUIDv7.generate()
        let members = [
            PaneOrganizationMemberFixture(paneID: secondTieID, normalizedTitle: "alpha").member,
            PaneOrganizationMemberFixture(paneID: bravoID, normalizedTitle: "Bravo").member,
            PaneOrganizationMemberFixture(paneID: firstTieID, normalizedTitle: "Alpha").member,
        ]

        let ascending = RepoExplorerPaneOrganizationPolicy.orderedPaneIDs(
            organizationInput(sortField: .name, sortOrder: .ascending, members: members)
        )
        let descending = RepoExplorerPaneOrganizationPolicy.orderedPaneIDs(
            organizationInput(sortField: .name, sortOrder: .descending, members: members)
        )

        #expect(ascending == [firstTieID, secondTieID, bravoID])
        #expect(descending == [bravoID, firstTieID, secondTieID])
    }

    @Test("activity sort supports both directions and always leaves unknown evidence last")
    func activitySortDirectionsKeepUnknownLast() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let recentID = UUIDv7.generate()
        let olderID = UUIDv7.generate()
        let missingID = UUIDv7.generate()
        let invalidID = UUIDv7.generate()
        let members = [
            PaneOrganizationMemberFixture(
                paneID: recentID,
                normalizedTitle: "Recent",
                activityAt: referenceDate.addingTimeInterval(-10)
            ).member,
            PaneOrganizationMemberFixture(
                paneID: olderID,
                normalizedTitle: "Older",
                activityAt: referenceDate.addingTimeInterval(-100)
            ).member,
            PaneOrganizationMemberFixture(paneID: missingID, normalizedTitle: "Alpha unknown").member,
            PaneOrganizationMemberFixture(
                paneID: invalidID,
                normalizedTitle: "Zulu unknown",
                activityAt: Date(timeIntervalSince1970: .infinity)
            ).member,
        ]

        let ascending = RepoExplorerPaneOrganizationPolicy.orderedPaneIDs(
            organizationInput(
                sortField: .activity,
                sortOrder: .ascending,
                referenceDate: referenceDate,
                members: members
            )
        )
        let descending = RepoExplorerPaneOrganizationPolicy.orderedPaneIDs(
            organizationInput(
                sortField: .activity,
                sortOrder: .descending,
                referenceDate: referenceDate,
                members: members
            )
        )

        #expect(ascending == [olderID, recentID, missingID, invalidID])
        #expect(descending == [recentID, olderID, invalidID, missingID])
    }

    @Test("optional activity subgroup precedes leaf name ordering")
    func optionalActivitySubgroupShapesLeafOrder() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let activeZuluID = UUIDv7.generate()
        let olderAlphaID = UUIDv7.generate()
        let input = organizationInput(
            subgroupMode: .activity,
            referenceDate: referenceDate,
            members: [
                PaneOrganizationMemberFixture(
                    paneID: olderAlphaID,
                    normalizedTitle: "Alpha",
                    activityAt: referenceDate.addingTimeInterval(-1800)
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: activeZuluID,
                    normalizedTitle: "Zulu",
                    activityAt: referenceDate.addingTimeInterval(-1)
                ).member,
            ]
        )

        #expect(
            RepoExplorerPaneOrganizationPolicy.orderedPaneIDs(input)
                == [activeZuluID, olderAlphaID]
        )
    }

    @Test("pinned ordering filters membership and delegates to the shared order policy")
    func pinnedOrderingUsesSharedPolicy() {
        let pinnedAlphaID = UUIDv7.generate()
        let pinnedZuluID = UUIDv7.generate()
        let unpinnedID = UUIDv7.generate()
        let input = organizationInput(
            members: [
                PaneOrganizationMemberFixture(
                    paneID: pinnedZuluID,
                    normalizedTitle: "Zulu",
                    isPinned: true
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: unpinnedID,
                    normalizedTitle: "Middle",
                    isPinned: false
                ).member,
                PaneOrganizationMemberFixture(
                    paneID: pinnedAlphaID,
                    normalizedTitle: "Alpha",
                    isPinned: true
                ).member,
            ]
        )

        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.orderedPaneIDs(input)
                == [pinnedAlphaID, pinnedZuluID]
        )
    }

    @Test("successor policy wraps and defines absent-origin and empty behavior")
    func successorWrapAbsentAndEmptyBehavior() {
        let firstID = UUIDv7.generate()
        let middleID = UUIDv7.generate()
        let lastID = UUIDv7.generate()
        let absentID = UUIDv7.generate()
        let ordered = [firstID, middleID, lastID]

        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
                from: middleID, direction: .next, orderedPaneIDs: ordered
            ) == lastID
        )
        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
                from: lastID, direction: .next, orderedPaneIDs: ordered
            ) == firstID
        )
        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
                from: firstID, direction: .previous, orderedPaneIDs: ordered
            ) == lastID
        )
        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
                from: absentID, direction: .next, orderedPaneIDs: ordered
            ) == firstID
        )
        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
                from: absentID, direction: .previous, orderedPaneIDs: ordered
            ) == lastID
        )
        #expect(
            RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
                from: nil, direction: .next, orderedPaneIDs: []
            ) == nil
        )
    }
}

private struct PaneOrganizationMemberFixture {
    let paneID: UUID
    var repositoryID: UUID?
    var repositoryName: String?
    var tabID: UUID = UUIDv7.generate()
    var tabOrder = 0
    let normalizedTitle: String
    var isPinned = true
    var activityAt: Date?

    var member: RepoExplorerPaneOrganizationMember {
        RepoExplorerPaneOrganizationMember(
            paneID: paneID,
            repositoryID: repositoryID,
            repositoryName: repositoryName,
            tabID: tabID,
            tabOrder: tabOrder,
            normalizedTitle: normalizedTitle,
            isPinned: isPinned,
            activityAt: activityAt
        )
    }
}

private func organizationInput(
    groupingMode: RepoExplorerGroupingMode = .repo,
    subgroupMode: SidebarSubgroupMode = .ungrouped,
    sortField: SidebarSortField = .name,
    sortOrder: RepoExplorerSortOrder = .ascending,
    referenceDate: Date = Date(timeIntervalSince1970: 1_000_000),
    members: [RepoExplorerPaneOrganizationMember]
) -> RepoExplorerPaneOrganizationInput {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return RepoExplorerPaneOrganizationInput(
        members: members,
        preferences: RepoExplorerPaneOrganizationPreferences(
            groupingMode: groupingMode,
            subgroupMode: subgroupMode,
            sortField: sortField,
            sortOrder: sortOrder,
            referenceDate: referenceDate,
            calendar: calendar
        )
    )
}
