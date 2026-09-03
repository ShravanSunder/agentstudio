import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
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
    var showsRepositoryFactStatus = true
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
            || (branchStatus.prCount ?? 0) > 0
    }

    private var hasStatusMetadata: Bool {
        RepoExplorerWorktreeStatusPresentation.reservesStatusLine(branchStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
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

            if !branchName.isEmpty {
                HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
                    SidebarMetadataLine(
                        icon: .octicon(name: "octicon-git-branch", loader: octiconLoader),
                        text: branchName
                    )
                    if showsRepositoryFactStatus,
                        RepoExplorerWorktreeStatusPresentation.showsPendingIndicatorInMetadataLine(
                            branchStatus
                        )
                    {
                        SidebarPendingPullRequestIndicator()
                    }
                }
            }

            if !placementText.isEmpty {
                SidebarMetadataLine(
                    icon: .systemName("square.split.2x1"),
                    text: placementText
                )
            }

            if hasStatusMetadata {
                SidebarStatusChipRow(
                    isPendingPullRequestFacts: showsRepositoryFactStatus
                        && RepoExplorerWorktreeStatusPresentation.showsPendingIndicator(branchStatus)
                ) {
                    if showsRepositoryFactStatus,
                        SidebarGitStatusChips.hasContent(branchStatus: branchStatus)
                    {
                        SidebarGitStatusChips(branchStatus: branchStatus, octiconLoader: octiconLoader)
                    }
                }
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
    var showsRepositoryFactStatus = true
    var bridgeCommandResolution: BridgePaneCommandResolution = .create
    var isFavorite = false
    let commandPresentation: RepoExplorerWorktreeCommandPresentation
    var onToggleFavorite: () -> Void = {}
    let onOpen: () -> Void
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
        showsRepositoryFactStatus: Bool = true,
        bridgeCommandResolution: BridgePaneCommandResolution = .create,
        isFavorite: Bool = false,
        commandPresentation: RepoExplorerWorktreeCommandPresentation,
        onToggleFavorite: @escaping () -> Void = {},
        onOpen: @escaping () -> Void
    ) {
        self.octiconLoader = octiconLoader
        self.worktree = worktree
        self.checkoutTitle = checkoutTitle
        self.branchName = branchName
        self.placementText = placementText
        self.checkoutIconKind = checkoutIconKind
        self.iconColor = iconColor
        self.branchStatus = branchStatus
        self.showsRepositoryFactStatus = showsRepositoryFactStatus
        self.bridgeCommandResolution = bridgeCommandResolution
        self.isFavorite = isFavorite
        self.commandPresentation = commandPresentation
        self.onToggleFavorite = onToggleFavorite
        self.onOpen = onOpen
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
                showsRepositoryFactStatus: showsRepositoryFactStatus,
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
    }
}
