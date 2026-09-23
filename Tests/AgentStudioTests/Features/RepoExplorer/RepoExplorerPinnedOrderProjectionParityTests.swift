import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("Pinned order and full Panes projection parity")
struct RepoExplorerPinnedOrderProjectionParityTests {
    @Test("shared ordering agrees across every grouping, subgroup and leaf sort")
    func allOrganizationSettingsAgree() {
        let tabIDs = [UUIDv7.generate(), UUIDv7.generate()]
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
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
                        isPinned: member.isPinned, latestMessageText: nil,
                        recencyReferenceDate: referenceDate, recencyText: "", isActive: false
                    )
                )
            })
        for grouping in RepoExplorerGroupingMode.allCases {
            for subgroup in SidebarSubgroupMode.allCases {
                for sortField in SidebarSortField.allCases {
                    for direction in SidebarSortDirection.allCases {
                        let preferences = RepoExplorerPaneOrganizationPreferences(
                            groupingMode: grouping, subgroupMode: subgroup,
                            sortField: sortField, sortOrder: direction,
                            referenceDate: referenceDate, calendar: .current
                        )
                        let projection = RepoExplorerProjection.project(
                            RepoExplorerSnapshot(
                                repos: [], repoEnrichmentByRepoId: [:], surface: .panes,
                                groupingMode: grouping, subgroupMode: subgroup,
                                sortField: sortField, referenceDate: referenceDate,
                                sortOrder: direction, query: "", unassociatedPaneLocations: locations
                            ),
                            paneRowFactsByPaneId: facts
                        )
                        let sidebarIDs = projection.sections.filter { $0.kind == .pinnedPanes }
                            .flatMap(\.resolvedGroups)
                            .flatMap { projection.paneRowsByGroupId[$0.id, default: []].map { $0.destination.paneId } }
                        let pinnedIDs = RepoExplorerPinnedPaneNavigationPolicy.orderedPaneIDs(
                            .init(members: members, preferences: preferences)
                        )
                        #expect(sidebarIDs == pinnedIDs)
                        #expect(Set(pinnedIDs) == Set(members.filter(\.isPinned).map(\.paneID)))
                    }
                }
            }
        }
    }
}
