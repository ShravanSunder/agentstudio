import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

package enum RepoExplorerCheckoutIconKind {
    case mainCheckout
    case gitWorktree
}

struct RepoExplorerFavoriteControlVisibility: Equatable {
    let showsInlineButton: Bool
    let showsContextMenuAction: Bool

    init(isMainWorktree: Bool) {
        showsInlineButton = isMainWorktree
        showsContextMenuAction = isMainWorktree
    }
}

struct RepoExplorerWorktreeRowContent: View {
    let octiconLoader: OcticonLoader
    let checkoutTitle: String
    let branchName: String
    var placementText = ""
    let checkoutIconKind: RepoExplorerCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let showsFavoriteControl: Bool
    var isFavorite = false
    var favoriteCommandPresentation: RepoExplorerPresentedCommand?
    var onToggleFavorite: () -> Void = {}

    static func favoriteAccessibilityLabel(isFavorite: Bool) -> String {
        favoriteActionSpec(isFavorite: isFavorite).label
    }

    static func favoriteHelpText(isFavorite: Bool) -> String {
        favoriteActionSpec(isFavorite: isFavorite).helpText
    }

    static func favoriteActionSpec(isFavorite: Bool) -> AppCommandSpec {
        (isFavorite ? AppCommand.removeRepoFavorite : AppCommand.addRepoFavorite).definition
    }

    static func diffChipDetail(branchStatus: GitBranchStatus) -> SidebarDiffChip.WorkingTreeDetail? {
        SidebarGitStatusChips.diffDetail(branchStatus: branchStatus)
    }

    static func shouldShowDiffChip(branchStatus: GitBranchStatus) -> Bool {
        diffChipDetail(branchStatus: branchStatus) != nil
    }

    static func shouldShowSyncChip(branchStatus: GitBranchStatus) -> Bool {
        SidebarGitStatusChips.showsSync(branchStatus: branchStatus)
    }

    static func shouldShowPullRequestChip(branchStatus: GitBranchStatus) -> Bool {
        SidebarGitStatusChips.showsPendingPullRequestFacts(branchStatus: branchStatus)
            || (branchStatus.prCount ?? 0) > 0 && !branchStatus.pullRequestDataUnavailable
    }

    private var hasStatusMetadata: Bool {
        Self.shouldShowDiffChip(branchStatus: branchStatus)
            || Self.shouldShowSyncChip(branchStatus: branchStatus)
            || Self.shouldShowPullRequestChip(branchStatus: branchStatus)
    }

    var body: some View {
        VStack(alignment: .sidebarTextColumn, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
                checkoutTypeIcon
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                Text(checkoutTitle)
                    .font(
                        .system(
                            size: AppStyles.General.Typography.textBase,
                            weight: checkoutIconKind == .mainCheckout ? .medium : .regular)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsFavoriteControl,
                    let favoriteCommandPresentation
                {
                    let favoriteActionSpec = favoriteCommandPresentation.commandSpec
                    Button(action: onToggleFavorite) {
                        favoriteActionSpec.icon.swiftUIImage(
                            loader: octiconLoader,
                            size: AppStyles.General.Icon.compact
                        )
                        .foregroundStyle(isFavorite ? iconColor : .secondary)
                        .frame(
                            width: AppStyles.General.Button.compact,
                            height: AppStyles.General.Button.compact
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(favoriteActionSpec.label)
                    .controlHelp(favoriteActionSpec.controlTooltipRenderValue())
                    .disabled(!favoriteCommandPresentation.isEnabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarIconLineTextColumnGuide()

            SidebarMetadataLine(
                icon: .octicon(name: "octicon-git-branch", loader: octiconLoader),
                text: branchName
            )

            if !placementText.isEmpty {
                SidebarMetadataLine(
                    icon: .systemName("square.split.2x1"),
                    text: placementText
                )
            }

            if hasStatusMetadata {
                HStack(spacing: AppStyles.Shell.Sidebar.chipRowSpacing) {
                    if SidebarGitStatusChips.hasContent(branchStatus: branchStatus) {
                        SidebarGitStatusChips(branchStatus: branchStatus, octiconLoader: octiconLoader)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sidebarChipRowTextColumnGuide()
                .sidebarPendingPullRequestIndicator(
                    isVisible: SidebarGitStatusChips.showsPendingPullRequestFacts(
                        branchStatus: branchStatus
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var checkoutTypeIcon: some View {
        let checkoutTypeSize = AppStyles.Shell.Sidebar.worktreeIconSize
        switch checkoutIconKind {
        case .mainCheckout:
            OcticonImage(name: "octicon-star-fill", size: checkoutTypeSize, loader: octiconLoader)
                .foregroundStyle(iconColor)
        case .gitWorktree:
            OcticonImage(name: "octicon-git-worktree", size: checkoutTypeSize, loader: octiconLoader)
                .foregroundStyle(iconColor)
                .rotationEffect(.degrees(180))
        }
    }
}

package struct RepoExplorerWorktreeRow: View {
    let octiconLoader: OcticonLoader
    let worktree: Worktree
    let checkoutTitle: String
    let branchName: String
    var placementText = ""
    let checkoutIconKind: RepoExplorerCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    var bridgeCommandResolution: BridgePaneCommandResolution = .create
    var isFavorite = false
    let commandPresentation: RepoExplorerWorktreeCommandPresentation
    var panePresentations: [RepoExplorerPanePresentation] = []
    var onToggleFavorite: () -> Void = {}
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onReview: () -> Void
    let onOpenFiles: () -> Void
    var onOpenReviewInNewTab: () -> Void = {}
    var onOpenFilesInNewTab: () -> Void = {}
    let onOpenInPane: () -> Void
    var onFocusPane: (UUID) -> Void = { _ in }
    static let rowChromePolicy = SidebarRowShell<RepoExplorerWorktreeRowContent>.chromePolicy

    @State private var isHovering = false

    package init(
        octiconLoader: OcticonLoader,
        worktree: Worktree,
        checkoutTitle: String,
        branchName: String,
        placementText: String = "",
        checkoutIconKind: RepoExplorerCheckoutIconKind,
        iconColor: Color,
        branchStatus: GitBranchStatus,
        bridgeCommandResolution: BridgePaneCommandResolution = .create,
        isFavorite: Bool = false,
        commandPresentation: RepoExplorerWorktreeCommandPresentation,
        panePresentations: [RepoExplorerPanePresentation] = [],
        onToggleFavorite: @escaping () -> Void = {},
        onOpen: @escaping () -> Void,
        onOpenNew: @escaping () -> Void,
        onReview: @escaping () -> Void,
        onOpenFiles: @escaping () -> Void,
        onOpenReviewInNewTab: @escaping () -> Void = {},
        onOpenFilesInNewTab: @escaping () -> Void = {},
        onOpenInPane: @escaping () -> Void,
        onFocusPane: @escaping (UUID) -> Void = { _ in }
    ) {
        self.octiconLoader = octiconLoader
        self.worktree = worktree
        self.checkoutTitle = checkoutTitle
        self.branchName = branchName
        self.placementText = placementText
        self.checkoutIconKind = checkoutIconKind
        self.iconColor = iconColor
        self.branchStatus = branchStatus
        self.bridgeCommandResolution = bridgeCommandResolution
        self.isFavorite = isFavorite
        self.commandPresentation = commandPresentation
        self.panePresentations = panePresentations
        self.onToggleFavorite = onToggleFavorite
        self.onOpen = onOpen
        self.onOpenNew = onOpenNew
        self.onReview = onReview
        self.onOpenFiles = onOpenFiles
        self.onOpenReviewInNewTab = onOpenReviewInNewTab
        self.onOpenFilesInNewTab = onOpenFilesInNewTab
        self.onOpenInPane = onOpenInPane
        self.onFocusPane = onFocusPane
    }

    package var body: some View {
        let favoriteControlVisibility = RepoExplorerFavoriteControlVisibility(
            isMainWorktree: worktree.isMainWorktree
        )
        let favoriteCommand = isFavorite ? AppCommand.removeRepoFavorite : AppCommand.addRepoFavorite
        let inlineOpenWorktree = commandPresentation.inlineCommand(.openWorktree)
        let inlineFavorite = commandPresentation.inlineCommand(favoriteCommand)

        SidebarRowShell(isHovering: isHovering) {
            RepoExplorerWorktreeRowContent(
                octiconLoader: octiconLoader,
                checkoutTitle: checkoutTitle,
                branchName: branchName,
                placementText: placementText,
                checkoutIconKind: checkoutIconKind,
                iconColor: iconColor,
                branchStatus: branchStatus,
                showsFavoriteControl: favoriteControlVisibility.showsInlineButton,
                isFavorite: isFavorite,
                favoriteCommandPresentation: inlineFavorite,
                onToggleFavorite: onToggleFavorite
            )
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            guard inlineOpenWorktree?.isEnabled == true else { return }
            onOpen()
        }
        .contextMenu {
            if hasNewTabCommands {
                Menu {
                    if let openNewTerminal = commandPresentation.contextMenuCommand(.openNewTerminalInTab) {
                        Button {
                            onOpenNew()
                        } label: {
                            worktreeContextMenuLabel(for: openNewTerminal)
                        }
                        .disabled(!openNewTerminal.isEnabled)
                    }

                    if let openReviewInNewTab =
                        commandPresentation.contextMenuCommand(.openBridgeReviewInNewTab)
                    {
                        Button {
                            onOpenReviewInNewTab()
                        } label: {
                            worktreeContextMenuLabel(for: openReviewInNewTab)
                        }
                        .disabled(!openReviewInNewTab.isEnabled)
                    }

                    if let openFilesInNewTab =
                        commandPresentation.contextMenuCommand(.openBridgeFilesInNewTab)
                    {
                        Button {
                            onOpenFilesInNewTab()
                        } label: {
                            worktreeContextMenuLabel(for: openFilesInNewTab)
                        }
                        .disabled(!openFilesInNewTab.isEnabled)
                    }
                } label: {
                    menuLabel(actionSpec: LocalActionSpec.createNewInTab.actionSpec)
                }
            }

            if hasCurrentTabCommands {
                Menu {
                    if let openWorktreeInPane = commandPresentation.contextMenuCommand(.openWorktreeInPane) {
                        Button {
                            onOpenInPane()
                        } label: {
                            worktreeContextMenuLabel(for: openWorktreeInPane)
                        }
                        .disabled(!openWorktreeInPane.isEnabled)
                    }

                    if let showBridgeReview = commandPresentation.contextMenuCommand(.showBridgeReview) {
                        Button {
                            onReview()
                        } label: {
                            worktreeContextMenuLabel(for: showBridgeReview)
                        }
                        .disabled(!showBridgeReview.isEnabled)
                    }

                    if let showBridgeFiles = commandPresentation.contextMenuCommand(.showBridgeFiles) {
                        Button {
                            onOpenFiles()
                        } label: {
                            worktreeContextMenuLabel(for: showBridgeFiles)
                        }
                        .disabled(!showBridgeFiles.isEnabled)
                    }
                } label: {
                    menuLabel(actionSpec: LocalActionSpec.createNewInPane.actionSpec)
                }
            }

            if !panePresentations.isEmpty {
                Menu(LocalActionSpec.goToPane.actionSpec.label) {
                    RepoExplorerPaneDestinationMenuContent(
                        presentations: panePresentations,
                        onFocusPane: onFocusPane
                    )
                }
            }

            Divider()

            if favoriteControlVisibility.showsContextMenuAction,
                let favoritePresentation = commandPresentation.contextMenuCommand(favoriteCommand)
            {
                let favoriteActionSpec = favoritePresentation.commandSpec
                Button {
                    onToggleFavorite()
                } label: {
                    HStack {
                        favoriteActionSpec.icon.swiftUIImage(loader: octiconLoader)
                        Text(favoriteActionSpec.label)
                    }
                }
                .disabled(!favoritePresentation.isEnabled)
            }

            Menu {
                Button {
                    openInCursor()
                } label: {
                    menuLabel(actionSpec: LocalActionSpec.openInCursor.actionSpec)
                }

                Button {
                    openInVSCode()
                } label: {
                    menuLabel(actionSpec: LocalActionSpec.openInVSCode.actionSpec)
                }
            } label: {
                menuLabel(actionSpec: LocalActionSpec.openInEditorMenu.actionSpec)
            }

            Divider()

            Button {
                PathActions.revealInFinder(worktree.path)
            } label: {
                menuLabel(actionSpec: LocalActionSpec.revealInFinder.actionSpec)
            }

            Button {
                PathActions.copyPath(worktree.path)
            } label: {
                menuLabel(actionSpec: LocalActionSpec.copyPath.actionSpec)
            }
        }
    }

    private var hasCurrentTabCommands: Bool {
        commandPresentation.contextMenuCommand(.openWorktreeInPane) != nil
            || commandPresentation.contextMenuCommand(.showBridgeReview) != nil
            || commandPresentation.contextMenuCommand(.showBridgeFiles) != nil
    }

    private var hasNewTabCommands: Bool {
        commandPresentation.contextMenuCommand(.openNewTerminalInTab) != nil
            || commandPresentation.contextMenuCommand(.openBridgeReviewInNewTab) != nil
            || commandPresentation.contextMenuCommand(.openBridgeFilesInNewTab) != nil
    }

    private func openInCursor() {
        ExternalWorkspaceOpener.openInCursor(worktree.path)
    }

    private func openInVSCode() {
        ExternalWorkspaceOpener.openInVSCode(worktree.path)
    }

    @ViewBuilder
    private func worktreeContextMenuLabel(for command: RepoExplorerPresentedCommand) -> some View {
        menuLabel(
            actionSpec: command.commandSpec.actionSpec,
            labelOverride: RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: command.command)
        )
    }

    @ViewBuilder
    private func menuLabel(actionSpec: ActionSpec, labelOverride: String? = nil) -> some View {
        let label = labelOverride ?? actionSpec.label
        switch actionSpec.icon {
        case .system(let systemSymbol):
            Label(label, systemImage: systemSymbol.rawValue)
        case .octicon(let octiconSymbol):
            if let image = octiconLoader.image(named: octiconSymbol.rawValue) {
                Label {
                    Text(label)
                } icon: {
                    Image(nsImage: image)
                }
            } else {
                Label(label, systemImage: "questionmark.square.dashed")
            }
        }
    }
}
