import SwiftUI

struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    private let contentWidth: CGFloat = 860
    private let cardMinimumWidth: CGFloat = 250

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                WorkspaceHomeHeader(
                    title: model.kind == .noFolders ? "Welcome to AgentStudio" : "Workspace Ready",
                    subtitle: model.kind == .noFolders
                        ? "Add folders to scan for repos, then jump back into the worktrees and CWDs you were using."
                        : "Open a recent worktree or CWD, or scan another folder for repos."
                )

                Group {
                    switch model.kind {
                    case .noFolders:
                        folderIntakeBody
                    case .launcher:
                        launcherBody
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, minHeight: 680)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .animation(.easeInOut(duration: 0.18), value: model.kind)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var folderIntakeBody: some View {
        VStack(spacing: 28) {
            WorkspaceHomeIntroCard()

            VStack(spacing: 10) {
                Text("No folders configured yet")
                    .font(.system(size: AppStyle.textXl, weight: .semibold))
                Text("Choose a parent folder and AgentStudio will scan it for repositories and worktrees.")
                    .font(.system(size: AppStyle.textBase))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button("Add Folder...") {
                onAddFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Add folder to scan for repos")
        }
        .frame(maxWidth: .infinity)
    }

    private var launcherBody: some View {
        VStack(spacing: 28) {
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

            VStack(spacing: 12) {
                Button("Add Folder to Scan for Repos...") {
                    onAddFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Add folder to scan for repos")
            }
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

private struct WorkspaceHomeIntroCard: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.43, blue: 0.38))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Spacer(minLength: 20)

            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 92, height: 92)

                VStack(spacing: 6) {
                    Text("AgentStudio")
                        .font(.system(size: AppStyle.text2xl, weight: .semibold))
                    Text("Scan folders, discover repos, and reopen worktrees where you left off.")
                        .font(.system(size: AppStyle.textBase))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }

            Spacer(minLength: 24)
        }
        .frame(width: 360, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(AppStyle.fillMuted))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 24, y: 18)
        )
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
