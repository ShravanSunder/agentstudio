import SwiftUI

enum WorkspaceEmptyStateLayout {
    static let visibleRecentCardLimit: Int = 6
}

enum WorkspaceEmptyStateCopy {
    static let intakeTitle = "Welcome to AgentStudio"
    static let intakeBody = "The terminal IDE built for coding agents."
    static let intakeHelper =
        "AgentStudio watches the folder and discovers your repos automatically."

    static let intakeBusyTitle = "Opening folder picker…"
    static let intakeBusyHelper = "Waiting for you to pick a folder."

    static let scanningHelper = "Looking for git folders…"

    static let scanEmptyRetryButton = "Choose Another Folder to Scan…"
    static let scanEmptyHelper =
        "AgentStudio will keep watching this folder and add repos as they appear."

    static func scanningTitle(folder: String) -> String {
        "Scanning \(folder)"
    }

    static func scanEmptyTitle(folder: String) -> String {
        "No git folders found in \(folder)"
    }

    static func displayName(for path: URL?, fallback: String) -> String {
        guard let path else { return fallback }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fullPath = path.path
        if fullPath.hasPrefix(home) {
            return "~" + fullPath.dropFirst(home.count)
        }
        return fullPath
    }
}

struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    // Instant click feedback for the folder-intake button. Flips the action
    // region to a spinner BEFORE the store observation cycle propagates
    // .scanning — otherwise users perceive a dead 1–2 second gap between
    // the click and Welcome 2 appearing.
    @State private var isBusy: Bool = false
    @State private var busyTimeoutTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch model.kind {
            case .noFolders where isBusy:
                VStack(spacing: 0) {
                    Spacer()
                    folderIntakeBusyBody
                    Spacer()
                }
                .id("noFoldersBusy")
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .animation(.easeInOut(duration: 0.25), value: isBusy)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.kind) { _, newKind in
            // Once the store state has actually moved past .noFolders, the
            // busy placeholder has served its purpose — yield to the real UI.
            if newKind != .noFolders {
                endBusy()
            }
        }
        .onDisappear { endBusy() }
    }

    private func beginBusy() {
        isBusy = true
        busyTimeoutTask?.cancel()
        busyTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(AppStyles.Welcome.intakeBusyTimeoutSeconds))
            guard !Task.isCancelled else { return }
            isBusy = false
            busyTimeoutTask = nil
        }
    }

    private func endBusy() {
        busyTimeoutTask?.cancel()
        busyTimeoutTask = nil
        isBusy = false
    }

    private var folderIntakeBody: some View {
        folderIntakeLayout {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.intakeActionRowSpacing) {
                Button(LocalActionSpec.chooseFolderToScan.actionSpec.label) {
                    beginBusy()
                    onAddFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(WorkspaceEmptyStateCopy.intakeHelper)
                    .font(.system(size: AppStyles.General.Typography.textXs))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, AppStyles.Welcome.intakeActionTopPadding)
        }
    }

    private var folderIntakeBusyBody: some View {
        folderIntakeLayout {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.intakeActionRowSpacing) {
                HStack(spacing: AppStyles.Welcome.intakeScanningSpinnerGap) {
                    ProgressView()
                        .controlSize(.small)
                    Text(WorkspaceEmptyStateCopy.intakeBusyTitle)
                        .font(AppStyles.Welcome.Typography.h3)
                        .foregroundStyle(
                            .primary.opacity(AppStyles.Welcome.intakeScanningTitleOpacity)
                        )
                }

                Text(WorkspaceEmptyStateCopy.intakeBusyHelper)
                    .font(.system(size: AppStyles.General.Typography.textXs))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, AppStyles.Welcome.intakeActionTopPadding)
        }
    }

    private var scanningBody: some View {
        folderIntakeLayout {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.intakeActionRowSpacing) {
                HStack(spacing: AppStyles.Welcome.intakeScanningSpinnerGap) {
                    ProgressView()
                        .controlSize(.small)
                    Text(WorkspaceEmptyStateCopy.scanningTitle(folder: scanningFolderDisplayName))
                        .font(AppStyles.Welcome.Typography.h3)
                        .foregroundStyle(
                            .primary.opacity(AppStyles.Welcome.intakeScanningTitleOpacity)
                        )
                }

                Text(WorkspaceEmptyStateCopy.scanningHelper)
                    .font(.system(size: AppStyles.General.Typography.textXs))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, AppStyles.Welcome.intakeActionTopPadding)
        }
    }

    private var scanEmptyBody: some View {
        folderIntakeLayout {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.intakeActionRowSpacing) {
                Text(WorkspaceEmptyStateCopy.scanEmptyTitle(folder: emptyFolderDisplayName))
                    .font(AppStyles.Welcome.Typography.h3)
                    .foregroundStyle(
                        .primary.opacity(AppStyles.Welcome.intakeScanningTitleOpacity)
                    )

                Button(WorkspaceEmptyStateCopy.scanEmptyRetryButton) {
                    beginBusy()
                    onAddFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(WorkspaceEmptyStateCopy.scanEmptyHelper)
                    .font(.system(size: AppStyles.General.Typography.textXs))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, AppStyles.Welcome.intakeActionTopPadding)
        }
    }

    @ViewBuilder
    private func folderIntakeLayout<Action: View>(
        @ViewBuilder actionRegion: () -> Action
    ) -> some View {
        HStack(alignment: .center, spacing: AppStyles.Welcome.intakeColumnSpacing) {
            WelcomeSidebarIllustration()

            VStack(alignment: .leading, spacing: AppStyles.Welcome.intakeRightColumnSpacing) {
                AppLogoView(size: AppStyles.Welcome.intakeLogoSize)

                Text(WorkspaceEmptyStateCopy.intakeTitle)
                    .font(.system(size: AppStyles.Welcome.titleFontSize, weight: .semibold))

                Text(WorkspaceEmptyStateCopy.intakeBody)
                    .font(.system(size: AppStyles.Welcome.bodyFontSize))
                    .foregroundStyle(.secondary)

                actionRegion()
            }
        }
    }

    private var scanningFolderDisplayName: String {
        WorkspaceEmptyStateCopy.displayName(for: model.scanningFolderPath, fallback: "")
    }

    private var emptyFolderDisplayName: String {
        WorkspaceEmptyStateCopy.displayName(for: model.emptyFolderPath, fallback: "this folder")
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
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose + 4) {
            Text("Start")
                .font(AppStyles.Welcome.Typography.h2)
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.TextColor.h2Opacity))

            launcherShortcutsColumns
        }
    }

    private var launcherShortcutsColumns: some View {
        HStack(alignment: .top, spacing: AppStyles.Welcome.launcherShortcutsColumnsGap) {
            VStack(spacing: AppStyles.Welcome.launcherPreviewCalloutGap) {
                CommandBarEmbeddedPreview()
                LauncherScopesCallout()
            }

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
                    title: "Watch Folder",
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
        LauncherShortcutRow(
            key: key,
            keyImage: keyImage,
            title: title,
            subtitle: subtitle,
            action: action
        )
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

struct CommandBarEmbeddedPreview: View {
    static let previewQuery: String = "gho"

    static let mockItems: [CommandBarItem] = [
        CommandBarItem(
            id: "preview-ghostty",
            title: "ghostty",
            icon: "star.fill",
            iconColor: welcomePaletteColor(at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex),
            group: "Repos",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostrider",
            title: "ghostrider",
            icon: "star.fill",
            iconColor: welcomePaletteColor(at: WelcomeSidebarIllustrationConstants.uvPaletteIndex),
            group: "Repos",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostty-gpu-renderer",
            title: "ghostty.gpu-renderer",
            icon: "arrow.triangle.branch",
            iconColor: welcomePaletteColor(at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex),
            group: "ghostty (worktrees)",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostty-fix-keybinds",
            title: "ghostty.fix-keybinds",
            icon: "arrow.triangle.branch",
            iconColor: welcomePaletteColor(at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex),
            group: "ghostty (worktrees)",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostrider-fix-engine",
            title: "ghostrider.fix-engine",
            icon: "arrow.triangle.branch",
            iconColor: welcomePaletteColor(at: WelcomeSidebarIllustrationConstants.uvPaletteIndex),
            group: "ghostrider (worktrees)",
            groupPriority: 30,
            action: .custom {}
        ),
    ]

    static var mockGroups: [CommandBarItemGroup] {
        var seenGroupNames: [String] = []
        var grouped: [String: [CommandBarItem]] = [:]
        for item in mockItems {
            if grouped[item.group] == nil {
                seenGroupNames.append(item.group)
            }
            grouped[item.group, default: []].append(item)
        }
        return seenGroupNames.map { name in
            CommandBarItemGroup(
                id: "preview-group-\(name)",
                name: name,
                priority: grouped[name]?.first?.groupPriority ?? 0,
                items: grouped[name] ?? []
            )
        }
    }

    @State private var previewState: CommandBarState = {
        let state = CommandBarState()
        state.rawInput = previewQuery
        state.selectedIndex = 0
        return state
    }()

    private var selectedItem: CommandBarItem? {
        Self.mockItems.first
    }

    private var footerHints: [FooterHint] {
        FooterHintBuilder.hints(
            for: selectedItem,
            isNested: false,
            canOpenInCurrentTab: false,
            scope: .everything
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            CommandBarSearchField(
                state: previewState,
                onArrowUp: {},
                onArrowDown: {},
                onEnter: { _ in },
                onShortcutTrigger: { _ in false },
                onBackspaceOnEmpty: {}
            )

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            CommandBarResultsList(
                groups: Self.mockGroups,
                selectedIndex: 0,
                searchQuery: Self.previewQuery,
                onSelect: { _ in }
            )
            .frame(height: AppStyles.Welcome.previewResultsHeight)

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
        .allowsHitTesting(false)
    }
}

private struct LauncherShortcutRow: View {
    let key: String?
    let keyImage: String?
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
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
            .padding(.horizontal, AppStyles.Welcome.launcherShortcutRowHorizontalPadding)
            .padding(.vertical, AppStyles.Welcome.launcherShortcutRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(rowBorder)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppStyles.Welcome.launcherShortcutRowCornerRadius)
            .fill(
                isHovered
                    ? Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
                    : Color.white.opacity(AppStyles.Welcome.cardFillOpacity)
            )
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: AppStyles.Welcome.launcherShortcutRowCornerRadius)
            .stroke(Color.white.opacity(AppStyles.Welcome.cardStrokeOpacity), lineWidth: 1)
    }
}

struct LauncherScopesCallout: View {
    private struct Scope: Identifiable {
        let id: String
        let prefix: String
        let label: String
    }

    private let scopes: [Scope] = [
        Scope(id: "scope-commands", prefix: ">", label: "Commands"),
        Scope(id: "scope-panes", prefix: "$", label: "Panes"),
        Scope(id: "scope-repos", prefix: "#", label: "Repos · Worktrees"),
    ]

    var body: some View {
        HStack(spacing: AppStyles.Welcome.scopesCalloutItemGap) {
            ForEach(scopes) { scope in
                HStack(spacing: 6) {
                    Text(scope.prefix)
                        .font(AppStyles.Welcome.Typography.key)
                        .foregroundStyle(Color.accentColor)
                    Text(scope.label)
                        .font(AppStyles.Welcome.Typography.bodySm)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: AppStyles.Welcome.previewWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(AppStyles.Welcome.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(AppStyles.Welcome.cardStrokeOpacity), lineWidth: 1)
                )
        )
    }
}

private func welcomePaletteColor(at index: Int) -> Color {
    let hexes = AppStyles.Shell.Sidebar.accentPaletteHexes
    let hex = hexes.indices.contains(index) ? hexes[index] : hexes.first ?? ""
    return Color(nsColor: NSColor(hex: hex) ?? .controlAccentColor)
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
