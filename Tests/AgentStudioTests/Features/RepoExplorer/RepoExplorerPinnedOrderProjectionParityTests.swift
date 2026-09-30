import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("Pinned order under fixed Panes activity")
struct RepoExplorerPinnedOrderProjectionParityTests {
    @Test("legacy organization settings cannot change pinned activity order")
    func legacyOrganizationSettingsDoNotChangePinnedOrder() {
        let tabIDs = [UUIDv7.generate(), UUIDv7.generate()]
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let referenceInstant = ContinuousClock.now
        let members: [RepoExplorerPaneOrganizationMember] = (0..<6).map { index in
            let activityAt: Date? = index == 3 ? nil : referenceDate.addingTimeInterval(-Double(index * 900))
            return RepoExplorerPaneOrganizationMember(
                paneID: UUIDv7.generate(), repositoryID: nil, repositoryName: nil,
                tabID: tabIDs[index % 2], tabOrder: index % 2,
                normalizedTitle: ["Zulu", "Alpha", "Echo"][index % 3],
                isPinned: index != 2,
                activityAt: activityAt
            )
        }
        let locations = members.enumerated().map { index, member in
            WorkspacePaneLocation(
                paneId: member.paneID, tabId: member.tabID, tabIndex: member.tabOrder,
                paneIndexInTab: index, isActiveInTab: false
            )
        }
        let facts: [UUID: RepoExplorerPaneRowFacts] = Dictionary(
            uniqueKeysWithValues: members.map { member in
                (
                    member.paneID,
                    RepoExplorerPaneRowFacts(
                        terminalTitle: member.normalizedTitle, activityAt: member.activityAt,
                        paneActivityTime: member.activityAt.map {
                            PaneActivityTime(
                                orderingInstant: referenceInstant.advanced(
                                    by: .seconds(Int($0.timeIntervalSince(referenceDate)))
                                ),
                                wallTime: $0, source: .terminal
                            )
                        },
                        isPinned: member.isPinned, latestMessageText: nil,
                        recencyReferenceDate: referenceDate, recencyText: "", isActive: false
                    )
                )
            })
        for grouping in RepoExplorerGroupingMode.allCases {
            for subgroup in SidebarSubgroupMode.allCases {
                for sortField in SidebarSortField.allCases {
                    for direction in SidebarSortDirection.allCases {
                        let projection = RepoExplorerProjection.project(
                            RepoExplorerSnapshot(
                                repos: [], repoEnrichmentByRepoId: [:], surface: .panes,
                                groupingMode: grouping, subgroupMode: subgroup,
                                sortField: sortField, referenceDate: referenceDate,
                                referenceInstant: referenceInstant,
                                sortOrder: direction, query: "", unassociatedPaneLocations: locations
                            ),
                            paneRowFactsByPaneId: facts
                        )
                        let sidebarIDs = projection.sections.filter { $0.kind == .pinnedPanes }
                            .flatMap(\.resolvedGroups)
                            .flatMap { projection.paneRowsByGroupId[$0.id, default: []].map { $0.destination.paneId } }
                        let expectedPinnedIDs = [
                            members[0].paneID, members[1].paneID,
                            members[4].paneID, members[5].paneID, members[3].paneID,
                        ]
                        #expect(sidebarIDs == expectedPinnedIDs)
                        #expect(Set(sidebarIDs) == Set(members.filter(\.isPinned).map(\.paneID)))
                    }
                }
            }
        }
    }
}
