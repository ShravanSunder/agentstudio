import AgentStudioCore

@MainActor
extension CommandBarDataSource {
    static func paneAndTabItems(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> [CommandBarItem] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let workspacePane = store.paneAtom
        var items: [CommandBarItem] = []
        let selectTabSpec = CommandBarCommandPresentation.targetedSpec(
            for: .selectTab,
            targetType: .tab
        )
        for (tabIndex, tab) in workspaceTab.tabs.enumerated() {
            let tabTitle = tabDisplayTitle(tab: tab, store: store, repoCache: repoCache)
            let tabGroupName = "Tab \(tabIndex + 1): \(tabTitle)"
            let isActiveTab = tab.id == store.tabShellAtom.activeTabId

            if let selectTabSpec {
                items.append(
                    CommandBarItem(
                        id: "tab-\(tab.id.uuidString)",
                        title: tabTitle,
                        subtitle: tabLocationSubtitle(
                            tabIndex: tabIndex,
                            paneCount: nil,
                            isActive: isActiveTab
                        ),
                        icon: .system(.rectangleStack),
                        group: tabGroupName,
                        groupPriority: Priority.paneTabBase + tabIndex,
                        keywords: keywordsForTab(tab, store: store, repoCache: repoCache),
                        action: .dispatchTargeted(selectTabSpec.command, target: tab.id, targetType: .tab),
                        command: selectTabSpec.command
                    ))
            }

            for (paneIndex, paneId) in tab.activePaneIds.enumerated() {
                guard let pane = workspacePane.pane(paneId) else { continue }
                let isActive = tab.activePaneId == paneId
                let targetType = targetTypeForPane(pane)
                guard
                    let focusPaneSpec = CommandBarCommandPresentation.targetedSpec(
                        for: .focusPane,
                        targetType: targetType
                    )
                else {
                    continue
                }
                var paneKeywords = keywordsForPane(pane, store: store, repoCache: repoCache)
                paneKeywords.append(tabTitle)
                items.append(
                    CommandBarItem(
                        id: "pane-\(pane.id.uuidString)",
                        title: paneDisplayLabel(for: pane, store: store, repoCache: repoCache),
                        subtitle: paneLocationSubtitle(
                            tabTitle: nil,
                            tabIndex: tabIndex,
                            paneIndex: paneIndex,
                            isActive: isActive
                        ),
                        secondaryLine: paneNoteSecondaryLine(pane),
                        icon: iconForPane(pane),
                        iconColor: nil,
                        group: tabGroupName,
                        groupPriority: Priority.paneTabBase + tabIndex,
                        keywords: stableUniqueKeywords(paneKeywords),
                        action: .dispatchTargeted(
                            focusPaneSpec.command,
                            target: pane.id,
                            targetType: targetType
                        ),
                        command: focusPaneSpec.command
                    ))
            }
        }
        return items
    }
}
