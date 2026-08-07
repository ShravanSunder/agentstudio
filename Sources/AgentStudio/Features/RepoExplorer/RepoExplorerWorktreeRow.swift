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
    let unreadCount: Int
    let showsFavoriteControl: Bool
    var isFavorite = false
    var favoriteCommandPresentation: RepoExplorerPresentedCommand?
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

            HStack(spacing: AppStyles.General.Spacing.tight) {
                OcticonImage(
                    name: "octicon-git-branch",
                    size: AppStyles.Shell.Sidebar.branchIconSize,
                    loader: octiconLoader
                )
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
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: AppStyles.Shell.Sidebar.branchIconSize, weight: .medium))
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
                    octiconLoader: octiconLoader,
                    linesAdded: lineDiffCounts.added,
                    linesDeleted: lineDiffCounts.deleted,
                    showsDirtyIndicator: branchStatus.isDirty,
                    isMuted: lineDiffCounts.added == 0 && lineDiffCounts.deleted == 0
                )

                SidebarStatusSyncChip(
                    octiconLoader: octiconLoader,
                    aheadText: syncCounts.ahead,
                    behindText: syncCounts.behind,
                    hasSyncSignal: hasSyncSignal
                )

                SidebarChip(
                    iconAsset: "octicon-git-pull-request",
                    octiconLoader: octiconLoader,
                    text: "\(branchStatus.prCount ?? 0)",
                    style: (branchStatus.prCount ?? 0) > 0 ? .accent(iconColor) : .neutral
                )

                if Self.shouldShowUnreadPill(unreadCount: unreadCount) {
                    Button(action: onUnreadPillTap) {
                        SidebarChip(
                            iconAsset: "octicon-bell",
                            octiconLoader: octiconLoader,
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
    let unreadCount: Int
    var bridgeCommandResolution: BridgePaneCommandResolution = .create
    var isFavorite = false
    let commandPresentation: RepoExplorerWorktreeCommandPresentation
    var panePresentations: [RepoExplorerPanePresentation] = []
    var onToggleFavorite: () -> Void = {}
    var onUnreadPillTap: () -> Void = {}
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
        unreadCount: Int,
        bridgeCommandResolution: BridgePaneCommandResolution = .create,
        isFavorite: Bool = false,
        commandPresentation: RepoExplorerWorktreeCommandPresentation,
        panePresentations: [RepoExplorerPanePresentation] = [],
        onToggleFavorite: @escaping () -> Void = {},
        onUnreadPillTap: @escaping () -> Void = {},
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
        self.unreadCount = unreadCount
        self.bridgeCommandResolution = bridgeCommandResolution
        self.isFavorite = isFavorite
        self.commandPresentation = commandPresentation
        self.panePresentations = panePresentations
        self.onToggleFavorite = onToggleFavorite
        self.onUnreadPillTap = onUnreadPillTap
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
                unreadCount: unreadCount,
                showsFavoriteControl: favoriteControlVisibility.showsInlineButton,
                isFavorite: isFavorite,
                favoriteCommandPresentation: inlineFavorite,
                onToggleFavorite: onToggleFavorite,
                onUnreadPillTap: onUnreadPillTap
            )
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            guard inlineOpenWorktree?.isEnabled == true else { return }
            onOpen()
        }
        .contextMenu {
            Menu {
                if hasCurrentTabCommands {
                    Menu {
                        if let openWorktreeInPane = commandPresentation.contextMenuCommand(.openWorktreeInPane) {
                            Button {
                                onOpenInPane()
                            } label: {
                                menuLabel(actionSpec: openWorktreeInPane.commandSpec.actionSpec)
                            }
                            .disabled(!openWorktreeInPane.isEnabled)
                        }

                        if let showBridgeReview = commandPresentation.contextMenuCommand(.showBridgeReview) {
                            Button {
                                onReview()
                            } label: {
                                menuLabel(actionSpec: showBridgeReview.commandSpec.actionSpec)
                            }
                            .disabled(!showBridgeReview.isEnabled)
                        }

                        if let showBridgeFiles = commandPresentation.contextMenuCommand(.showBridgeFiles) {
                            Button {
                                onOpenFiles()
                            } label: {
                                menuLabel(actionSpec: showBridgeFiles.commandSpec.actionSpec)
                            }
                            .disabled(!showBridgeFiles.isEnabled)
                        }
                    } label: {
                        menuLabel(actionSpec: LocalActionSpec.openInCurrentTabMenu.actionSpec)
                    }
                }

                if hasNewTabCommands {
                    Menu {
                        if let openNewTerminal = commandPresentation.contextMenuCommand(.openNewTerminalInTab) {
                            Button {
                                onOpenNew()
                            } label: {
                                menuLabel(actionSpec: openNewTerminal.commandSpec.actionSpec)
                            }
                            .disabled(!openNewTerminal.isEnabled)
                        }

                        if let openReviewInNewTab =
                            commandPresentation.contextMenuCommand(.openBridgeReviewInNewTab)
                        {
                            Button {
                                onOpenReviewInNewTab()
                            } label: {
                                menuLabel(actionSpec: openReviewInNewTab.commandSpec.actionSpec)
                            }
                            .disabled(!openReviewInNewTab.isEnabled)
                        }

                        if let openFilesInNewTab =
                            commandPresentation.contextMenuCommand(.openBridgeFilesInNewTab)
                        {
                            Button {
                                onOpenFilesInNewTab()
                            } label: {
                                menuLabel(actionSpec: openFilesInNewTab.commandSpec.actionSpec)
                            }
                            .disabled(!openFilesInNewTab.isEnabled)
                        }
                    } label: {
                        menuLabel(actionSpec: LocalActionSpec.openInNewTabMenu.actionSpec)
                    }
                }
            } label: {
                menuLabel(actionSpec: LocalActionSpec.createNew.actionSpec)
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
    private func menuLabel(actionSpec: ActionSpec) -> some View {
        switch actionSpec.icon {
        case .system(let systemSymbol):
            Label(actionSpec.label, systemImage: systemSymbol.rawValue)
        case .octicon(let octiconSymbol):
            if let image = octiconLoader.image(named: octiconSymbol.rawValue) {
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
