import Foundation

@MainActor
package struct CommandContextDerived {
    package init() {}

    package func currentContext(
        workspaceTab: WorkspaceTabLayoutDerived,
        workspacePane: WorkspacePaneAtom,
        focusedPane: WorkspaceFocusedPane?,
        workspacePanePresentation: WorkspacePanePresentationAtom
    ) -> CommandContext {
        guard
            let activeTabId = workspaceTab.shellAtom.activeTabId,
            let activeTab = workspaceTab.tab(activeTabId)
        else {
            return .empty
        }

        var satisfiedRequirements: Set<CommandRequirement> = [.hasActiveTab]

        if workspaceTab.tabs.count > 1 {
            satisfiedRequirements.insert(.hasMultipleTabs)
        }
        if workspacePane.activeResidencyPaneIds(in: activeTab.activeArrangement.layout.paneIds).count > 1 {
            satisfiedRequirements.insert(.hasMultiplePanes)
        }
        if activeTab.arrangements.count > 1 {
            satisfiedRequirements.insert(.hasArrangements)
        }

        if hasActiveTerminalZoom(
            in: activeTabId,
            workspacePane: workspacePane,
            workspacePanePresentation: workspacePanePresentation
        ) {
            satisfiedRequirements.insert(.supportsTerminalZoom)
            satisfiedRequirements.insert(.hasActiveTerminalZoom)
        }

        guard let focusedPane else {
            return CommandContext(
                activeTabId: activeTabId,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        satisfiedRequirements.insert(.hasActivePane)

        if let activeMainPane = workspacePane.pane(focusedPane.activeMainPaneId) {
            if case .terminal = activeMainPane.content {
                satisfiedRequirements.insert(.supportsTerminalZoom)
            }
            if let drawer = activeMainPane.drawer {
                satisfiedRequirements.insert(.hasDrawer)
                if drawer.isExpanded,
                    !workspacePane.activeResidencyPaneIds(in: drawer.paneIds).isEmpty
                {
                    satisfiedRequirements.insert(.hasDrawerPanes)
                }
            }
        }

        switch focusedPane.owner {
        case .mainPane:
            break
        case .emptyDrawer:
            satisfiedRequirements.insert(.hasEmptyDrawerFocus)
        case .drawerPane:
            satisfiedRequirements.insert(.hasFocusedDrawerPane)
        }

        return CommandContext(
            activeTabId: activeTabId,
            focusedPaneId: focusedPane.paneId,
            focusedRepoId: focusedPane.repoId,
            focusedWorktreeId: focusedPane.worktreeId,
            focusedContentType: focusedPane.contentType,
            satisfiedRequirements: satisfiedRequirements
        )
    }

    private func hasActiveTerminalZoom(
        in tabId: UUID,
        workspacePane: WorkspacePaneAtom,
        workspacePanePresentation: WorkspacePanePresentationAtom
    ) -> Bool {
        guard
            let sourcePaneId = workspacePanePresentation.zoomPresentation(forTab: tabId)?.sourcePaneId,
            let sourcePane = workspacePane.pane(sourcePaneId),
            case .terminal = sourcePane.content
        else {
            return false
        }
        return true
    }
}
