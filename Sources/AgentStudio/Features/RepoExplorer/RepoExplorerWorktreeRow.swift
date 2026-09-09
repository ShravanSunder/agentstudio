import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

package enum RepoExplorerCheckoutIconKind {
    case mainCheckout
    case gitWorktree
}

struct RepoExplorerPinnedControlVisibility: Equatable {
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
    let showsPinnedControl: Bool
    var isPinned = false
    var pinnedCommandPresentation: RepoExplorerPresentedCommand?
    var onTogglePinned: () -> Void = {}

    static func pinnedAccessibilityLabel(isPinned: Bool) -> String {
        pinnedActionSpec(isPinned: isPinned).label
    }

    static func pinnedHelpText(isPinned: Bool) -> String {
        pinnedActionSpec(isPinned: isPinned).helpText
    }

    static func pinnedActionSpec(isPinned: Bool) -> AppCommandSpec {
        (isPinned ? AppCommand.unpinRepo : AppCommand.pinRepo).definition
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

                if showsPinnedControl,
                    let pinnedCommandPresentation
                {
                    let pinnedActionSpec = pinnedCommandPresentation.commandSpec
                    Button(action: onTogglePinned) {
                        pinnedActionSpec.icon.swiftUIImage(
                            loader: octiconLoader,
                            size: AppStyles.General.Icon.compact
                        )
                        .foregroundStyle(isPinned ? iconColor : .secondary)
                        .frame(
                            width: AppStyles.General.Button.compact,
                            height: AppStyles.General.Button.compact
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pinnedActionSpec.label)
                    .controlHelp(pinnedActionSpec.controlTooltipRenderValue())
                    .disabled(!pinnedCommandPresentation.isEnabled)
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
    var isPinned = false
    let commandPresentation: RepoExplorerWorktreeCommandPresentation
    var onTogglePinned: () -> Void = {}
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
        isPinned: Bool = false,
        commandPresentation: RepoExplorerWorktreeCommandPresentation,
        onTogglePinned: @escaping () -> Void = {},
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
        self.isPinned = isPinned
        self.commandPresentation = commandPresentation
        self.onTogglePinned = onTogglePinned
        self.onOpen = onOpen
    }

    package var body: some View {
        let pinnedControlVisibility = RepoExplorerPinnedControlVisibility(
            isMainWorktree: worktree.isMainWorktree
        )
        let pinnedCommand = isPinned ? AppCommand.unpinRepo : AppCommand.pinRepo
        let inlineOpenWorktree = commandPresentation.inlineCommand(.openWorktree)
        let inlinePinned = commandPresentation.inlineCommand(pinnedCommand)

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
                showsPinnedControl: pinnedControlVisibility.showsInlineButton,
                isPinned: isPinned,
                pinnedCommandPresentation: inlinePinned,
                onTogglePinned: onTogglePinned
            )
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            guard inlineOpenWorktree?.isEnabled == true else { return }
            onOpen()
        }
    }
}
