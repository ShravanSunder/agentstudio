extension AppCommand {
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
            helpText: "Show repositories and worktrees in the sidebar"
        )
    }

    func showPanesSidebarDefinition() -> AppCommandSpec {
        sidebarScreenDefinition(
            label: "Panes",
            icon: .system(.squareSplit2x1),
            helpText: "Show pane destinations in the sidebar"
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

    func setPanesGroupingRepoDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Repo",
            icon: .octicon(.repo),
            helpText: "Group the Panes sidebar by repository"
        )
    }

    func setPanesGroupingTabDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Tab",
            icon: .system(.squareStackFill),
            helpText: "Group the Panes sidebar by tab"
        )
    }

    func setPanesGroupingActivityDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Activity",
            icon: .system(.clock),
            helpText: "Group the Panes sidebar by terminal activity"
        )
    }

    func setPanesSubgroupNoneDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "None",
            icon: .system(.circle),
            helpText: "Do not subgroup panes in the Panes sidebar"
        )
    }

    func setPanesSubgroupActivityDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Activity",
            icon: .system(.clock),
            helpText: "Subgroup panes by terminal activity in the Panes sidebar"
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

    func setPanesSortFieldNameDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Name",
            icon: .system(.line3Horizontal),
            helpText: "Sort Panes sidebar rows by name"
        )
    }

    func setPanesSortFieldActivityDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Activity",
            icon: .system(.clock),
            helpText: "Sort Panes sidebar rows by terminal activity"
        )
    }

    func toggleReposSortDirectionDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Direction",
            icon: .system(.arrowUpArrowDown),
            helpText: "Reverse the Repos sidebar leaf sort direction"
        )
    }

    func togglePanesSortDirectionDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Direction",
            icon: .system(.arrowUpArrowDown),
            helpText: "Reverse the Panes sidebar leaf sort direction"
        )
    }

    func toggleReposShowsPinnedDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Show Pinned",
            icon: .system(.pinFill),
            helpText: "Show or merge the Pinned repos section"
        )
    }

    func togglePanesShowsPinnedDefinition() -> AppCommandSpec {
        sidebarSettingDefinition(
            label: "Show Pinned",
            icon: .system(.pinFill),
            helpText: "Show or merge the Pinned Panes section"
        )
    }
}
