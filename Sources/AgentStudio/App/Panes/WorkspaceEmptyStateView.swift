import SwiftUI

struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let repoCount: Int
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    private let contentWidth: CGFloat = 860
    private let cardMinimumWidth: CGFloat = 250

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                Group {
                    switch model.kind {
                    case .noFolders:
                        folderIntakeBody
                            .id("noFolders")
                            .transition(.opacity)
                    case .scanning:
                        scanningBody
                            .id("scanning")
                            .transition(.opacity)
                    case .launcher:
                        launcherBody
                            .id("launcher")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, minHeight: 680)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .animation(.easeInOut(duration: 0.25), value: model.kind)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var folderIntakeBody: some View {
        HStack(alignment: .center, spacing: 56) {
            WelcomeSidebarIllustration()

            VStack(alignment: .leading, spacing: 20) {
                AppLogoView(size: 56)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to AgentStudio")
                        .font(.system(size: 26, weight: .semibold))

                    Text("A terminal workspace for your repos.")
                        .font(.system(size: AppStyle.textLg))
                        .foregroundStyle(.secondary)
                }

                Text("Point at a parent folder — AgentStudio discovers every repo and worktree inside.")
                    .font(.system(size: AppStyle.textBase))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 320)

                VStack(alignment: .leading, spacing: 8) {
                    Button("Choose a Folder to Scan…") {
                        onAddFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("⌘⌥⇧O")
                        .font(.system(size: AppStyle.textXs))
                        .foregroundStyle(.quaternary)
                        .padding(.leading, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningBody: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(1.2)

            VStack(spacing: 8) {
                Text("Scanning \(scanningFolderDisplayName)")
                    .font(.system(size: 20, weight: .semibold))

                if repoCount > 0 {
                    Text("Found \(repoCount) \(repoCount == 1 ? "repository" : "repositories") so far…")
                        .font(.system(size: AppStyle.textBase))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Looking for repositories…")
                        .font(.system(size: AppStyle.textBase))
                        .foregroundStyle(.secondary)
                }

                Text("Repos appear in the sidebar as they're discovered.")
                    .font(.system(size: AppStyle.textSm))
                    .foregroundStyle(.tertiary)
            }

            Rectangle()
                .fill(Color.white.opacity(AppStyle.fillSubtle))
                .frame(width: 200, height: 1)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 10) {
                Text("⌘T")
                    .font(.system(size: AppStyle.textBase, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)

                Text("Open a terminal tab anytime — no need to wait.")
                    .font(.system(size: AppStyle.textBase))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
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

    private var launcherBody: some View {
        VStack(spacing: 28) {
            WorkspaceHomeHeader(
                title: "Workspace Ready",
                subtitle: "Open a recent worktree, or pick one from the sidebar."
            )

            VStack(spacing: 18) {
                recentSectionHeader

                if model.recentCards.isEmpty {
                    WorkspaceRecentPlaceholderCard()
                        .frame(maxWidth: 420)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: cardMinimumWidth, maximum: 320), spacing: 16, alignment: .top)
                        ],
                        alignment: .center,
                        spacing: 16
                    ) {
                        ForEach(model.recentCards) { card in
                            WorkspaceRecentCardView(
                                card: card,
                                onOpen: { onOpenRecent(card.target) }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentSectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Recent")
                .font(.system(size: AppStyle.textSm, weight: .semibold))
                .foregroundStyle(.secondary)

            if model.showsOpenAll {
                Button("Open All In Tabs") {
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
            VStack(alignment: .leading, spacing: AppStyle.sidebarRowContentSpacing + 4) {
                HStack(spacing: AppStyle.spacingTight) {
                    leadingIcon
                        .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                    Text(card.title)
                        .font(.system(size: AppStyle.textBase, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: AppStyle.spacingTight) {
                    secondaryLineIcon
                        .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                    Text(card.detail)
                        .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let statusChips = card.statusChips {
                    WorkspaceStatusChipRow(model: statusChips, accentColor: .accentColor)
                        .padding(.leading, AppStyle.sidebarStatusRowLeadingIndent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

    @ViewBuilder
    private var leadingIcon: some View {
        switch card.icon {
        case .mainWorktree:
            WorkspaceOcticonImage(name: "octicon-star-fill", size: AppStyle.textBase)
                .foregroundStyle(Color.accentColor)
        case .gitWorktree:
            WorkspaceOcticonImage(name: "octicon-git-worktree", size: AppStyle.textBase)
                .foregroundStyle(Color.accentColor)
                .rotationEffect(.degrees(180))
        case .cwdOnly:
            Image(systemName: "terminal")
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var secondaryLineIcon: some View {
        if card.icon == .cwdOnly {
            Image(systemName: "folder")
                .font(.system(size: AppStyle.sidebarBranchIconSize, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            WorkspaceOcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
                .foregroundStyle(.secondary)
        }
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
