import SwiftUI

enum WorkspaceEmptyStateLayout {
    static func recentColumnCount(for availableWidth: CGFloat) -> Int {
        if availableWidth >= AppStyles.Welcome.launcherWideBreakpoint {
            return AppStyles.Welcome.recentsColumnCountWide
        }
        if availableWidth < AppStyles.Welcome.launcherNarrowBreakpoint {
            return AppStyles.Welcome.recentsColumnCountNarrow
        }
        return AppStyles.Welcome.recentsColumnCount
    }

    static func visibleRecentCardLimit(for _: CGFloat) -> Int { 6 }

    static func recentSectionWidth(for _: CGFloat) -> CGFloat { contentColumnWidth }

    static let contentColumnWidth: CGFloat =
        AppStyles.Welcome.teachingColumnWidth
        + AppStyles.Welcome.contentColumnsGap
        + AppStyles.Welcome.previewWidth

    static func recentCardWidth(forColumns columns: Int) -> CGFloat {
        let count = max(columns, 1)
        let totalGaps = AppStyles.Welcome.recentCardGap * CGFloat(count - 1)
        let raw = (contentColumnWidth - totalGaps) / CGFloat(count)
        return max(raw, AppStyles.Welcome.recentCardMinWidth)
    }

    static func recentGridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let count = recentColumnCount(for: availableWidth)
        let cardWidth = recentCardWidth(forColumns: count)
        return Array(
            repeating: GridItem(
                .fixed(cardWidth),
                spacing: AppStyles.Welcome.recentCardGap,
                alignment: .top
            ),
            count: count
        )
    }
}

struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    var body: some View {
        Group {
            switch model.kind {
            case .noFolders:
                VStack(spacing: 0) {
                    Spacer()
                    folderIntakeBody
                    Spacer()
                }
                .id("noFolders")
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .scanning:
                VStack(spacing: 0) {
                    Spacer()
                    scanningBody
                    Spacer()
                }
                .id("scanning")
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .scanEmpty:
                VStack(spacing: 0) {
                    Spacer()
                    scanEmptyBody
                    Spacer()
                }
                .id("scanEmpty")
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .launcher:
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        launcherBody(
                            availableWidth: max(
                                geometry.size.width - (AppStyles.Welcome.pageHorizontalPadding * 2),
                                0
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppStyles.Welcome.pageHorizontalPadding)
                        .padding(.vertical, AppStyles.Welcome.pageVerticalPadding)
                    }
                }
                .id("launcher")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.kind)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var folderIntakeBody: some View {
        HStack(alignment: .center, spacing: 56) {
            WelcomeSidebarIllustration()

            VStack(alignment: .leading, spacing: 20) {
                AppLogoView(size: 96)

                Text("Welcome to AgentStudio")
                    .font(.system(size: AppStyles.Welcome.titleFontSize, weight: .semibold))

                Text("The terminal IDE built for coding agents.")
                    .font(.system(size: AppStyles.Welcome.bodyFontSize))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Button(LocalActionSpec.chooseFolderToScan.actionSpec.label) {
                        onAddFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("AgentStudio watches the folder and discovers your repos automatically.")
                        .font(.system(size: AppStyles.General.Typography.textXs))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
            }
        }
    }

    private var scanningBody: some View {
        VStack(spacing: AppStyles.Welcome.sectionSpacing) {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.35)

                Text("Scanning \(scanningFolderDisplayName)")
                    .font(.system(size: AppStyles.General.Typography.text2xl, weight: .semibold))

                Text("Looking for git folders in the folder you selected.")
                    .font(.system(size: AppStyles.Welcome.bodyFontSize))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            scanningCallout
        }
        .padding(.horizontal, 24)
    }

    private var scanningCallout: some View {
        QuickActionsCallout(header: "You don't need to wait.")
    }

    private var scanEmptyBody: some View {
        VStack(spacing: AppStyles.Welcome.sectionSpacing) {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: AppStyles.General.Typography.text2xl, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("No git folders found")
                    .font(.system(size: AppStyles.General.Typography.text2xl, weight: .semibold))

                Text(emptyFolderMessage)
                    .font(.system(size: AppStyles.Welcome.bodyFontSize))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            Button("Choose Another Folder to Scan…") {
                onAddFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            QuickActionsCallout(header: "You can still keep moving.")
        }
        .padding(.horizontal, 24)
    }

    private var scanningFolderDisplayName: String {
        guard let path = model.scanningFolderPath else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fullPath = path.path
        if fullPath.hasPrefix(home) {
            return "~" + fullPath.dropFirst(home.count)
        }
        return fullPath
    }

    private var emptyFolderDisplayName: String {
        guard let path = model.emptyFolderPath else { return "this folder" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fullPath = path.path
        if fullPath.hasPrefix(home) {
            return "~" + fullPath.dropFirst(home.count)
        }
        return fullPath
    }

    private var emptyFolderMessage: String {
        "Nothing under \(emptyFolderDisplayName) contains a git repository yet. "
            + "AgentStudio will keep watching this folder for future repos."
    }

    private func launcherBody(availableWidth: CGFloat) -> some View {
        let columnCount = WorkspaceEmptyStateLayout.recentColumnCount(for: availableWidth)
        let visibleRecentCards = Array(
            model.recentCards.prefix(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: availableWidth))
        )
        let stacksVertically = availableWidth < AppStyles.Welcome.launcherNarrowBreakpoint

        return VStack(spacing: AppStyles.Welcome.headerToContentGap) {
            WorkspaceHomeHeader(
                title: "Your workspace",
                subtitle: "Jump back in, or start something new."
            )

            VStack(alignment: .leading, spacing: 0) {
                launcherRecentSection(
                    availableWidth: availableWidth,
                    columnCount: columnCount,
                    visibleRecentCards: visibleRecentCards
                )
                .padding(.bottom, AppStyles.Welcome.recentsToHeroGap)

                launcherHeroRow
                    .padding(.bottom, AppStyles.Welcome.heroToCommandPaletteGap)

                launcherCommandPaletteSection(stacksVertically: stacksVertically)
            }
            .frame(
                maxWidth: WorkspaceEmptyStateLayout.contentColumnWidth,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var launcherHeroRow: some View {
        Button {
            CommandDispatcher.shared.dispatch(.showCommandBarRepos)
        } label: {
            HStack(alignment: .center, spacing: AppStyles.Welcome.shortcutTextGap) {
                Text("⌘T")
                    .font(
                        .system(
                            size: AppStyles.Welcome.shortcutKeyFontSize,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(Color.accentColor)
                    .frame(width: AppStyles.Welcome.shortcutKeyColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: AppStyles.Welcome.shortcutTitleBodyGap) {
                    Text("Start a new tab or worktree")
                        .font(.system(size: AppStyles.Welcome.shortcutTitleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Opens the # picker. New Empty Tab is always first.")
                        .font(.system(size: AppStyles.Welcome.shortcutBodyFontSize))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.system(size: AppStyles.General.Typography.textLg, weight: .medium))
                    .foregroundStyle(.primary.opacity(AppStyles.Welcome.heroRowChevronOpacity))
            }
            .padding(.horizontal, AppStyles.Welcome.heroRowInnerHorizontalPadding)
            .padding(.vertical, AppStyles.Welcome.heroRowInnerVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Welcome.heroRowCornerRadius)
                    .fill(Color.white.opacity(AppStyles.Welcome.heroRowFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppStyles.Welcome.heroRowCornerRadius)
                            .stroke(
                                Color.white.opacity(AppStyles.Welcome.heroRowStrokeOpacity),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: AppStyles.Welcome.heroRowCornerRadius))
    }

    @ViewBuilder
    private func launcherCommandPaletteSection(stacksVertically: Bool) -> some View {
        if stacksVertically {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.previewTopGap) {
                launcherCommandPaletteTeaching
                CommandBarEmbeddedPreview()
            }
        } else {
            HStack(alignment: .top, spacing: AppStyles.Welcome.contentColumnsGap) {
                launcherCommandPaletteTeaching
                    .frame(width: AppStyles.Welcome.teachingColumnWidth, alignment: .leading)
                CommandBarEmbeddedPreview()
            }
        }
    }

    private var launcherCommandPaletteTeaching: some View {
        Button {
            CommandDispatcher.shared.dispatch(.showCommandBarEverything)
        } label: {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.shortcutTitleBodyGap) {
                HStack(alignment: .firstTextBaseline, spacing: AppStyles.Welcome.shortcutTextGap) {
                    Text("⌘P")
                        .font(
                            .system(
                                size: AppStyles.Welcome.shortcutKeyFontSize,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(Color.accentColor)
                        .frame(width: AppStyles.Welcome.shortcutKeyColumnWidth, alignment: .leading)

                    Text("Command palette")
                        .font(.system(size: AppStyles.Welcome.shortcutTitleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text("Scope your search with a prefix.")
                    .font(.system(size: AppStyles.Welcome.shortcutBodyFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppStyles.Welcome.shortcutBodyLeadingInset)
            }
            .padding(.vertical, AppStyles.Welcome.shortcutRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func launcherRecentSection(
        availableWidth: CGFloat,
        columnCount: Int,
        visibleRecentCards: [WorkspaceRecentCardModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyles.Welcome.sectionToContentGap) {
            recentSectionHeader

            if visibleRecentCards.isEmpty {
                WorkspaceRecentPlaceholderCard()
                    .frame(width: WorkspaceEmptyStateLayout.recentCardWidth(forColumns: columnCount))
            } else {
                LazyVGrid(
                    columns: WorkspaceEmptyStateLayout.recentGridColumns(for: availableWidth),
                    alignment: .leading,
                    spacing: AppStyles.Welcome.recentCardGap
                ) {
                    ForEach(visibleRecentCards) { card in
                        WorkspaceRecentCardView(
                            card: card,
                            onOpen: { onOpenRecent(card.target) }
                        )
                    }
                }
                .frame(maxWidth: WorkspaceEmptyStateLayout.contentColumnWidth, alignment: .leading)
            }
        }
    }

    private var recentSectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Recent")
                .font(.system(size: AppStyles.Welcome.sectionLabelFontSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.sectionLabelOpacity))

            if model.showsOpenAll {
                Button(LocalActionSpec.openAllInTabs.actionSpec.label) {
                    onOpenAllRecent()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct WorkspaceHomeHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppStyles.Welcome.titleBodyGap) {
            Text(title)
                .font(.system(size: AppStyles.Welcome.titleFontSize, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: AppStyles.Welcome.bodyFontSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AppStyles.Welcome.headerMaxWidth)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LauncherPreviewScopeRow: View {
    let prefix: String
    let title: String
    let bodyText: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppStyles.CommandBar.Rows.iconSpacing) {
            Text(isSelected ? "▸" : " ")
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(
                    width: AppStyles.Welcome.scopeRowCaretColumnWidth,
                    alignment: .leading
                )

            VStack(alignment: .leading, spacing: AppStyles.Welcome.scopeRowTitleBodyGap) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(prefix)
                        .font(
                            .system(
                                size: AppStyles.General.Typography.textBase,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(Color.primary.opacity(0.88))

                    Text(title)
                        .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.88))
                }

                Text(bodyText)
                    .font(.system(size: AppStyles.Welcome.scopeRowBodySize))
                    .foregroundStyle(Color.primary.opacity(AppStyles.Welcome.scopeRowBodyOpacity))
                    .lineLimit(AppStyles.Welcome.scopeRowBodyLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, AppStyles.CommandBar.Rows.horizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.CommandBar.Rows.selectedRowCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, AppStyles.CommandBar.Rows.selectedRowHorizontalInset)
        )
        .contentShape(Rectangle())
    }
}

struct CommandBarEmbeddedPreview: View {
    struct ScopeEntry: Identifiable {
        let id: String
        let prefix: String
        let title: String
        let body: String
    }

    static let scopeEntries: [ScopeEntry] = [
        ScopeEntry(
            id: "preview-commands",
            prefix: ">",
            title: "Commands",
            body: "Run actions — open, close, toggle"
        ),
        ScopeEntry(
            id: "preview-panes",
            prefix: "$",
            title: "Panes",
            body: "Jump to any open tab or pane"
        ),
        ScopeEntry(
            id: "preview-repos",
            prefix: "#",
            title: "Repos · Worktrees",
            body: "Open a repo, switch a worktree, or start a new one"
        ),
    ]

    private let footerHints: [FooterHint] = [
        FooterHint(id: "enter", key: "↵", label: "Select"),
        FooterHint(id: "move", key: "↑↓", label: "Move", style: .plain),
        FooterHint(id: "dismiss", key: "esc", label: "Dismiss", style: .plain),
    ]

    var body: some View {
        VStack(spacing: 0) {
            CommandBarStatusStrip(mode: .normal, context: .empty)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.rootDividerOpacity)

            HStack(spacing: AppStyles.Welcome.shortcutTextGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.35))
                    .frame(width: 16, height: 16)

                Text("Search or jump to…")
                    .font(.system(size: AppStyles.General.Typography.textBase))
                    .foregroundStyle(.primary.opacity(0.35))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: AppStyles.Welcome.previewSearchRowHeight)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            VStack(spacing: AppStyles.Welcome.scopeRowVerticalSpacing) {
                ForEach(Array(Self.scopeEntries.enumerated()), id: \.element.id) { index, entry in
                    LauncherPreviewScopeRow(
                        prefix: entry.prefix,
                        title: entry.title,
                        bodyText: entry.body,
                        isSelected: index == 0
                    )
                }
            }
            .padding(.vertical, 8)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            CommandBarFooter(hints: footerHints)
        }
        .frame(width: AppStyles.Welcome.previewWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                .fill(Color(nsColor: AppStyles.Shell.TabBar.titlebarBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                        .stroke(Color.white.opacity(AppStyles.Welcome.cardStrokeOpacity), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius))
    }
}

private struct WorkspaceRecentCardView: View {
    let card: WorkspaceRecentCardModel
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            worktreeContent
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
            .fill(
                isHovered
                    ? Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
                    : Color.white.opacity(AppStyles.General.Fill.muted)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
            .stroke(Color.white.opacity(AppStyles.General.Fill.active), lineWidth: 1)
    }

    private var worktreeContent: SidebarWorktreeRowContent {
        let statusChips =
            card.statusChips
            ?? .init(
                branchStatus: .init(
                    isDirty: false,
                    syncState: .unknown,
                    prCount: nil,
                    linesAdded: 0,
                    linesDeleted: 0
                ),
                notificationCount: 0
            )
        let checkoutIconKind = card.checkoutIconKind ?? .gitWorktree
        let iconColorHex = card.iconColorHex ?? ""
        let iconColor = Color(nsColor: NSColor(hex: iconColorHex) ?? .controlAccentColor)
        return SidebarWorktreeRowContent(
            checkoutTitle: card.title,
            branchName: card.detail,
            checkoutIconKind: checkoutIconKind,
            iconColor: iconColor,
            branchStatus: statusChips.branchStatus,
            notificationCount: statusChips.notificationCount
        )
    }
}

private struct WorkspaceRecentPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing + 4) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                Text("No recent worktrees yet")
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                .fill(Color.white.opacity(AppStyles.General.Fill.muted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                .strokeBorder(
                    Color.white.opacity(AppStyles.General.Fill.active),
                    style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                )
        )
    }
}

private struct AppLogoView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.appResources.url(
                forResource: "AppLogoTransparent", withExtension: "svg"),
                let image = NSImage(contentsOf: url)
            {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct QuickActionsCallout: View {
    var header: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose) {
            if let header {
                Text(header)
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose) {
                quickActionButton(key: "⌘T", label: "New tab or worktree") {
                    CommandDispatcher.shared.dispatch(.showCommandBarRepos)
                }
                quickActionButton(key: "⌘P", label: "Command palette") {
                    CommandDispatcher.shared.dispatch(.showCommandBarEverything)
                }
            }
        }
        .padding(AppStyles.Welcome.previewTopGap + 10)
        .frame(maxWidth: AppStyles.Welcome.previewWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                .fill(Color.white.opacity(AppStyles.Welcome.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                        .stroke(Color.white.opacity(AppStyles.Welcome.cardStrokeOpacity), lineWidth: 1)
                )
        )
    }

    private func quickActionButton(key: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(key)
                    .font(.system(size: AppStyles.Welcome.shortcutKeyFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: AppStyles.Welcome.shortcutKeyColumnWidth, alignment: .trailing)

                Text(label)
                    .font(.system(size: AppStyles.Welcome.bodyFontSize))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(minHeight: AppStyles.Welcome.previewResultRowHeight, alignment: .center)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
