import Foundation

enum WorkspaceTabMembershipNormalizer {
    static func normalize(
        tabs: [Tab],
        validPaneIds: Set<UUID>,
        activeTabId: UUID?,
        drawerParentPaneIdByDrawerId: [UUID: UUID]
    ) -> WorkspaceTabMembershipNormalizationResult {
        var normalizedTabs = tabs
        var repairedTabIds: [UUID] = []
        var drawerIdByParentPaneId: [UUID: UUID] = [:]
        for (drawerId, parentPaneId) in drawerParentPaneIdByDrawerId
        where drawerIdByParentPaneId[parentPaneId] == nil {
            drawerIdByParentPaneId[parentPaneId] = drawerId
        }

        for tabIndex in normalizedTabs.indices {
            let originalTab = normalizedTabs[tabIndex]
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: normalizedTabs[tabIndex].arrangements
            )
            normalizedTabs[tabIndex].arrangements =
                TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                    drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
                    from: normalizedTabs[tabIndex].arrangements
                )
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.promotingLiveArrangementToDefault(
                in: normalizedTabs[tabIndex].arrangements
            )

            if normalizedTabs[tabIndex].activeArrangement.layout.isEmpty,
                let liveArrangement = normalizedTabs[tabIndex].arrangements.first(where: { !$0.layout.isEmpty })
            {
                normalizedTabs[tabIndex].activeArrangementId = liveArrangement.id
            }

            for arrangementIndex in normalizedTabs[tabIndex].arrangements.indices {
                if let activePaneId = normalizedTabs[tabIndex].arrangements[arrangementIndex].activePaneId,
                    !validPaneIds.contains(activePaneId)
                        || !normalizedTabs[tabIndex].arrangements[arrangementIndex].layout.contains(activePaneId)
                        || normalizedTabs[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.contains(
                            activePaneId
                        )
                {
                    normalizedTabs[tabIndex].arrangements[arrangementIndex].activePaneId =
                        TabArrangementSelectionRules.firstUnminimizedPaneId(
                            in: normalizedTabs[tabIndex].arrangements[arrangementIndex]
                        )
                }
            }

            normalizedTabs[tabIndex].allPaneIds = normalizedMembershipPaneIds(
                for: normalizedTabs[tabIndex],
                validPaneIds: validPaneIds,
                drawerIdByParentPaneId: drawerIdByParentPaneId
            )

            if normalizedTabs[tabIndex] != originalTab {
                repairedTabIds.append(originalTab.id)
            }
        }

        let tabIdsBeforeDroppingEmptyTabs = Set(normalizedTabs.map(\.id))
        normalizedTabs.removeAll { tab in
            !TabArrangementRepairRules.hasLivePaneReferences(in: tab.arrangements)
        }
        let droppedTabIds = tabIdsBeforeDroppingEmptyTabs.subtracting(normalizedTabs.map(\.id))
        for tabId in droppedTabIds where !repairedTabIds.contains(tabId) {
            repairedTabIds.append(tabId)
        }

        var normalizedActiveTabId = activeTabId
        if let activeTabId, !normalizedTabs.contains(where: { $0.id == activeTabId }) {
            normalizedActiveTabId = normalizedTabs.last?.id
        }

        return WorkspaceTabMembershipNormalizationResult(
            tabs: normalizedTabs,
            activeTabId: normalizedActiveTabId,
            repairReport: WorkspaceTabMembershipRepairReport(
                repairedTabIds: repairedTabIds,
                activeTabIdChanged: normalizedActiveTabId != activeTabId
            )
        )
    }

    private static func normalizedMembershipPaneIds(
        for tab: Tab,
        validPaneIds: Set<UUID>,
        drawerIdByParentPaneId: [UUID: UUID]
    ) -> [UUID] {
        let referencedPaneIds = orderedReferencedPaneIds(
            in: tab,
            validPaneIds: validPaneIds,
            drawerIdByParentPaneId: drawerIdByParentPaneId
        )
        let referencedPaneIdSet = Set(referencedPaneIds)
        var normalizedPaneIds: [UUID] = []
        var seenPaneIds = Set<UUID>()

        for paneId in referencedPaneIds {
            guard seenPaneIds.insert(paneId).inserted else { continue }
            normalizedPaneIds.append(paneId)
        }
        for paneId in tab.allPaneIds where validPaneIds.contains(paneId) && referencedPaneIdSet.contains(paneId) {
            guard seenPaneIds.insert(paneId).inserted else { continue }
            normalizedPaneIds.append(paneId)
        }

        return normalizedPaneIds
    }

    private static func orderedReferencedPaneIds(
        in tab: Tab,
        validPaneIds: Set<UUID>,
        drawerIdByParentPaneId: [UUID: UUID]
    ) -> [UUID] {
        var paneIds: [UUID] = []
        var seenPaneIds = Set<UUID>()
        for arrangement in tab.arrangements {
            for paneId in arrangement.layout.paneIds where validPaneIds.contains(paneId) {
                guard seenPaneIds.insert(paneId).inserted else { continue }
                paneIds.append(paneId)
            }
            for parentPaneId in arrangement.layout.paneIds {
                guard let drawerId = drawerIdByParentPaneId[parentPaneId],
                    let drawerView = arrangement.drawerViews[drawerId]
                else {
                    continue
                }
                for paneId in drawerView.layout.paneIds where validPaneIds.contains(paneId) {
                    guard seenPaneIds.insert(paneId).inserted else { continue }
                    paneIds.append(paneId)
                }
            }
        }
        return paneIds
    }
}
