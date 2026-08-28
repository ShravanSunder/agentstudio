import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

struct RepoExplorerMaterializedRowView: View {
    let row: RepoExplorerMaterializedRow
    let commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot
    let octiconLoader: OcticonLoader
    let onCommandRequest: (RepoExplorerCommandPresentationRequest) -> Void
    let onToggleGroup: (String) -> Void
    let onFocusPane: (UUID) -> Void

    var body: some View {
        content
            .environment(
                \.sidebarRowVerticalInset,
                AppStyles.Shell.Sidebar.nativeRowVerticalInset
            )
            .padding(.leading, row.layout.metrics.leadingInset)
            .padding(.trailing, row.layout.metrics.trailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch row.presentation {
        case .sectionHeader(let kind, let isFirstRow):
            SectionSubheadingLabel(kind.title)
                .padding(.leading, AppStyles.Shell.Sidebar.listRowLeadingInset)
                .padding(.trailing, AppStyles.Components.SectionSubheading.horizontalPadding)
                .padding(.top, isFirstRow ? 0 : AppStyles.Components.SectionSubheading.topPadding)
                .padding(.bottom, AppStyles.Components.SectionSubheading.bottomPadding)
                .accessibilityAddTraits(.isHeader)
        case .loadingSectionHeader(_, let state):
            RepoExplorerLoadingSectionHeaderRow(state: state)
                .padding(.top, AppStyles.General.Spacing.standard)
                .padding(.bottom, AppStyles.General.Spacing.tight)
        case .loadingRepository(_, _, let name, let isStatusUnavailable):
            RepoExplorerLoadingRepoRow(
                repoName: name,
                isStatusUnavailable: isStatusUnavailable
            )
            .allowsHitTesting(false)
        case .groupHeader(let group):
            SidebarRepoGroupHeader(
                isCollapsed: !group.isExpanded,
                octiconLoader: octiconLoader,
                icon: group.icon,
                repoTitle: group.title,
                organizationName: group.organizationName,
                onToggle: { onToggleGroup(group.groupID) },
                trailingContent: {
                    if group.presentsRepositoryActivity,
                        group.repositoryActivityDisposition == .locallyInactive
                            || RepoExplorerRepositoryUpdatePresentation.keepsActivitySlotVisible(
                                group.repositoryFactUpdateProgress
                            ),
                        group.repoIDs.count == 1,
                        let repoID = group.repoIDs.first
                    {
                        repositoryActivityTrailingContent(
                            repoID: repoID,
                            isUpdating: RepoExplorerRepositoryUpdatePresentation.isLoading(
                                group.repositoryFactUpdateProgress
                            )
                        )
                    }
                }
            )
            .padding(.top, AppStyles.Shell.Sidebar.nativeGroupHeaderTopPadding)
            .padding(.bottom, AppStyles.Shell.Sidebar.nativeGroupHeaderBottomPadding)
            .contextMenu {
                if !group.paneDestinations.isEmpty {
                    Menu(LocalActionSpec.goToPane.actionSpec.label) {
                        RepoExplorerPaneDestinationMenuContent(
                            presentations: group.paneDestinations.map {
                                RepoExplorerPanePresentation(destination: $0, label: $0.label)
                            },
                            onFocusPane: onFocusPane
                        )
                    }
                }
                if let path = group.semanticRepoPath {
                    Button(LocalActionSpec.revealInFinder.actionSpec.label) {
                        PathActions.revealInFinder(path)
                    }
                    Button(LocalActionSpec.copyPath.actionSpec.label) {
                        PathActions.copyPath(path)
                    }
                }
            }
        case .worktree(let worktree):
            let isFavorite =
                commandPresentationSnapshot.favoriteStateByRepositoryID[
                    worktree.repo.id
                ] ?? false
            let commandPresentation = RepoExplorerWorktreeCommandPresentation.resolve(
                worktreeId: worktree.worktree.id,
                repoId: worktree.repo.id,
                isFavorite: isFavorite,
                showsFavoriteControl: worktree.isMainCheckout,
                snapshot: commandPresentationSnapshot
            )
            RepoExplorerWorktreeRow(
                octiconLoader: octiconLoader,
                worktree: worktree.worktree,
                checkoutTitle: worktree.checkoutTitle,
                branchName: worktree.branchName,
                placementText: worktree.placementText,
                checkoutIconKind: worktree.isMainCheckout ? .mainCheckout : .gitWorktree,
                iconColor: Color(
                    nsColor: NSColor(hex: worktree.checkoutColorHex)
                        ?? AppStyles.General.Accent.primaryNSColor
                ),
                branchStatus: worktree.branchStatus,
                showsRepositoryFactStatus: worktree.showsRepositoryFactStatus,
                bridgeCommandResolution: worktree.bridgeCommandResolution,
                isFavorite: isFavorite,
                commandPresentation: commandPresentation,
                panePresentations: worktree.paneDestinations.map {
                    RepoExplorerPanePresentation(destination: $0, label: $0.label)
                },
                onToggleFavorite: {
                    dispatch(
                        isFavorite ? .removeRepoFavorite : .addRepoFavorite,
                        surface: .inlineControl,
                        from: commandPresentation
                    )
                },
                onOpen: {
                    dispatch(.openWorktree, surface: .inlineControl, from: commandPresentation)
                },
                onOpenNew: {
                    dispatch(.openNewTerminalInTab, surface: .contextMenu, from: commandPresentation)
                },
                onReview: {
                    dispatch(.showBridgeReview, surface: .contextMenu, from: commandPresentation)
                },
                onOpenFiles: {
                    dispatch(.showBridgeFiles, surface: .contextMenu, from: commandPresentation)
                },
                onOpenReviewInNewTab: {
                    dispatch(.openBridgeReviewInNewTab, surface: .contextMenu, from: commandPresentation)
                },
                onOpenFilesInNewTab: {
                    dispatch(.openBridgeFilesInNewTab, surface: .contextMenu, from: commandPresentation)
                },
                onOpenInPane: {
                    dispatch(.openWorktreeInPane, surface: .contextMenu, from: commandPresentation)
                }
            )
        case .pane(let pane):
            RepoExplorerPaneRow(
                row: pane,
                octiconLoader: octiconLoader,
                onFocus: { onFocusPane(pane.destination.paneId) }
            )
        case .unassociatedPane(let pane):
            RepoExplorerUnassociatedPaneRow(
                primaryText: pane.primaryText,
                secondaryLine: pane.secondaryLine,
                recencyText: pane.recencyText,
                recencyTier: pane.recencyTier,
                isActive: pane.isActive,
                isDrawerPane: pane.isDrawerPane,
                octiconLoader: octiconLoader,
                onFocus: { onFocusPane(pane.destination.paneId) }
            )
        case .topologyFault(let fault):
            RepoExplorerTopologyFaultRow(fault: fault)
        case .unresolved:
            Text("Repository data unavailable")
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func repositoryActivityTrailingContent(repoID: UUID, isUpdating: Bool) -> some View {
        let commandPresentation = RepoExplorerRepositoryCommandPresentation.resolve(
            repoID: repoID,
            snapshot: commandPresentationSnapshot
        )
        let inactivityStatus = ActionSpec(
            label: "Locally inactive",
            helpText: "No repository or worktree has been opened in Agent Studio for 60 days",
            icon: .system(.clock)
        )
        HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
            if isUpdating {
                HStack(spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating")
                }
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Updating repository facts")
            } else {
                HStack(spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
                    inactivityStatus.icon.swiftUIImage(
                        loader: octiconLoader,
                        size: AppStyles.General.Icon.compact
                    )
                    Text(inactivityStatus.label)
                }
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(inactivityStatus.helpText)
                .controlHelp(
                    inactivityStatus.controlTooltipRenderValue(
                        provenance: .localAction(rawValue: "repositoryLocallyInactive")
                    )
                )
            }

            if let commandPresentation {
                let actionSpec = commandPresentation.commandSpec
                Button {
                    onCommandRequest(commandPresentation.request)
                } label: {
                    actionSpec.icon.swiftUIImage(
                        loader: octiconLoader,
                        size: AppStyles.General.Icon.compact
                    )
                    .frame(
                        width: AppStyles.General.Button.compact,
                        height: AppStyles.General.Button.compact
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionSpec.label)
                .controlHelp(actionSpec.controlTooltipRenderValue())
                .disabled(!commandPresentation.isEnabled)
            }
        }
    }

    private func dispatch(
        _ command: AppCommand,
        surface: AppCommandSurface,
        from presentation: RepoExplorerWorktreeCommandPresentation
    ) {
        let presentedCommand =
            surface == .inlineControl
            ? presentation.inlineCommand(command)
            : presentation.contextMenuCommand(command)
        guard let request = presentedCommand?.request else { return }
        onCommandRequest(request)
    }

    static func accessibilityLabel(for row: RepoExplorerMaterializedRow) -> String {
        switch row.presentation {
        case .sectionHeader(let kind, _):
            kind.title
        case .loadingSectionHeader(_, let state):
            switch state {
            case .scanning: "Scanning"
            case .statusUnavailable: "Status unavailable"
            case .mixed: "Scanning; some status unavailable"
            }
        case .loadingRepository(_, _, let name, let isStatusUnavailable):
            isStatusUnavailable ? "\(name), status unavailable" : name
        case .groupHeader(let group):
            [group.title, group.organizationName].compactMap { $0 }.joined(separator: ", ")
        case .worktree(let worktree):
            [worktree.checkoutTitle, worktree.branchName, worktree.placementText]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        case .pane(let pane):
            [
                pane.primaryText,
                pane.secondaryText,
                pane.branchContextText,
                pane.isDrawerPane ? "Drawer" : nil,
                pane.recencyText,
                pane.isActive ? "Active" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        case .unassociatedPane(let pane):
            [
                pane.primaryText,
                pane.secondaryLine?.text,
                pane.isDrawerPane ? "Drawer" : nil,
                pane.recencyText,
                pane.isActive ? "Active" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        case .topologyFault, .unresolved:
            "Repository data unavailable"
        }
    }
}

enum RepoExplorerRepositoryUpdatePresentation {
    static func keepsActivitySlotVisible(_ progress: RepositoryFactUpdateProgress?) -> Bool {
        progress?.phase == .captured || progress?.isLoading == true
    }

    static func isLoading(_ progress: RepositoryFactUpdateProgress?) -> Bool {
        progress?.isLoading == true
    }
}
