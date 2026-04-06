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
        VStack(alignment: .leading, spacing: AppStyle.sidebarRowContentSpacing) {
            HStack(spacing: AppStyle.spacingTight) {
                checkoutTypeIcon
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text(checkoutTitle)
                    .font(
                        .system(size: AppStyle.textBase, weight: checkoutIconKind == .mainCheckout ? .medium : .regular)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppStyle.spacingTight) {
                OcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text(branchName)
                    .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppStyle.sidebarChipRowSpacing) {
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
            .padding(.leading, AppStyle.sidebarStatusRowLeadingIndent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var checkoutTypeIcon: some View {
        let checkoutTypeSize = AppStyle.textBase
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
        .padding(.vertical, AppStyle.sidebarRowVerticalInset)
        .padding(.horizontal, AppStyle.spacingTight / 2)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                .fill(isHovering ? Color.accentColor.opacity(AppStyle.sidebarRowHoverOpacity) : Color.clear)
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
                menuLabel(presentation: LocalActionPresentation.openInNewTab.presentation)
            }

            Button {
                onOpenInPane()
            } label: {
                menuLabel(presentation: LocalActionPresentation.openInPaneSplit.presentation)
            }

            Divider()

            Button {
                onOpen()
            } label: {
                menuLabel(presentation: LocalActionPresentation.goToTerminal.presentation)
            }

            Menu(LocalActionPresentation.openInMenu.presentation.label) {
                Button {
                    openInCursor()
                } label: {
                    menuLabel(presentation: LocalActionPresentation.openInCursor.presentation)
                }

                Button {
                    openInVSCode()
                } label: {
                    menuLabel(presentation: LocalActionPresentation.openInVSCode.presentation)
                }
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
            } label: {
                menuLabel(presentation: LocalActionPresentation.revealInFinder.presentation)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path.path, forType: .string)
            } label: {
                menuLabel(presentation: LocalActionPresentation.copyPath.presentation)
            }

            Divider()

            Menu(LocalActionPresentation.setIconColorMenu.presentation.label) {
                ForEach(SidebarRepoGrouping.colorPresets, id: \.hex) { preset in
                    Button(preset.name) {
                        onSetIconColor(preset.hex)
                    }
                }
                Divider()
                Button(LocalActionPresentation.resetIconColorDefault.presentation.label) {
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
    private func menuLabel(presentation: ActionPresentation) -> some View {
        if let icon = presentation.icon {
            switch icon {
            case .system(let systemName):
                Label(presentation.label, systemImage: systemName)
            case .octicon(let octiconName):
                if let image = OcticonLoader.shared.image(named: octiconName) {
                    Label {
                        Text(presentation.label)
                    } icon: {
                        Image(nsImage: image)
                    }
                } else {
                    Label(presentation.label, systemImage: "questionmark.square.dashed")
                }
            }
        } else {
            Text(presentation.label)
        }
    }
}
