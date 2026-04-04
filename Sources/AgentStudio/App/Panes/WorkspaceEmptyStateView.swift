import SwiftUI

struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    private let contentWidth: CGFloat = 860
    private let cardMinimumWidth: CGFloat = 250

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
                ScrollView(.vertical, showsIndicators: false) {
                    launcherBody
                        .frame(maxWidth: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 48)
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
                    Button("Choose a Folder to Scan…") {
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

    private var launcherBody: some View {
        VStack(spacing: 28) {
            WorkspaceHomeHeader(
                title: "Your workspace",
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

            QuickActionsCallout()
                .padding(.top, AppStyle.spacingLoose)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentSectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Recent")
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(.tertiary)

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
            OcticonImage(name: "octicon-star-fill", size: AppStyle.textBase)
                .foregroundStyle(Color.accentColor)
        case .gitWorktree:
            OcticonImage(name: "octicon-git-worktree", size: AppStyle.textBase)
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
            OcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
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
