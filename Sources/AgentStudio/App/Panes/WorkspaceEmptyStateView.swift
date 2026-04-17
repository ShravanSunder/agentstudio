import SwiftUI

enum WorkspaceEmptyStateLayout {
    static let visibleRecentCardLimit: Int = 6
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
                        .padding(.bottom, AppStyles.Welcome.pageVerticalPadding)
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

    private func launcherBody(availableWidth _: CGFloat) -> some View {
        let visibleRecentCards = Array(
            model.recentCards.prefix(WorkspaceEmptyStateLayout.visibleRecentCardLimit)
        )
        let subtitle =
            visibleRecentCards.isEmpty ? "Get started." : "Jump back in, fast."

        return VStack(alignment: .leading, spacing: AppStyles.Welcome.launcherSectionGap) {
            launcherHeader(subtitle: subtitle)

            launcherRecentSection(visibleRecentCards: visibleRecentCards)

            Divider()
                .opacity(AppStyles.Welcome.launcherDividerOpacity)

            launcherShortcutsBlock
        }
        .padding(.top, AppStyles.Welcome.launcherPageTopPadding)
        .frame(maxWidth: AppStyles.Welcome.launcherContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func launcherHeader(subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppStyles.Welcome.titleBodyGap) {
            Text("Your workspace")
                .font(AppStyles.Welcome.Typography.h1)

            Text(subtitle)
                .font(AppStyles.Welcome.Typography.body)
                .foregroundStyle(.secondary)
        }
    }

    private var launcherShortcutsBlock: some View {
        HStack(alignment: .center, spacing: AppStyles.Welcome.launcherShortcutsColumnsGap) {
            CommandBarEmbeddedPreview()

            VStack(alignment: .leading, spacing: AppStyles.Welcome.launcherRowGap) {
                launcherShortcutRow(
                    key: "⌘P",
                    title: "Command palette",
                    subtitle: "Everything in the app, one keypress away.",
                    action: { CommandDispatcher.shared.dispatch(.showCommandBarEverything) }
                )

                launcherShortcutRow(
                    key: "⌘T",
                    title: "New tab or worktree",
                    subtitle: "Opens the # picker. New Empty Tab is always first.",
                    action: { CommandDispatcher.shared.dispatch(.showCommandBarRepos) }
                )

                launcherShortcutRow(
                    keyImage: "folder.badge.plus",
                    title: "Add folder",
                    subtitle: "Scan a new folder for repos.",
                    action: { CommandDispatcher.shared.dispatch(.addFolder) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func launcherShortcutRow(
        key: String? = nil,
        keyImage: String? = nil,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyles.Welcome.launcherShortcutKeyTitleGap) {
                Group {
                    if let keyImage {
                        Image(systemName: keyImage)
                            .font(AppStyles.Welcome.Typography.key)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(key ?? "")
                            .font(AppStyles.Welcome.Typography.key)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: AppStyles.Welcome.launcherShortcutKeyColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppStyles.Welcome.Typography.h3)
                        .foregroundStyle(.primary.opacity(AppStyles.Welcome.TextColor.h3Opacity))

                    Text(subtitle)
                        .font(AppStyles.Welcome.Typography.bodySm)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func launcherRecentSection(
        visibleRecentCards: [WorkspaceRecentCardModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose + 4) {
            recentSectionHeader

            if visibleRecentCards.isEmpty {
                WorkspaceRecentPlaceholderCard()
            } else {
                VStack(spacing: AppStyles.Welcome.recentCardGap) {
                    ForEach(visibleRecentCards) { card in
                        WorkspaceRecentCardView(
                            card: card,
                            onOpen: { onOpenRecent(card.target) }
                        )
                    }
                }
            }
        }
    }

    private var recentSectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Recent")
                .font(AppStyles.Welcome.Typography.h2)
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.TextColor.h2Opacity))

            if model.showsOpenAll {
                Button(LocalActionSpec.openAllInTabs.actionSpec.label) {
                    onOpenAllRecent()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                .font(AppStyles.Welcome.Typography.h3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(prefix)
                        .font(AppStyles.Welcome.Typography.key)
                        .foregroundStyle(Color.primary.opacity(AppStyles.Welcome.TextColor.h3Opacity))

                    Text(title)
                        .font(AppStyles.Welcome.Typography.h3)
                        .foregroundStyle(Color.primary.opacity(AppStyles.Welcome.TextColor.h3Opacity))
                }

                Text(bodyText)
                    .font(AppStyles.Welcome.Typography.bodySm)
                    .foregroundStyle(
                        Color.primary.opacity(AppStyles.Welcome.launcherPreviewSubtitleOpacity)
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, AppStyles.CommandBar.Rows.horizontalPadding)
        .padding(.vertical, 5)
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

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(AppStyles.Welcome.Typography.h3)
                    .foregroundStyle(.primary.opacity(0.35))
                    .frame(width: 16, height: 16)

                Text("Search or jump to…")
                    .font(AppStyles.Welcome.Typography.h3)
                    .foregroundStyle(.primary.opacity(0.35))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: AppStyles.Welcome.previewSearchRowHeight)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            VStack(spacing: 4) {
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
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    branchRow
                }

                Spacer(minLength: 12)

                chipsRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                isHovered
                    ? Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
                    : Color.white.opacity(AppStyles.General.Fill.muted)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(AppStyles.General.Fill.active), lineWidth: 1)
    }

    private var iconColor: Color {
        let hex = card.iconColorHex ?? ""
        return Color(nsColor: NSColor(hex: hex) ?? .controlAccentColor)
    }

    private var iconSymbol: String {
        switch card.checkoutIconKind ?? .gitWorktree {
        case .mainCheckout: return "star.fill"
        case .gitWorktree: return "arrow.triangle.branch"
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: iconSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 14, alignment: .leading)

            Text(card.repoName)
                .font(AppStyles.Welcome.Typography.h3)
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.TextColor.h3Opacity))

            Text("/")
                .font(AppStyles.Welcome.Typography.h3)
                .foregroundStyle(.secondary)

            Text(card.worktreeDisplayName)
                .font(AppStyles.Welcome.Typography.h3)
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.TextColor.h3Opacity))
        }
    }

    private var branchRow: some View {
        Text(card.detail)
            .font(AppStyles.Welcome.Typography.bodySm)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 20)
    }

    private var chipsRow: some View {
        WorkspaceStatusChipRow(
            model: card.statusChips
                ?? .init(
                    branchStatus: .init(
                        isDirty: false,
                        syncState: .unknown,
                        prCount: nil,
                        linesAdded: 0,
                        linesDeleted: 0
                    ),
                    notificationCount: 0
                ),
            accentColor: iconColor
        )
    }
}

private struct WorkspaceRecentPlaceholderCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(AppStyles.Welcome.Typography.h3)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)

            Text("No recent worktrees yet.")
                .font(AppStyles.Welcome.Typography.h3)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.white.opacity(AppStyles.General.Fill.active),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
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
        .padding(24)
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
