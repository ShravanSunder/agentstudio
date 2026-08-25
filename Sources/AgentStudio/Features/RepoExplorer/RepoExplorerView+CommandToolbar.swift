import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

extension RepoExplorerView {
    @ViewBuilder
    var repoToolbarRow: some View {
        let nextSortOrder = repoExplorerPrefs.sortOrder.toggled
        let commandPresentation = RepoExplorerToolbarCommandPresentation.resolve(
            nextSortOrder: nextSortOrder,
            snapshot: commandPresentationSnapshot
        )
        let groupingAction = LocalActionSpec.groupRepoExplorerWorktrees.actionSpec
        let presentedGroupingModes = RepoExplorerGroupingMode.allCases.filter { groupingMode in
            commandPresentation.command(groupingCommand(for: groupingMode)) != nil
        }

        HStack(spacing: AppStyles.General.Spacing.standard) {
            Spacer(minLength: 0)

            if let sortCommand = commandPresentation.command(.setRepoSidebarSortOrder) {
                SidebarToolbarSortButton(
                    sortValue: repoExplorerPrefs.sortOrder,
                    isReversed: repoExplorerPrefs.sortOrder == .descending,
                    label: sortCommand.commandSpec.label,
                    accessibilityIdentifier: "repoSidebarSortButton",
                    tooltipValue: sortCommand.commandSpec.controlTooltipRenderValue(
                        textOverride: "Sort \(repoExplorerPrefs.sortOrder.title.lowercased())"
                    ),
                    icon: {
                        sortCommand.commandSpec.icon.swiftUIImage(
                            loader: octiconLoader,
                            size: AppStyles.General.Icon.compact
                        )
                    },
                    tooltipTarget: RepoSidebarToolbarTooltipTarget.sort,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    frameAccessibilityIdentifier: "repoSidebarSortButtonFrame",
                    onHover: { updateTooltipTarget(.sort, isHovered: $0) },
                    onToggle: { onSetSortOrder(nextSortOrder) }
                )
                .id("repoSidebarSortButton.stable")
                .disabled(!sortCommand.isEnabled)
            }

            if !presentedGroupingModes.isEmpty {
                SidebarToolbarDivider()
                SidebarToolbarGroupingButton(
                    label: groupingAction.label,
                    selectionLabel: repoExplorerPrefs.groupingMode.title,
                    accessibilityIdentifier: "repoSidebarGroupingButton",
                    tooltipValue: groupingAction.controlTooltipRenderValue(
                        provenance: .localAction(rawValue: "groupRepoExplorerWorktrees"),
                        textOverride: "Group"
                    ),
                    isOpen: groupingMenuOpen,
                    tooltipTarget: RepoSidebarToolbarTooltipTarget.grouping,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    frameAccessibilityIdentifier: "repoSidebarGroupingButtonFrame",
                    onHover: { updateTooltipTarget(.grouping, isHovered: $0) },
                    action: { groupingMenuOpen.toggle() }
                )
                .disabled(
                    !presentedGroupingModes.contains { groupingMode in
                        commandPresentation.command(groupingCommand(for: groupingMode))?.isEnabled == true
                    }
                )
                .popover(isPresented: $groupingMenuOpen) {
                    SidebarGroupingPopover(
                        items: presentedGroupingModes,
                        selectedItem: repoExplorerPrefs.groupingMode,
                        icon: { groupingMode in
                            presentedGroupingCommand(
                                for: groupingMode,
                                in: commandPresentation
                            ).commandSpec.icon.swiftUIImage(
                                loader: octiconLoader,
                                size: AppStyles.General.Icon.compact
                            )
                        },
                        label: { $0.title },
                        onSelect: { candidate in
                            let command = groupingCommand(for: candidate)
                            guard commandPresentation.command(command)?.isEnabled == true else {
                                return
                            }
                            commandDispatcher.dispatch(command)
                            groupingMenuOpen = false
                        },
                        onDismiss: { groupingMenuOpen = false }
                    )
                }
            }
        }
        .background(
            AccessibilityLabelBridge(
                identifier: "repoSidebarToolbarRow",
                label: "Repo toolbar row"
            )
        )
    }

    func presentedGroupingCommand(
        for mode: RepoExplorerGroupingMode,
        in commandPresentation: RepoExplorerToolbarCommandPresentation
    ) -> RepoExplorerPresentedCommand {
        guard let presentedCommand = commandPresentation.command(groupingCommand(for: mode)) else {
            preconditionFailure("Grouping popover received a presentation-denied mode")
        }
        return presentedCommand
    }

    func groupingCommand(for mode: RepoExplorerGroupingMode) -> AppCommand {
        switch mode {
        case .repo: .setRepoSidebarGroupingRepo
        case .pane: .setRepoSidebarGroupingPane
        case .tab: .setRepoSidebarGroupingTab
        }
    }

    func groupingModeIcon(for mode: RepoExplorerGroupingMode) -> AppEntityIcon {
        switch mode {
        case .repo: AppEntityIcon.repo
        case .pane: AppEntityIcon.pane
        case .tab: AppEntityIcon.tab
        }
    }
}
