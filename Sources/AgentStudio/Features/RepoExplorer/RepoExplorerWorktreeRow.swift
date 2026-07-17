import AppKit
import SwiftUI

enum RepoExplorerCheckoutIconKind {
    case mainCheckout
    case gitWorktree
}

struct RepoExplorerWorktreeRowContent: View {
    let checkoutTitle: String
    let branchName: String
    let checkoutIconKind: RepoExplorerCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let unreadCount: Int
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
    let checkoutIconKind: RepoExplorerCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let unreadCount: Int
    var bridgeCommandResolution: BridgePaneCommandResolution = .create
    var onUnreadPillTap: () -> Void = {}
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onReview: () -> Void
    let onOpenFiles: () -> Void
    var onOpenReviewInNewTab: () -> Void = {}
    var onOpenFilesInNewTab: () -> Void = {}
    let onOpenInPane: () -> Void
    static let rowChromePolicy = SidebarRowShell<RepoExplorerWorktreeRowContent>.chromePolicy

    @State private var isHovering = false

    var body: some View {
        SidebarRowShell(isHovering: isHovering) {
            RepoExplorerWorktreeRowContent(
                checkoutTitle: checkoutTitle,
                branchName: branchName,
                checkoutIconKind: checkoutIconKind,
                iconColor: iconColor,
                branchStatus: branchStatus,
                unreadCount: unreadCount,
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
                onReview()
            } label: {
                menuLabel(
                    actionSpec: contextualBridgeActionSpec(
                        command: .showBridgeReview,
                        surface: .review
                    )
                )
            }

            Button {
                onOpenFiles()
            } label: {
                menuLabel(
                    actionSpec: contextualBridgeActionSpec(
                        command: .showBridgeFiles,
                        surface: .file
                    )
                )
            }

            Button {
                onOpenReviewInNewTab()
            } label: {
                menuLabel(actionSpec: AppCommand.openBridgeReviewInNewTab.definition.actionSpec)
            }

            Button {
                onOpenFilesInNewTab()
            } label: {
                menuLabel(actionSpec: AppCommand.openBridgeFilesInNewTab.definition.actionSpec)
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

    private func contextualBridgeActionSpec(
        command: AppCommand,
        surface: BridgeProductSurface
    ) -> ActionSpec {
        let definition = command.definition
        return ActionSpec(
            label: bridgeCommandResolution.contextualLabel(for: surface),
            helpText: definition.helpText,
            icon: definition.icon
        )
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
