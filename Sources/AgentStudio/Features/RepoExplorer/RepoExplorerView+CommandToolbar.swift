import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

enum RepoExplorerOrganizationSelector: Hashable {
    case sortField
    case subgroup
    case group
}

extension RepoExplorerView {
    var sidebarSurfaceSelector: some View {
        let presentation = RepoExplorerToolbarCommandPresentation.resolve(snapshot: commandPresentationSnapshot)
        return SidebarEntityToggle(
            segments: [AppCommand.showReposSidebar, .showPanesSidebar].map { command in
                SidebarToolbarSegment(
                    value: command,
                    label: command.definition.label,
                    accessibilityIdentifier: "sidebarSurface.\(command.rawValue)",
                    tooltipValue: command.definition.controlTooltipRenderValue(),
                    isEnabled: presentation.command(command)?.isEnabled == true
                )
            },
            selection: repoExplorerPrefs.sidebarSurface == .repos ? .showReposSidebar : .showPanesSidebar,
            octiconLoader: octiconLoader,
            entityIcon: { $0 == .showReposSidebar ? .repo : .pane },
            onSelect: { command in commandDispatcher.dispatch(command) }
        )
        .accessibilityIdentifier("sidebarSurfaceSelector")
    }

    var repoToolbarRow: some View {
        let presentation = RepoExplorerToolbarCommandPresentation.resolve(snapshot: commandPresentationSnapshot)
        let isPanes = repoExplorerPrefs.sidebarSurface == .panes
        let showsSubgroup = isPanes && repoExplorerPrefs.groupingMode != .activity
        let sortCommands: [AppCommand] =
            isPanes
            ? [.setPanesSortFieldName, .setPanesSortFieldActivity]
            : [.setReposSortFieldName, .setReposSortFieldActivity]
        let subgroupCommands: [AppCommand] = [.setPanesSubgroupNone, .setPanesSubgroupActivity]
        let groupingCommands: [AppCommand] =
            isPanes
            ? [.setPanesGroupingRepo, .setPanesGroupingTab, .setPanesGroupingActivity]
            : [.setReposGroupingRepo, .setReposGroupingActivity]
        return HStack(spacing: AppStyles.General.Spacing.tight) {
            Spacer(minLength: 0)
            organizationSelector(
                .sortField, commands: sortCommands,
                selected: sortCommands[repoExplorerPrefs.sortField == .name ? 0 : 1],
                presentation: presentation
            )
            sortDirectionButton(
                isPanes ? .togglePanesSortDirection : .toggleReposSortDirection,
                presentation: presentation
            )
            commandToggle(
                isPanes ? .togglePanesShowsPinned : .toggleReposShowsPinned,
                selected: repoExplorerPrefs.showsPinned, presentation: presentation
            )
            SidebarToolbarDivider()
            if showsSubgroup {
                organizationSelector(
                    .subgroup, commands: subgroupCommands,
                    selected: subgroupCommands[repoExplorerPrefs.subgroupMode == .ungrouped ? 0 : 1],
                    presentation: presentation
                )
            }
            if showsSubgroup {
                SidebarGroupingConnector()
            }
            organizationSelector(
                .group, commands: groupingCommands,
                selected: groupingCommand, presentation: presentation
            )
        }
        .accessibilityIdentifier("repoSidebarToolbarRow")
        .onChange(of: repoExplorerPrefs.sidebarSurface) { _, _ in openOrganizationSelector = nil }
        .onChange(of: showsSubgroup) { _, visible in
            if !visible && openOrganizationSelector == .subgroup { openOrganizationSelector = nil }
        }
    }

    private func organizationSelector(
        _ selector: RepoExplorerOrganizationSelector, commands: [AppCommand], selected: AppCommand,
        presentation: RepoExplorerToolbarCommandPresentation
    ) -> some View {
        SidebarDropdownSelector(
            options: commands.map { command in
                SidebarToolbarSegment(
                    value: command, label: command.definition.label,
                    accessibilityIdentifier: controlAccessibilityIdentifier(command),
                    tooltipValue: command.definition.controlTooltipRenderValue(),
                    isEnabled: presentation.command(command)?.isEnabled == true
                )
            },
            selection: selected, label: selected.definition.helpText,
            tooltip: selected.definition.controlTooltipRenderValue(),
            appearance: selector == .sortField ? .unhighlighted : (selector == .subgroup ? .neutral : .accent),
            isOpen: Binding(
                get: { openOrganizationSelector == selector },
                set: { openOrganizationSelector = $0 ? selector : nil }
            ),
            icon: { command in
                command.definition.icon.swiftUIImage(loader: octiconLoader, size: AppStyles.General.Icon.compact)
            },
            onSelect: { command in commandDispatcher.dispatch(command) }
        )
    }

    private var groupingCommand: AppCommand {
        switch (repoExplorerPrefs.sidebarSurface, repoExplorerPrefs.groupingMode) {
        case (.repos, .repo), (.inbox, .repo), (.repos, .tab), (.inbox, .tab):
            .setReposGroupingRepo
        case (.repos, .activity), (.inbox, .activity):
            .setReposGroupingActivity
        case (.panes, .repo):
            .setPanesGroupingRepo
        case (.panes, .tab):
            .setPanesGroupingTab
        case (.panes, .activity):
            .setPanesGroupingActivity
        }
    }

    private func commandSegments(
        _ commands: [AppCommand], selected: AppCommand?,
        presentation: RepoExplorerToolbarCommandPresentation, showsLabel: Bool = false,
        content: SidebarToggleModel<AppCommand>.Content? = nil
    ) -> some View {
        SidebarToolbarSegmentedControl(
            segments: commands.map { command in
                SidebarToolbarSegment(
                    value: command, label: command.definition.label,
                    accessibilityIdentifier: controlAccessibilityIdentifier(command),
                    tooltipValue: command.definition.controlTooltipRenderValue(
                        textOverride: isSortDirectionCommand(command) ? repoExplorerPrefs.sortDirection.title : nil
                    ),
                    isEnabled: presentation.command(command)?.isEnabled == true
                )
            },
            selection: selected,
            content: content ?? (showsLabel ? .selectedLabel : .icons),
            icon: { command in
                command.definition.icon.swiftUIImage(loader: octiconLoader, size: AppStyles.General.Icon.compact)
                    .rotationEffect(
                        .degrees(
                            isSortDirectionCommand(command) && repoExplorerPrefs.sortDirection == .descending ? 180 : 0)
                    )
            },
            onSelect: { command in
                guard presentation.command(command)?.isEnabled == true else { return }
                commandDispatcher.dispatch(command)
            }
        )
    }

    private func controlAccessibilityIdentifier(_ command: AppCommand) -> String {
        switch command {
        case .setReposGroupingRepo, .setPanesGroupingRepo: "repoSidebarGroupingSegment.repo"
        case .setPanesGroupingTab: "repoSidebarGroupingSegment.tab"
        case .setReposGroupingActivity, .setPanesGroupingActivity: "repoSidebarGroupingSegment.activity"
        default: "sidebarOrganization.\(command.rawValue)"
        }
    }

    private func isSortDirectionCommand(_ command: AppCommand) -> Bool {
        command == .toggleReposSortDirection || command == .togglePanesSortDirection
    }

    @ViewBuilder
    private func sortDirectionButton(
        _ command: AppCommand, presentation: RepoExplorerToolbarCommandPresentation
    ) -> some View {
        if let sortCommand = presentation.command(command) {
            SidebarToolbarSortButton(
                sortValue: repoExplorerPrefs.sortDirection,
                isReversed: repoExplorerPrefs.sortDirection == .descending,
                label: sortCommand.commandSpec.label,
                accessibilityIdentifier: "repoSidebarSortButton",
                tooltipValue: sortCommand.commandSpec.controlTooltipRenderValue(
                    textOverride: "Sort \(repoExplorerPrefs.sortDirection.title.lowercased())"
                ),
                icon: {
                    sortCommand.commandSpec.icon.swiftUIImage(
                        loader: octiconLoader, size: AppStyles.General.Icon.compact
                    )
                },
                onToggle: { commandDispatcher.dispatch(command) }
            )
            .id("repoSidebarSortButton.stable")
            .disabled(!sortCommand.isEnabled)
        }
    }

    @ViewBuilder
    private func commandToggle(
        _ command: AppCommand, selected: Bool, presentation: RepoExplorerToolbarCommandPresentation
    ) -> some View {
        if let presented = presentation.command(command) {
            SidebarToolbarActionButton(
                label: presented.commandSpec.label,
                accessibilityIdentifier: "sidebarOrganization.\(command.rawValue)",
                tooltipValue: presented.commandSpec.controlTooltipRenderValue(),
                icon: {
                    presented.commandSpec.icon.swiftUIImage(
                        loader: octiconLoader, size: AppStyles.General.Icon.compact
                    )
                },
                isActive: selected,
                action: { commandDispatcher.dispatch(command) }
            )
            .disabled(!presented.isEnabled)
        }
    }
}
