import SwiftUI

// MARK: - Launcher preview scope (for clickable pills + preview swap)

enum LauncherPreviewScope: String, Identifiable, CaseIterable {
    case commands, panes, repos

    var id: String { rawValue }

    var prefixGlyph: String {
        switch self {
        case .commands: return ">"
        case .panes: return "$"
        case .repos: return "#"
        }
    }

    var label: String {
        switch self {
        case .commands: return "Commands"
        case .panes: return "Panes"
        case .repos: return "Repos · Worktrees"
        }
    }

    var query: String {
        switch self {
        case .commands: return "new"
        case .panes: return "dev"
        case .repos: return "gho"
        }
    }
}

// MARK: - LauncherPreviewStack (composition root for preview + scope pills)

/// Wraps the cmd-P preview and the scope callout so they share a selected
/// scope. Clicking a pill swaps the preview's mock data with a 100ms
/// crossfade. Preview itself stays `.allowsHitTesting(false)` — only the
/// pills are interactive.
struct LauncherPreviewStack: View {
    @State private var selectedScope: LauncherPreviewScope = .repos

    var body: some View {
        VStack(spacing: AppStyles.Welcome.launcherPreviewCalloutGap) {
            CommandBarEmbeddedPreview(scope: selectedScope)
            LauncherScopesCallout(selectedScope: $selectedScope)
        }
    }
}

// MARK: - CommandBarEmbeddedPreview

struct CommandBarEmbeddedPreview: View {
    let scope: LauncherPreviewScope

    init(scope: LauncherPreviewScope = .repos) {
        self.scope = scope
    }

    var body: some View {
        VStack(spacing: 0) {
            previewContent
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

    // Crossfade the inner content when scope changes. `.id(scope)` forces a
    // re-identify so SwiftUI treats the new content as a different view and
    // the `.transition` fires.
    @ViewBuilder
    private var previewContent: some View {
        PreviewBody(scope: scope)
            .id(scope)
            .transition(.opacity)
            .animation(
                .easeInOut(duration: AppStyles.Welcome.launcherPreviewScopeCrossfadeDuration),
                value: scope
            )
    }

    // MARK: - Mock data (public for tests)

    static func mockItems(for scope: LauncherPreviewScope) -> [CommandBarItem] {
        switch scope {
        case .commands: return commandsMockItems
        case .panes: return panesMockItems
        case .repos: return reposMockItems
        }
    }

    static func mockGroups(for scope: LauncherPreviewScope) -> [CommandBarItemGroup] {
        Self.buildGroups(from: Self.mockItems(for: scope))
    }

    // Legacy accessors (keep tests working against the default .repos scope).
    static let previewQuery: String = LauncherPreviewScope.repos.query
    static var mockItems: [CommandBarItem] { reposMockItems }
    static var mockGroups: [CommandBarItemGroup] { buildGroups(from: reposMockItems) }

    private static func buildGroups(from items: [CommandBarItem]) -> [CommandBarItemGroup] {
        var seenGroupNames: [String] = []
        var grouped: [String: [CommandBarItem]] = [:]
        for item in items {
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

    // MARK: - Commands mock (query: "new")

    private static let commandsMockItems: [CommandBarItem] = [
        CommandBarItem(
            id: "preview-cmd-new-tab",
            title: "New Tab",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "T")],
            group: "Tab",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-cmd-new-terminal-in-tab",
            title: "New Terminal in Tab",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "⇧"), ShortcutKey(symbol: "T")],
            group: "Tab",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-cmd-new-window",
            title: "New Window",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "⇧"), ShortcutKey(symbol: "N")],
            group: "Window",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-cmd-new-pane",
            title: "New Pane (Split Right)",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "D")],
            group: "Pane",
            groupPriority: 30,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-cmd-new-floating",
            title: "New Floating Terminal",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "⇧"), ShortcutKey(symbol: "F")],
            group: "Floating",
            groupPriority: 40,
            action: .custom {}
        ),
    ]

    // MARK: - Panes mock (query: "dev")
    //
    // Pane names mirror how developers actually name work-in-progress panes:
    // "what this pane is currently doing", not "Terminal N". Covers three
    // broad kinds — servers/long-running, testing, and coding/agents.

    private static let panesMockItems: [CommandBarItem] = [
        CommandBarItem(
            id: "preview-pane-dev-server",
            title: "dev server",
            icon: "star.fill",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "Tab 1 · ghostty",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-test-watcher",
            title: "test watcher",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "Tab 1 · ghostty",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-claude-shader",
            title: "claude · shader polish",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "Tab 1 · ghostty",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-benchmarks",
            title: "benchmarks",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "Tab 2 · ghostty.gpu-renderer",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-build-zig-release",
            title: "build · zig release",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "Tab 2 · ghostty.gpu-renderer",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-api-server",
            title: "api server",
            icon: "star.fill",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.uvPaletteIndex
            ),
            group: "Tab 3 · ghostrider",
            groupPriority: 30,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-redis-local",
            title: "redis · local",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.uvPaletteIndex
            ),
            group: "Tab 3 · ghostrider",
            groupPriority: 30,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-pane-logs-tail",
            title: "logs · tail -f",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.uvPaletteIndex
            ),
            group: "Tab 3 · ghostrider",
            groupPriority: 30,
            action: .custom {}
        ),
    ]

    // MARK: - Repos mock (query: "gho") — the original, matches WelcomeSidebarIllustration

    private static let reposMockItems: [CommandBarItem] = [
        CommandBarItem(
            id: "preview-ghostty",
            title: "ghostty",
            icon: "star.fill",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "Repos",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostrider",
            title: "ghostrider",
            icon: "star.fill",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.uvPaletteIndex
            ),
            group: "Repos",
            groupPriority: 10,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostty-gpu-renderer",
            title: "ghostty.gpu-renderer",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "ghostty (worktrees)",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostty-fix-keybinds",
            title: "ghostty.fix-keybinds",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
            ),
            group: "ghostty (worktrees)",
            groupPriority: 20,
            action: .custom {}
        ),
        CommandBarItem(
            id: "preview-ghostrider-fix-engine",
            title: "ghostrider.fix-engine",
            icon: "arrow.triangle.branch",
            iconColor: AppStyles.Shell.Sidebar.paletteColor(
                at: WelcomeSidebarIllustrationConstants.uvPaletteIndex
            ),
            group: "ghostrider (worktrees)",
            groupPriority: 30,
            action: .custom {}
        ),
    ]
}

// MARK: - PreviewBody — internal view composing real cmd-bar leaf views with mock data

private struct PreviewBody: View {
    let scope: LauncherPreviewScope

    @State private var previewState = CommandBarState()

    private var selectedItem: CommandBarItem? {
        CommandBarEmbeddedPreview.mockItems(for: scope).first
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
                groups: CommandBarEmbeddedPreview.mockGroups(for: scope),
                selectedIndex: 0,
                searchQuery: scope.query,
                onSelect: { _ in }
            )
            .frame(height: AppStyles.Welcome.previewResultsHeight)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            CommandBarFooter(hints: footerHints)
        }
        .onAppear { previewState.rawInput = scope.query }
    }
}

struct LauncherShortcutRow: View {
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

/// Clickable scope pills below the cmd-P preview. Selecting a pill flips
/// the parent's `selectedScope`, which swaps the preview's mock data with a
/// 100ms crossfade. The selected pill gets an accent-tinted background to
/// communicate which scope is active.
struct LauncherScopesCallout: View {
    @Binding var selectedScope: LauncherPreviewScope

    var body: some View {
        HStack(spacing: AppStyles.Welcome.scopesCalloutItemGap) {
            ForEach(LauncherPreviewScope.allCases) { scope in
                scopePill(scope)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppStyles.Welcome.scopesCalloutHorizontalPadding)
        .padding(.vertical, AppStyles.Welcome.scopesCalloutVerticalPadding)
        .frame(width: AppStyles.Welcome.previewWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Welcome.scopesCalloutCornerRadius)
                .fill(Color.white.opacity(AppStyles.Welcome.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyles.Welcome.scopesCalloutCornerRadius)
                        .stroke(Color.white.opacity(AppStyles.Welcome.cardStrokeOpacity), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func scopePill(_ scope: LauncherPreviewScope) -> some View {
        Button {
            withAnimation(
                .easeInOut(duration: AppStyles.Welcome.launcherPreviewScopeCrossfadeDuration)
            ) {
                selectedScope = scope
            }
        } label: {
            HStack(spacing: AppStyles.Welcome.scopesCalloutPillContentSpacing) {
                Text(scope.prefixGlyph)
                    .font(AppStyles.Welcome.Typography.key)
                    .foregroundStyle(Color.accentColor)
                Text(scope.label)
                    .font(AppStyles.Welcome.Typography.bodySm)
                    .foregroundStyle(
                        selectedScope == scope ? .primary : .secondary
                    )
            }
            .padding(.horizontal, AppStyles.Welcome.scopesCalloutPillHorizontalPadding)
            .padding(.vertical, AppStyles.Welcome.scopesCalloutPillVerticalPadding)
            .background(pillBackground(for: scope))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pillBackground(for scope: LauncherPreviewScope) -> some View {
        if selectedScope == scope {
            RoundedRectangle(cornerRadius: AppStyles.Welcome.scopesCalloutPillCornerRadius)
                .fill(Color.accentColor.opacity(AppStyles.Welcome.scopesCalloutPillSelectedFillOpacity))
        } else {
            Color.clear
        }
    }
}
