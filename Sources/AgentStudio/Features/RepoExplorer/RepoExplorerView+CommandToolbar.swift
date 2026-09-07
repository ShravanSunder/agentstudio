import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

extension RepoExplorerView {
    var sidebarSurfaceSelector: some View {
        let presentation = RepoExplorerToolbarCommandPresentation.resolve(snapshot: commandPresentationSnapshot)
        return Picker(
            "",
            selection: Binding(
                get: { atom(\.workspaceSidebarState).sidebarSurface },
                set: { surface in
                    let command: AppCommand = surface == .repos ? .showReposSidebar : .showPanesSidebar
                    guard presentation.command(command)?.isEnabled == true else { return }
                    commandDispatcher.dispatch(command)
                }
            )
        ) {
            Text(AppCommand.showReposSidebar.definition.label).tag(SidebarSurface.repos)
            Text(AppCommand.showPanesSidebar.definition.label).tag(SidebarSurface.panes)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("sidebarSurfaceSelector")
    }

    var repoToolbarRow: some View {
        ViewThatFits(in: .horizontal) {
            organizationControls(showsSelectedLabels: true)
            organizationControls(showsSelectedLabels: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("repoSidebarToolbarRow")
    }

    private func organizationControls(showsSelectedLabels: Bool) -> some View {
        let presentation = RepoExplorerToolbarCommandPresentation.resolve(snapshot: commandPresentationSnapshot)
        let isPanes = atom(\.workspaceSidebarState).sidebarSurface == .panes
        let groupingCommands: [AppCommand] =
            isPanes
            ? [.setPanesGroupingRepo, .setPanesGroupingTab, .setPanesGroupingActivity]
            : [.setReposGroupingRepo]
        let selectedGrouping: AppCommand =
            isPanes
            ? paneGroupingCommand : .setReposGroupingRepo
        let subgroupCommands: [AppCommand] =
            isPanes
            ? [.setPanesSubgroupNone, .setPanesSubgroupActivity]
            : [.setReposSubgroupNone, .setReposSubgroupActivity]
        let selectedSubgroup = subgroupCommands[repoExplorerPrefs.subgroupMode == .ungrouped ? 0 : 1]
        let sortCommands: [AppCommand] =
            isPanes
            ? [.setPanesSortFieldName, .setPanesSortFieldActivity]
            : [.setReposSortFieldName, .setReposSortFieldActivity]
        let selectedSort = sortCommands[repoExplorerPrefs.sortField == .name ? 0 : 1]
        return HStack(
            spacing: showsSelectedLabels
                ? AppStyles.General.Spacing.tight
                : AppStyles.Shell.Sidebar.ToolbarControl.segmentedControlSpacing
        ) {
            commandSegments(
                groupingCommands, selected: selectedGrouping,
                presentation: presentation, showsLabel: showsSelectedLabels)
            SidebarToolbarDivider()
            commandSegments(
                subgroupCommands, selected: selectedSubgroup,
                presentation: presentation, showsLabel: showsSelectedLabels
            )
            .disabled(isPanes && repoExplorerPrefs.groupingMode == .activity)
            SidebarToolbarDivider()
            commandSegments(
                sortCommands, selected: selectedSort,
                presentation: presentation, showsLabel: showsSelectedLabels)
            commandToggle(
                isPanes ? .togglePanesSortDirection : .toggleReposSortDirection,
                selected: repoExplorerPrefs.sortDirection == .descending, presentation: presentation
            )
            SidebarToolbarDivider()
            commandToggle(
                isPanes ? .togglePanesShowsPinned : .toggleReposShowsPinned,
                selected: repoExplorerPrefs.showsPinned, presentation: presentation
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var paneGroupingCommand: AppCommand {
        switch repoExplorerPrefs.groupingMode {
        case .repo: .setPanesGroupingRepo
        case .tab: .setPanesGroupingTab
        case .activity: .setPanesGroupingActivity
        }
    }

    private func commandSegments(
        _ commands: [AppCommand], selected: AppCommand?,
        presentation: RepoExplorerToolbarCommandPresentation, showsLabel: Bool
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
            showsSelectedLabel: showsLabel,
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
        case .setPanesGroupingActivity: "repoSidebarGroupingSegment.activity"
        default: "sidebarOrganization.\(command.rawValue)"
        }
    }

    private func isSortDirectionCommand(_ command: AppCommand) -> Bool {
        command == .toggleReposSortDirection || command == .togglePanesSortDirection
    }

    private func commandToggle(
        _ command: AppCommand, selected: Bool, presentation: RepoExplorerToolbarCommandPresentation
    ) -> some View {
        commandSegments(
            [command], selected: selected ? command : nil,
            presentation: presentation, showsLabel: false)
    }
}
