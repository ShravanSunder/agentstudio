import SwiftUI

enum WorkspaceEmptyStateLayout {
    static let launcherQuickActionsSectionTitle = "Shortcuts"
    static let launcherQuickActionsSectionTopPadding: CGFloat = 20
    static let launcherQuickActionsDividerWidth: CGFloat = 220
    static let launcherQuickActionsDividerBottomPadding: CGFloat = 20
    static let launcherQuickActionsLabelBottomPadding: CGFloat = 20
    static let recentSectionWidthFraction: CGFloat = 0.6
    static let recentGridSpacing: CGFloat = 16
    static let recentCardWidth: CGFloat = 300
    static let minimumRecentColumnCount = 2
    static let maximumRecentColumnCount = 5
    static let recentVisibleRowCount = 3

    static func recentSectionWidth(for availableWidth: CGFloat) -> CGFloat {
        let fractionalWidth = availableWidth * recentSectionWidthFraction
        let maximumGridWidth =
            CGFloat(maximumRecentColumnCount) * recentCardWidth
            + CGFloat(maximumRecentColumnCount - 1) * recentGridSpacing
        return min(fractionalWidth, maximumGridWidth)
    }

    static func recentColumnCount(for availableWidth: CGFloat) -> Int {
        let sectionWidth = recentSectionWidth(for: availableWidth)
        let fittingColumnCount = Int(
            (sectionWidth + recentGridSpacing) / (recentCardWidth + recentGridSpacing)
        )
        return min(max(fittingColumnCount, minimumRecentColumnCount), maximumRecentColumnCount)
    }

    static func visibleRecentCardLimit(for availableWidth: CGFloat) -> Int {
        recentColumnCount(for: availableWidth) * recentVisibleRowCount
    }

    static func recentGridColumns(for availableWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(recentCardWidth),
                spacing: recentGridSpacing,
                alignment: .top
            ),
            count: recentColumnCount(for: availableWidth)
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
            case .launcher:
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        launcherBody(availableWidth: max(geometry.size.width - 80, 0))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 48)
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
                    .font(.system(size: 28, weight: .semibold))

                Text("The terminal IDE built for coding agents.")
                    .font(.system(size: AppStyle.textLg))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Button(LocalActionPresentation.chooseFolderToScan.presentation.label) {
                        onAddFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("AgentStudio watches the folder and discovers your repos automatically.")
                        .font(.system(size: AppStyle.textXs))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
            }
        }
    }

    private var scanningBody: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .scaleEffect(1.2)

                Text("Scanning \(scanningFolderDisplayName)")
                    .font(.system(size: 20, weight: .semibold))
            }

            scanningCallout
        }
    }

    private var scanningCallout: some View {
        QuickActionsCallout(header: "You don't need to wait.")
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

    private func launcherBody(availableWidth: CGFloat) -> some View {
        let recentSectionWidth = WorkspaceEmptyStateLayout.recentSectionWidth(for: availableWidth)
        let visibleRecentCards = Array(
            model.recentCards.prefix(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: availableWidth))
        )

        return VStack(spacing: 28) {
            WorkspaceHomeHeader(
                title: "Your workspace",
                subtitle: "Open a recent worktree, or pick one from the sidebar."
            )

            VStack(spacing: 18) {
                recentSectionHeader

                if visibleRecentCards.isEmpty {
                    WorkspaceRecentPlaceholderCard()
                        .frame(width: WorkspaceEmptyStateLayout.recentCardWidth)
                } else if visibleRecentCards.count == 1,
                    let card = visibleRecentCards.first
                {
                    WorkspaceRecentCardView(
                        card: card,
                        onOpen: { onOpenRecent(card.target) }
                    )
                    .frame(width: WorkspaceEmptyStateLayout.recentCardWidth)
                } else {
                    LazyVGrid(
                        columns: WorkspaceEmptyStateLayout.recentGridColumns(for: availableWidth),
                        alignment: .center,
                        spacing: WorkspaceEmptyStateLayout.recentGridSpacing
                    ) {
                        ForEach(visibleRecentCards) { card in
                            WorkspaceRecentCardView(
                                card: card,
                                onOpen: { onOpenRecent(card.target) }
                            )
                        }
                    }
                    .frame(maxWidth: recentSectionWidth)
                }
            }
            .frame(maxWidth: .infinity)

            launcherQuickActionsSection
        }
        .frame(maxWidth: .infinity)
    }

    private var launcherQuickActionsSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(AppStyle.fillActive))
                .frame(width: WorkspaceEmptyStateLayout.launcherQuickActionsDividerWidth, height: 1)
                .padding(.bottom, WorkspaceEmptyStateLayout.launcherQuickActionsDividerBottomPadding)

            Text(WorkspaceEmptyStateLayout.launcherQuickActionsSectionTitle)
                .font(.system(size: AppStyle.textSm, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.bottom, WorkspaceEmptyStateLayout.launcherQuickActionsLabelBottomPadding)

            QuickActionsCallout()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WorkspaceEmptyStateLayout.launcherQuickActionsSectionTopPadding)
    }

    private var recentSectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Recent")
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(.tertiary)

            if model.showsOpenAll {
                Button(LocalActionPresentation.openAllInTabs.presentation.label) {
                    onOpenAllRecent()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}

private struct WorkspaceHomeHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: AppStyle.textLg))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
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
        RoundedRectangle(cornerRadius: 16)
            .fill(
                isHovered
                    ? Color.accentColor.opacity(AppStyle.sidebarRowHoverOpacity)
                    : Color.white.opacity(AppStyle.fillMuted)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: AppStyle.sidebarRowContentSpacing + 4) {
            HStack(spacing: AppStyle.spacingTight) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: AppStyle.textBase, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text("No recent worktrees yet")
                    .font(.system(size: AppStyle.textBase, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(AppStyle.fillMuted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.white.opacity(AppStyle.fillActive),
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
        VStack(alignment: .leading, spacing: 14) {
            if let header {
                Text(header)
                    .font(.system(size: AppStyle.textBase, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                quickActionButton(key: "⌘T", label: "New terminal tab") {
                    CommandDispatcher.shared.dispatch(.newTab)
                }
                quickActionButton(key: "⌘P", label: "Command palette") {
                    CommandDispatcher.shared.dispatch(.commandBar)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(AppStyle.fillMuted))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
                )
        )
    }

    private func quickActionButton(key: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(key)
                    .font(.system(size: AppStyle.textSm, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, alignment: .trailing)

                Text(label)
                    .font(.system(size: AppStyle.textBase))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
