import AppKit
import SwiftUI

enum SidebarCheckoutIconKind {
    case mainCheckout
    case gitWorktree
}

struct SidebarWorktreeRowContent: View {
    let checkoutTitle: String
    let branchName: String
    let checkoutIconKind: SidebarCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let notificationCount: Int

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

                SidebarChip(
                    iconAsset: "octicon-bell",
                    text: "\(notificationCount)",
                    style: notificationCount > 0 ? .accent(iconColor) : .neutral
                )
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

struct SidebarWorktreeRow: View {
    let worktree: Worktree
    let checkoutTitle: String
    let branchName: String
    let checkoutIconKind: SidebarCheckoutIconKind
    let iconColor: Color
    let branchStatus: GitBranchStatus
    let notificationCount: Int
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onOpenInPane: () -> Void
    let onSetIconColor: (String?) -> Void

    @State private var isHovering = false

    var body: some View {
        SidebarWorktreeRowContent(
            checkoutTitle: checkoutTitle,
            branchName: branchName,
            checkoutIconKind: checkoutIconKind,
            iconColor: iconColor,
            branchStatus: branchStatus,
            notificationCount: notificationCount
        )
        .padding(.vertical, AppStyles.Shell.Sidebar.rowVerticalInset)
        .padding(.horizontal, AppStyles.General.Spacing.tight / 2)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.bar)
                .fill(isHovering ? Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity) : Color.clear)
        )
        .contentShape(Rectangle())
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
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
            } label: {
                menuLabel(actionSpec: LocalActionSpec.revealInFinder.actionSpec)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path.path, forType: .string)
            } label: {
                menuLabel(actionSpec: LocalActionSpec.copyPath.actionSpec)
            }

            Divider()

            Menu(LocalActionSpec.setIconColorMenu.actionSpec.label) {
                ForEach(RepoPresentationGrouping.colorPresets, id: \.hex) { preset in
                    Button(preset.name) {
                        onSetIconColor(preset.hex)
                    }
                }
                Divider()
                Button(LocalActionSpec.resetIconColorDefault.actionSpec.label) {
                    onSetIconColor(nil)
                }
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
