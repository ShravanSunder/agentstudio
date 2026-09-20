extension AppCommand {
    func focusSidebarDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            shortcut: .focusSidebar,
            label: "Focus Sidebar",
            icon: .system(.keyboard),
            helpText: "Move keyboard focus to the sidebar",
            surfacePolicy: .exposed([.commandBar, .inlineControl]),
            targeting: .contextual,
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.sidebar
        )
    }

    func pinRepoDefinition() -> AppCommandSpec {
        sidebarPinDefinition(
            label: "Pin Repository",
            icon: .pin,
            helpText: "Pin this repository in the Repos sidebar",
            targetType: .repo
        )
    }

    func unpinRepoDefinition() -> AppCommandSpec {
        sidebarPinDefinition(
            label: "Unpin Repository",
            icon: .pinFill,
            helpText: "Unpin this repository from the Repos sidebar",
            targetType: .repo
        )
    }

    func pinPaneDefinition() -> AppCommandSpec {
        sidebarPinDefinition(
            label: "Pin Pane",
            icon: .pin,
            helpText: "Pin this pane in the Panes sidebar",
            targetType: .pane
        )
    }

    func unpinPaneDefinition() -> AppCommandSpec {
        sidebarPinDefinition(
            label: "Unpin Pane",
            icon: .pinFill,
            helpText: "Unpin this pane from the Panes sidebar",
            targetType: .pane
        )
    }

    func showReposSidebarDefinition() -> AppCommandSpec {
        sidebarScreenDefinition(
            shortcut: .showReposSidebar,
            label: "Repos",
            icon: .octicon(.repo),
            helpText: "Show repositories and worktrees in the sidebar",
            sidebarKeyboardCompletion: .returnToOrigin
        )
    }

    func showPanesSidebarDefinition() -> AppCommandSpec {
        sidebarScreenDefinition(
            shortcut: .showPanesSidebar,
            label: "Panes",
            icon: .system(.squareSplit2x1),
            helpText: "Show pane destinations in the sidebar",
            sidebarKeyboardCompletion: .returnToOrigin
        )
    }

    func setReposGroupingRepoDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Repo",
            icon: .octicon(.repo),
            helpText: "Group the Repos sidebar by repository"
        )
    }

    func setReposGroupingActivityDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Activity",
            icon: .system(.clock),
            helpText: "Group the Repos sidebar by terminal activity"
        )
    }

    func retiredPanesOrganizationDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Panes",
            icon: .system(.clock),
            helpText: "Panes are always organized by most recent activity",
            surfacePolicy: .notPresented,
            targeting: .contextual,
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.sidebar
        )
    }

    func setReposSortFieldNameDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Name",
            icon: .system(.line3Horizontal),
            helpText: "Sort Repos sidebar rows by name"
        )
    }

    func setReposSortFieldActivityDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Activity",
            icon: .system(.clock),
            helpText: "Sort Repos sidebar rows by terminal activity"
        )
    }

    func toggleReposSortDirectionDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Direction",
            icon: .system(.arrowUpArrowDown),
            helpText: "Reverse the Repos sidebar leaf sort direction"
        )
    }

    func toggleReposShowsPinnedDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Show Pinned",
            icon: .system(.pin),
            helpText: "Show or merge the Pinned repos section"
        )
    }

    func togglePanesShowsPinnedDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Show Pinned",
            icon: .system(.pin),
            helpText: "Show or merge the Pinned Panes section"
        )
    }
}
