import AppKit
import SwiftUI

enum RepoExplorerCheckoutIconKind {
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
    let checkoutTitle: String
    let branchName: String
    var placementText = ""
    let checkoutIconKind: RepoExplorerCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let unreadCount: Int
    let showsFavoriteControl: Bool
    var isFavorite = false
    var onToggleFavorite: () -> Void = {}
    var onUnreadPillTap: () -> Void = {}

    private var syncCounts: (ahead: String, behind: String) {
        switch branchStatus.syncState {
        case .synced:
            return ("0", "0")
        case .ahead(let count):
            return ("\(count)", "0")
        case .behind(let count):
            return ("0", "\(count)")
        case .diverged(let ahead, let behind):
            return ("\(ahead)", "\(behind)")
        case .noUpstream:
            return ("-", "-")
        case .unknown:
            return ("?", "?")
        }
    }

    private var hasSyncSignal: Bool {
        switch branchStatus.syncState {
        case .ahead(let count):
            return count > 0
        case .behind(let count):
            return count > 0
        case .diverged(let ahead, let behind):
            return ahead > 0 || behind > 0
        case .synced, .noUpstream, .unknown:
            return false
        }
    }

    private var lineDiffCounts: (added: Int, deleted: Int) {
        (branchStatus.linesAdded, branchStatus.linesDeleted)
    }

    static func shouldShowUnreadPill(unreadCount: Int) -> Bool {
        unreadCount > 0
    }

    static func favoriteAccessibilityLabel(isFavorite: Bool) -> String {
        favoriteActionSpec(isFavorite: isFavorite).label
    }

    static func favoriteHelpText(isFavorite: Bool) -> String {
        favoriteActionSpec(isFavorite: isFavorite).helpText
    }

    static func favoriteActionSpec(isFavorite: Bool) -> AppCommandSpec {
        (isFavorite ? AppCommand.removeRepoFavorite : AppCommand.addRepoFavorite).definition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
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

                if showsFavoriteControl {
                    let favoriteActionSpec = Self.favoriteActionSpec(isFavorite: isFavorite)
                    Button(action: onToggleFavorite) {
                        favoriteActionSpec.icon.swiftUIImage(size: AppStyles.General.Icon.compact)
                            .foregroundStyle(isFavorite ? iconColor : .secondary)
                            .frame(
                                width: AppStyles.General.Button.compact,
                                height: AppStyles.General.Button.compact
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.favoriteAccessibilityLabel(isFavorite: isFavorite))
                    .help(Self.favoriteHelpText(isFavorite: isFavorite))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppStyles.General.Spacing.tight) {
                OcticonImage(name: "octicon-git-branch", size: AppStyles.Shell.Sidebar.branchIconSize)
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                Text(branchName)
                    .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !placementText.isEmpty {
                HStack(spacing: AppStyles.General.Spacing.tight) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                    Text(placementText)
                        .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: AppStyles.Shell.Sidebar.chipRowSpacing) {
                SidebarDiffChip(
                    linesAdded: lineDiffCounts.added,
                    linesDeleted: lineDiffCounts.deleted,
                    showsDirtyIndicator: branchStatus.isDirty,
                    isMuted: lineDiffCounts.added == 0 && lineDiffCounts.deleted == 0
                )

                SidebarStatusSyncChip(
                    aheadText: syncCounts.ahead,
                    behindText: syncCounts.behind,
                    hasSyncSignal: hasSyncSignal
                )

                SidebarChip(
                    iconAsset: "octicon-git-pull-request",
                    text: "\(branchStatus.prCount ?? 0)",
                    style: (branchStatus.prCount ?? 0) > 0 ? .accent(iconColor) : .neutral
                )

                if Self.shouldShowUnreadPill(unreadCount: unreadCount) {
                    Button(action: onUnreadPillTap) {
                        SidebarChip(
                            iconAsset: "octicon-bell",
                            text: "\(unreadCount)",
                            style: .accent(iconColor)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, AppStyles.Shell.Sidebar.statusRowLeadingIndent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var checkoutTypeIcon: some View {
        let checkoutTypeSize = AppStyles.General.Typography.textBase
        switch checkoutIconKind {
        case .mainCheckout:
            OcticonImage(name: "octicon-star-fill", size: checkoutTypeSize)
                .foregroundStyle(iconColor)
        case .gitWorktree:
            OcticonImage(name: "octicon-git-worktree", size: checkoutTypeSize)
                .foregroundStyle(iconColor)
                .rotationEffect(.degrees(180))
        }
    }
}

struct RepoExplorerWorktreeRow: View {
    let worktree: Worktree
    let checkoutTitle: String
    let branchName: String
    var placementText = ""
    let checkoutIconKind: RepoExplorerCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let unreadCount: Int
    var isFavorite = false
    var onToggleFavorite: () -> Void = {}
    var onUnreadPillTap: () -> Void = {}
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onOpenInPane: () -> Void
    static let rowChromePolicy = SidebarRowShell<RepoExplorerWorktreeRowContent>.chromePolicy

    @State private var isHovering = false

    var body: some View {
        let favoriteControlVisibility = RepoExplorerFavoriteControlVisibility(
            isMainWorktree: worktree.isMainWorktree
        )

        SidebarRowShell(isHovering: isHovering) {
            RepoExplorerWorktreeRowContent(
                checkoutTitle: checkoutTitle,
                branchName: branchName,
                placementText: placementText,
                checkoutIconKind: checkoutIconKind,
                iconColor: iconColor,
                branchStatus: branchStatus,
                unreadCount: unreadCount,
                showsFavoriteControl: favoriteControlVisibility.showsInlineButton,
                isFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite,
                onUnreadPillTap: onUnreadPillTap
            )
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button {
                onOpenNew()
            } label: {
                menuLabel(actionSpec: LocalActionSpec.openInNewTab.actionSpec)
            }

            Button {
                onOpenInPane()
            } label: {
                menuLabel(actionSpec: LocalActionSpec.openInPaneSplit.actionSpec)
            }

            Divider()

            Button {
                onOpen()
            } label: {
                menuLabel(actionSpec: LocalActionSpec.goToTerminal.actionSpec)
            }

            if favoriteControlVisibility.showsContextMenuAction {
                let favoriteActionSpec = RepoExplorerWorktreeRowContent.favoriteActionSpec(isFavorite: isFavorite)
                Button {
                    onToggleFavorite()
                } label: {
                    HStack {
                        favoriteActionSpec.icon.swiftUIImage()
                        Text(favoriteActionSpec.label)
                    }
                }
            }

            Menu(LocalActionSpec.openInMenu.actionSpec.label) {
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

    private func openInCursor() {
        ExternalWorkspaceOpener.openInCursor(worktree.path)
    }

    private func openInVSCode() {
        ExternalWorkspaceOpener.openInVSCode(worktree.path)
    }

    @ViewBuilder
    private func menuLabel(actionSpec: ActionSpec) -> some View {
        switch actionSpec.icon {
        case .system(let systemSymbol):
            Label(actionSpec.label, systemImage: systemSymbol.rawValue)
        case .octicon(let octiconSymbol):
            if let image = OcticonLoader.shared.image(named: octiconSymbol.rawValue) {
                Label {
                    Text(actionSpec.label)
                } icon: {
                    Image(nsImage: image)
                }
            } else {
                Label(actionSpec.label, systemImage: "questionmark.square.dashed")
            }
        }
    }
}
