import AppKit
import Foundation
import SwiftUI

// swiftlint:disable file_length

/// Redesigned sidebar content grouped by repository identity (worktree family / remote).
@MainActor
struct RepoSidebarContentView: View {
    struct SidebarProjection {
        let resolvedGroups: [SidebarRepoGroup]
        let loadingRepos: [SidebarRepo]
        let showsNoResults: Bool
    }

    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let uiStore: WorkspaceUIStore

    @State private var expandedGroups: Set<String> = []
    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isFilterVisible: Bool = false
    @FocusState private var isFilterFocused: Bool

    @State private var checkoutColorByRepoId: [String: String] = [:]
    @State private var notificationCountsByWorktreeId: [UUID: Int] = [:]

    @State private var debounceTask: Task<Void, Never>?

    private static let filterDebounceMilliseconds = 25

    init(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache = WorkspaceRepoCache(),
        uiStore: WorkspaceUIStore = WorkspaceUIStore()
    ) {
        self.store = store
        self.repoCache = repoCache
        self.uiStore = uiStore
    }

    private var sidebarRepos: [SidebarRepo] {
        store.repos.map(SidebarRepo.init(repo:))
    }

    private var sidebarProjectionFingerprint: String {
        Self.projectionFingerprint(for: sidebarProjection)
    }

    private var sidebarProjection: SidebarProjection {
        Self.projectSidebar(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId,
            query: debouncedQuery
        )
    }

    private var groups: [SidebarRepoGroup] {
        sidebarProjection.resolvedGroups
    }

    private var loadingReposList: [SidebarRepo] {
        sidebarProjection.loadingRepos
    }

    private var resolvedListEntries: [SidebarListEntry] {
        Self.buildListEntries(
            groups: groups,
            expandedGroupIds: expandedGroups,
            isFiltering: isFiltering
        )
    }

    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    private var worktreeStatusById: [UUID: GitBranchStatus] {
        Self.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: repoCache.worktreeEnrichmentByWorktreeId,
            pullRequestCountsByWorktreeId: repoCache.pullRequestCountByWorktreeId
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFilterVisible {
                filterBar
            }

            if sidebarProjection.showsNoResults {
                noResultsView
            } else {
                groupList
            }
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 0)
        .task {
            expandedGroups = uiStore.expandedGroups
            filterText = uiStore.filterText
            debouncedQuery = uiStore.filterText
            checkoutColorByRepoId = uiStore.checkoutColors
            notificationCountsByWorktreeId = repoCache.notificationCountByWorktreeId
        }
        .task {
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                switch event {
                case .refreshWorktreesRequested:
                    continue
                case .filterSidebarRequested:
                    withAnimation(.easeOut(duration: 0.15)) {
                        if isFilterVisible {
                            hideFilter()
                        } else {
                            isFilterVisible = true
                            uiStore.setFilterVisible(true)
                        }
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        isFilterFocused = true
                    }
                case .worktreeBellRang(let paneId):
                    guard
                        let pane = store.pane(paneId),
                        let worktreeId = pane.worktreeId
                    else { continue }
                    notificationCountsByWorktreeId[worktreeId, default: 0] += 1
                default:
                    continue
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .onChange(of: filterText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            uiStore.setFilterText(trimmed)
            debounceTask?.cancel()
            if trimmed.isEmpty {
                withAnimation(.easeOut(duration: 0.12)) {
                    debouncedQuery = ""
                }
            } else {
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Self.filterDebounceMilliseconds))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        debouncedQuery = trimmed
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppStyle.textXs))
                .foregroundStyle(.tertiary)

            TextField("Filter...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: AppStyle.textSm))
                .foregroundStyle(.primary)
                .focused($isFilterFocused)
                .onExitCommand {
                    hideFilter()
                }
                .onKeyPress(.downArrow) {
                    isFilterFocused = false
                    return .handled
                }

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppStyle.textSm))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
                .transition(.opacity.animation(.easeOut(duration: 0.1)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppStyle.text2xl))
                .foregroundStyle(.secondary)
                .opacity(0.5)

            Text("No results")
                .font(.system(size: AppStyle.textSm, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }

    private var groupList: some View {
        List {
            ForEach(resolvedListEntries) { entry in
                switch entry {
                case .resolvedGroupHeader(let group):
                    Button {
                        toggleGroupExpansion(group.id)
                    } label: {
                        SidebarResolvedGroupHeaderRow(
                            isExpanded: isGroupExpanded(group.id),
                            repoTitle: group.repoTitle,
                            organizationName: group.organizationName
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: AppStyle.sidebarListRowLeadingInset,
                            bottom: 0,
                            trailing: 0
                        )
                    )
                    .contextMenu {
                        Divider()

                        if let primaryRepo = Self.primaryRepoForGroup(group) {
                            Button("Open in Finder") {
                                openRepoInFinder(primaryRepo.repoPath)
                            }
                        }

                        Button("Refresh Worktrees") {
                            postAppEvent(.refreshWorktreesRequested)
                        }
                    }

                case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId):
                    if let resolvedWorktreeContext = resolvedWorktreeContext(
                        groupId: groupId,
                        repoId: repoId,
                        worktreeId: worktreeId
                    ) {
                        SidebarWorktreeRow(
                            worktree: resolvedWorktreeContext.worktree,
                            checkoutTitle: checkoutTitle(
                                for: resolvedWorktreeContext.worktree,
                                in: resolvedWorktreeContext.repo
                            ),
                            branchName: branchName(for: resolvedWorktreeContext.worktree),
                            checkoutIconKind: checkoutIconKind(
                                for: resolvedWorktreeContext.worktree,
                                in: resolvedWorktreeContext.repo
                            ),
                            iconColor: colorForCheckout(
                                repo: resolvedWorktreeContext.repo,
                                in: resolvedWorktreeContext.group
                            ),
                            branchStatus: worktreeStatusById[resolvedWorktreeContext.worktree.id] ?? .unknown,
                            notificationCount: notificationCountsByWorktreeId[
                                resolvedWorktreeContext.worktree.id,
                                default: 0
                            ],
                            onOpen: {
                                clearNotifications(for: resolvedWorktreeContext.worktree.id)
                                CommandDispatcher.shared.dispatch(
                                    .openWorktree,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenNew: {
                                clearNotifications(for: resolvedWorktreeContext.worktree.id)
                                CommandDispatcher.shared.dispatch(
                                    .openNewTerminalInTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenInPane: {
                                clearNotifications(for: resolvedWorktreeContext.worktree.id)
                                CommandDispatcher.shared.dispatch(
                                    .openWorktreeInPane,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onSetIconColor: { colorHex in
                                let key = resolvedWorktreeContext.repo.id.uuidString
                                if let colorHex {
                                    checkoutColorByRepoId[key] = colorHex
                                } else {
                                    checkoutColorByRepoId.removeValue(forKey: key)
                                }
                                uiStore.setCheckoutColor(colorHex, for: key)
                            }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: AppStyle.sidebarGroupChildRowLeadingInset,
                                bottom: 0,
                                trailing: 0
                            )
                        )
                    }
                }
            }

            if !loadingReposList.isEmpty {
                Section {
                    ForEach(loadingReposList, id: \.id) { repo in
                        SidebarLoadingRepoRow(repoName: repo.name)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: AppStyle.sidebarGroupChildRowLeadingInset,
                                    bottom: 0,
                                    trailing: 8
                                )
                            )
                            .listRowBackground(Color.clear)
                            .allowsHitTesting(false)
                    }
                } header: {
                    SidebarLoadingSectionHeaderRow()
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            }
        }
        .listStyle(.sidebar)
        .id(sidebarProjectionFingerprint)
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }

    private func colorForCheckout(repo: SidebarRepo, in group: SidebarRepoGroup) -> Color {
        let overrideKey = repo.id.uuidString
        if let hex = checkoutColorByRepoId[overrideKey],
            let nsColor = NSColor(hex: hex)
        {
            return Color(nsColor: nsColor)
        }

        let orderedFamilies = group.repos.sorted { lhs, rhs in
            lhs.stableKey.localizedCaseInsensitiveCompare(rhs.stableKey) == .orderedAscending
        }

        guard orderedFamilies.count > 1 else {
            return Color(nsColor: NSColor(hex: SidebarRepoGrouping.automaticPaletteHexes[0]) ?? .controlAccentColor)
        }

        guard let familyIndex = orderedFamilies.firstIndex(where: { $0.id == repo.id }) else {
            return Color(nsColor: NSColor(hex: SidebarRepoGrouping.automaticPaletteHexes[0]) ?? .controlAccentColor)
        }

        let colorHex = SidebarRepoGrouping.colorHexForCheckoutIndex(
            familyIndex,
            seed: "\(group.id)|\(repo.stableKey)|\(repo.id.uuidString)"
        )
        return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
    }

    private func isGroupExpanded(_ groupId: String) -> Bool {
        isFiltering || expandedGroups.contains(groupId)
    }

    private func toggleGroupExpansion(_ groupId: String) {
        guard !isFiltering else { return }

        if expandedGroups.contains(groupId) {
            expandedGroups.remove(groupId)
        } else {
            expandedGroups.insert(groupId)
        }
        uiStore.setExpandedGroups(expandedGroups)
    }

    private func resolvedWorktreeContext(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID
    ) -> (group: SidebarRepoGroup, repo: SidebarRepo, worktree: Worktree)? {
        guard let group = groups.first(where: { $0.id == groupId }) else { return nil }
        guard let repo = group.repos.first(where: { $0.id == repoId }) else { return nil }
        guard let worktree = repo.worktrees.first(where: { $0.id == worktreeId }) else { return nil }
        return (group, repo, worktree)
    }

    private func clearNotifications(for worktreeId: UUID) {
        notificationCountsByWorktreeId[worktreeId] = 0
    }

    private func checkoutTitle(for worktree: Worktree, in repo: SidebarRepo) -> String {
        let folderName = worktree.path.lastPathComponent
        if !folderName.isEmpty {
            return folderName
        }
        return repo.name
    }

    private func checkoutIconKind(for worktree: Worktree, in repo: SidebarRepo) -> SidebarCheckoutIconKind {
        let isMainCheckout =
            worktree.isMainWorktree
            || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path

        if !isMainCheckout {
            return .gitWorktree
        }

        return repo.worktrees.count > 1 ? .mainCheckout : .standaloneCheckout
    }

    private func branchName(for worktree: Worktree) -> String {
        Self.resolvedBranchName(
            worktree: worktree,
            enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
        )
    }

    private func hideFilter() {
        filterText = ""
        debouncedQuery = ""
        isFilterFocused = false
        withAnimation(.easeOut(duration: 0.15)) {
            isFilterVisible = false
        }
        uiStore.setFilterText("")
        uiStore.setFilterVisible(false)
        postAppEvent(.refocusTerminalRequested)
    }

    private func openRepoInFinder(_ path: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
    }

}

enum SidebarListEntry: Identifiable {
    case resolvedGroupHeader(SidebarRepoGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID)

    var id: String {
        switch self {
        case .resolvedGroupHeader(let group):
            return "group:\(group.id)"
        case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId):
            return "worktree:\(groupId):\(repoId.uuidString):\(worktreeId.uuidString)"
        }
    }
}

private struct SidebarGroupRow: View {
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            OcticonImage(name: "octicon-repo", size: AppStyle.sidebarGroupIconSize)
                .foregroundStyle(.secondary)

            HStack(spacing: AppStyle.sidebarGroupTitleSpacing) {
                Text(repoTitle)
                    .font(.system(size: AppStyle.textLg, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)

                if let organizationName, !organizationName.isEmpty {
                    Text("·")
                        .font(.system(size: AppStyle.textSm, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(organizationName)
                        .font(.system(size: AppStyle.sidebarGroupOrganizationFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: AppStyle.sidebarGroupOrganizationMaxWidth, alignment: .leading)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppStyle.sidebarGroupRowVerticalPadding)
        .contentShape(Rectangle())
    }
}

private struct SidebarResolvedGroupHeaderRow: View {
    let isExpanded: Bool
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyle.spacingTight) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: AppStyle.textXs, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppStyle.textBase, alignment: .center)

            SidebarGroupRow(
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarWorktreeRow: View {
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
                Label("Open in New Tab", systemImage: "plus.rectangle")
            }

            Button {
                onOpenInPane()
            } label: {
                Label("Open in Pane (Split)", systemImage: "rectangle.split.2x1")
            }

            Divider()

            Button {
                onOpen()
            } label: {
                Label("Go to Terminal", systemImage: "terminal")
            }

            Button {
                openInCursor()
            } label: {
                Label("Open in Cursor", systemImage: "cursorarrow.rays")
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
            }

            Divider()

            Menu("Set Icon Color") {
                ForEach(SidebarRepoGrouping.colorPresets, id: \.hex) { preset in
                    Button(preset.name) {
                        onSetIconColor(preset.hex)
                    }
                }
                Divider()
                Button("Reset to Default") {
                    onSetIconColor(nil)
                }
            }
        }
    }

    private func openInCursor() {
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [worktree.path],
            withApplicationAt: cursorURL,
            configuration: config
        )
    }

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
        case .standaloneCheckout:
            OcticonImage(name: "octicon-git-merge", size: checkoutTypeSize)
                .foregroundStyle(iconColor)
        }
    }
}

private struct SidebarLoadingSectionHeaderRow: View {
    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: AppStyle.spacingTight) {
                ProgressView()
                    .controlSize(.small)

                Text("Scanning...")
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, AppStyle.spacingStandard)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarLoadingRepoRow: View {
    let repoName: String

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            Text(repoName)
                .font(.system(size: AppStyle.textBase))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.55)
    }
}

private enum SidebarCheckoutIconKind {
    case mainCheckout
    case gitWorktree
    case standaloneCheckout
}

private struct SidebarChip: View {
    enum Style {
        case neutral
        case info
        case success
        case warning
        case danger
        case accent(Color)

        var foreground: Color {
            switch self {
            case .neutral: return .secondary
            case .info: return Color(red: 0.47, green: 0.69, blue: 0.96)
            case .success: return Color(red: 0.42, green: 0.84, blue: 0.50)
            case .warning: return Color(red: 0.93, green: 0.71, blue: 0.34)
            case .danger: return Color(red: 0.93, green: 0.41, blue: 0.41)
            case .accent(let color): return color
            }
        }
    }

    let iconAsset: String
    let text: String?
    let style: Style

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            OcticonImage(name: iconAsset, size: AppStyle.sidebarChipIconSize)
            if let text {
                Text(text)
                    .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(
            .horizontal,
            text == nil ? AppStyle.sidebarChipIconOnlyHorizontalPadding : AppStyle.sidebarChipHorizontalPadding
        )
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(style.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct SidebarStatusSyncChip: View {
    let aheadText: String
    let behindText: String
    let hasSyncSignal: Bool

    private var effectiveStyle: SidebarChip.Style {
        hasSyncSignal ? .info : .neutral
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            HStack(spacing: AppStyle.sidebarSyncClusterSpacing) {
                OcticonImage(name: "octicon-arrow-up", size: AppStyle.sidebarSyncChipIconSize)
                Text(aheadText)
            }
            HStack(spacing: AppStyle.sidebarSyncClusterSpacing) {
                OcticonImage(name: "octicon-arrow-down", size: AppStyle.sidebarSyncChipIconSize)
                Text(behindText)
            }
        }
        .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyle.sidebarChipHorizontalPadding)
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(effectiveStyle.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct SidebarDiffChip: View {
    let linesAdded: Int
    let linesDeleted: Int
    let showsDirtyIndicator: Bool
    let isMuted: Bool

    private var plusColor: Color {
        if isMuted {
            return SidebarChip.Style.neutral.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
        }
        return Color(red: 0.42, green: 0.84, blue: 0.50).opacity(AppStyle.sidebarChipForegroundOpacity)
    }

    private var minusColor: Color {
        if isMuted {
            return SidebarChip.Style.neutral.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
        }
        return Color(red: 0.93, green: 0.41, blue: 0.41).opacity(AppStyle.sidebarChipForegroundOpacity)
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            if showsDirtyIndicator {
                OcticonImage(name: "octicon-dot-fill", size: AppStyle.sidebarChipIconSize)
                    .foregroundStyle(SidebarChip.Style.danger.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
            }

            HStack(spacing: AppStyle.spacingTight) {
                Text("+\(linesAdded)")
                    .foregroundStyle(plusColor)
                Text("-\(linesDeleted)")
                    .foregroundStyle(minusColor)
            }
        }
        .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyle.sidebarChipHorizontalPadding)
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct OcticonImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = SidebarOcticonLoader.shared.image(named: name) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
private final class SidebarOcticonLoader {
    static let shared = SidebarOcticonLoader()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        let subdirectory = "SidebarIcons.xcassets/\(name).imageset"
        if let svgURL = Bundle.module.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: svgURL)
        {
            cache[name] = image
            return image
        }

        if let pdfURL = Bundle.module.url(
            forResource: name,
            withExtension: "pdf",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: pdfURL)
        {
            cache[name] = image
            return image
        }

        return nil
    }
}

struct SidebarRepoGroup: Identifiable {
    let id: String
    let repoTitle: String
    let organizationName: String?
    let repos: [SidebarRepo]

    var checkoutCount: Int {
        repos.reduce(0) { $0 + $1.worktrees.count }
    }
}

struct SidebarRepo: Identifiable, Hashable, SidebarFilterableRepository {
    let id: UUID
    let name: String
    let repoPath: URL
    let stableKey: String
    var worktrees: [Worktree]

    init(
        id: UUID,
        name: String,
        repoPath: URL,
        stableKey: String,
        worktrees: [Worktree]
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.stableKey = stableKey
        self.worktrees = worktrees
    }

    init(repo: Repo) {
        self.init(
            id: repo.id,
            name: repo.name,
            repoPath: repo.repoPath,
            stableKey: repo.stableKey,
            worktrees: repo.worktrees
        )
    }

    var sidebarRepoName: String { name }

    var sidebarWorktrees: [Worktree] {
        get { worktrees }
        set { worktrees = newValue }
    }
}

struct RepoIdentityMetadata: Sendable {
    let groupKey: String
    let displayName: String
    let repoName: String
    let worktreeCommonDirectory: String?
    let folderCwd: String
    let parentFolder: String
    let organizationName: String?
    let originRemote: String?
    let upstreamRemote: String?
    let lastPathComponent: String
    let worktreeCwds: [String]
    let remoteFingerprint: String?
    let remoteSlug: String?
}

struct GitBranchStatus: Equatable, Sendable {
    enum SyncState: Equatable, Sendable {
        case synced
        case ahead(Int)
        case behind(Int)
        case diverged(ahead: Int, behind: Int)
        case noUpstream
        case unknown
    }

    let isDirty: Bool
    let syncState: SyncState
    let prCount: Int?
    let linesAdded: Int
    let linesDeleted: Int

    static let unknown = Self(isDirty: false, syncState: .unknown, prCount: nil, linesAdded: 0, linesDeleted: 0)
}

extension RepoSidebarContentView {
    static func buildListEntries(
        groups: [SidebarRepoGroup],
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [SidebarListEntry] {
        var entries: [SidebarListEntry] = []

        for group in groups {
            entries.append(.resolvedGroupHeader(group))

            let shouldExpandGroup = isFiltering || expandedGroupIds.contains(group.id)
            guard shouldExpandGroup else { continue }

            for repo in group.repos {
                for worktree in sortedWorktrees(for: repo) {
                    entries.append(
                        .resolvedWorktreeRow(
                            groupId: group.id,
                            repoId: repo.id,
                            worktreeId: worktree.id
                        )
                    )
                }
            }
        }

        return entries
    }

    static func projectionFingerprint(for projection: SidebarProjection) -> String {
        let resolvedGroupsFingerprint = projection.resolvedGroups.map { group in
            let repoIds = group.repos.map(\.id.uuidString).joined(separator: ",")
            return "\(group.id):\(repoIds)"
        }
        .joined(separator: "|")

        let loadingFingerprint = projection.loadingRepos
            .map { "\($0.id.uuidString):\($0.name)" }
            .joined(separator: "|")

        return """
            resolved[\(resolvedGroupsFingerprint)]\
            /loading[\(loadingFingerprint)]\
            /noResults[\(projection.showsNoResults)]
            """
    }

    static func projectSidebar(
        repos: [SidebarRepo],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        query: String
    ) -> SidebarProjection {
        let resolvedRepos = resolvedRepos(repos, enrichmentByRepoId: repoEnrichmentByRepoId)
        let loadingRepos = loadingRepos(repos, enrichmentByRepoId: repoEnrichmentByRepoId)
        let filteredResolvedRepos = SidebarFilter.filter(repos: resolvedRepos, query: query)
        let filteredLoadingRepos = filterLoadingRepos(loadingRepos, query: query)
        let repoMetadataById = buildRepoMetadata(
            repos: filteredResolvedRepos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId
        )
        let resolvedGroups = SidebarRepoGrouping.buildGroups(
            repos: filteredResolvedRepos,
            metadataByRepoId: repoMetadataById
        )

        return SidebarProjection(
            resolvedGroups: resolvedGroups,
            loadingRepos: filteredLoadingRepos,
            showsNoResults: !query.isEmpty && resolvedGroups.isEmpty && filteredLoadingRepos.isEmpty
        )
    }

    static func resolvedRepos(
        _ repos: [SidebarRepo],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [SidebarRepo] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return true
            case .awaitingOrigin, .none:
                return false
            }
        }
    }

    static func loadingRepos(
        _ repos: [SidebarRepo],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [SidebarRepo] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return false
            case .awaitingOrigin, .none:
                return true
            }
        }
    }

    private static func filterLoadingRepos(
        _ repos: [SidebarRepo],
        query: String
    ) -> [SidebarRepo] {
        let filteredRepos: [SidebarRepo]
        if query.isEmpty {
            filteredRepos = repos
        } else {
            filteredRepos = repos.filter { repo in
                repo.name.localizedCaseInsensitiveContains(query)
            }
        }

        return filteredRepos.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func primaryRepoForGroup(_ group: SidebarRepoGroup) -> SidebarRepo? {
        group.repos.max { lhs, rhs in
            let lhsScore = primaryRepoScore(lhs)
            let rhsScore = primaryRepoScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
        }
    }

    private static func primaryRepoScore(_ repo: SidebarRepo) -> Int {
        let normalizedRepoPath = repo.repoPath.standardizedFileURL.path
        if repo.worktrees.contains(where: { $0.path.standardizedFileURL.path == normalizedRepoPath }) {
            return 2
        }
        if repo.worktrees.contains(where: \.isMainWorktree) {
            return 1
        }
        return 0
    }

    static func buildRepoMetadata(
        repos: [SidebarRepo],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [UUID: RepoIdentityMetadata] {
        var metadataByRepoId: [UUID: RepoIdentityMetadata] = [:]
        metadataByRepoId.reserveCapacity(repos.count)

        for repo in repos {
            let enrichment = repoEnrichmentByRepoId[repo.id]
            let normalizedRepoPath = repo.repoPath.standardizedFileURL.path

            let groupKey: String
            let displayName: String
            let organizationName: String?
            let originRemote: String?
            let upstreamRemote: String?
            let remoteSlug: String?

            switch enrichment {
            case .resolvedRemote(_, let raw, let identity, _):
                groupKey = identity.groupKey
                displayName = identity.displayName
                organizationName = identity.organizationName
                originRemote = raw.origin
                upstreamRemote = raw.upstream
                remoteSlug = identity.remoteSlug
            case .resolvedLocal(_, let identity, _):
                groupKey = identity.groupKey
                displayName = identity.displayName
                organizationName = identity.organizationName
                originRemote = nil
                upstreamRemote = nil
                remoteSlug = identity.remoteSlug
            case .awaitingOrigin, nil:
                groupKey = "path:\(normalizedRepoPath)"
                displayName = repo.name
                organizationName = nil
                originRemote = nil
                upstreamRemote = nil
                remoteSlug = nil
            }

            metadataByRepoId[repo.id] = RepoIdentityMetadata(
                groupKey: groupKey,
                displayName: displayName,
                repoName: displayName,
                worktreeCommonDirectory: nil,
                folderCwd: normalizedRepoPath,
                parentFolder: repo.repoPath.deletingLastPathComponent().lastPathComponent,
                organizationName: organizationName,
                originRemote: originRemote,
                upstreamRemote: upstreamRemote,
                lastPathComponent: repo.repoPath.lastPathComponent,
                worktreeCwds: repo.worktrees.map { $0.path.standardizedFileURL.path },
                remoteFingerprint: originRemote,
                remoteSlug: remoteSlug
            )
        }

        return metadataByRepoId
    }

    static func resolvedBranchName(
        worktree: Worktree,
        enrichment: WorktreeEnrichment?
    ) -> String {
        let cachedBranch = enrichment?.branch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cachedBranch.isEmpty {
            return cachedBranch
        }

        return "detached HEAD"
    }

    static func mergeBranchStatuses(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestCountsByWorktreeId: [UUID: Int]
    ) -> [UUID: GitBranchStatus] {
        let allWorktreeIds = Set(worktreeEnrichmentsByWorktreeId.keys).union(pullRequestCountsByWorktreeId.keys)
        var mergedByWorktreeId: [UUID: GitBranchStatus] = [:]
        mergedByWorktreeId.reserveCapacity(allWorktreeIds.count)

        for worktreeId in allWorktreeIds {
            let enrichment = worktreeEnrichmentsByWorktreeId[worktreeId]
            let pullRequestCount = pullRequestCountsByWorktreeId[worktreeId]
            mergedByWorktreeId[worktreeId] = branchStatus(
                enrichment: enrichment,
                pullRequestCount: pullRequestCount
            )
        }

        return mergedByWorktreeId
    }

    static func branchStatus(
        enrichment: WorktreeEnrichment?,
        pullRequestCount: Int?
    ) -> GitBranchStatus {
        guard let enrichment else {
            return GitBranchStatus(
                isDirty: GitBranchStatus.unknown.isDirty,
                syncState: GitBranchStatus.unknown.syncState,
                prCount: pullRequestCount,
                linesAdded: GitBranchStatus.unknown.linesAdded,
                linesDeleted: GitBranchStatus.unknown.linesDeleted
            )
        }

        let summary = enrichment.snapshot?.summary
        let isDirty: Bool
        if let summary {
            isDirty = summary.changed > 0 || summary.staged > 0 || summary.untracked > 0
        } else {
            isDirty = false
        }

        let syncState: GitBranchStatus.SyncState
        if let summary {
            switch summary.hasUpstream {
            case .some(false):
                syncState = .noUpstream
            case .some(true):
                let ahead = summary.aheadCount ?? 0
                let behind = summary.behindCount ?? 0
                if ahead > 0 && behind > 0 {
                    syncState = .diverged(ahead: ahead, behind: behind)
                } else if ahead > 0 {
                    syncState = .ahead(ahead)
                } else if behind > 0 {
                    syncState = .behind(behind)
                } else if summary.aheadCount != nil || summary.behindCount != nil {
                    syncState = .synced
                } else {
                    syncState = .unknown
                }
            case .none:
                syncState = .unknown
            }
        } else {
            syncState = .unknown
        }
        return GitBranchStatus(
            isDirty: isDirty,
            syncState: syncState,
            prCount: pullRequestCount,
            linesAdded: summary?.linesAdded ?? 0,
            linesDeleted: summary?.linesDeleted ?? 0
        )
    }

    static func sortedWorktrees(for repo: SidebarRepo) -> [Worktree] {
        repo.worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

enum SidebarRepoGrouping {
    struct ColorPreset {
        let name: String
        let hex: String
    }

    private struct OwnerCandidate {
        let repoId: UUID
        let repoWorktreeCount: Int
        let repoPathMatchesWorktree: Bool
        let isMainWorktree: Bool
        let stableTieBreaker: String
    }

    static let automaticPaletteHexes: [String] = [
        "#F5C451",  // 1: Yellow
        "#58C4FF",  // 2: Sky
        "#A78BFA",  // 3: Violet
        "#4ADE80",  // 4: Green
        "#FB923C",  // 5: Orange
        "#F472B6",  // 6: Pink
    ]

    static let colorPresets: [ColorPreset] = [
        ColorPreset(name: "Yellow", hex: "#F5C451"),
        ColorPreset(name: "Sky", hex: "#58C4FF"),
        ColorPreset(name: "Violet", hex: "#A78BFA"),
        ColorPreset(name: "Green", hex: "#4ADE80"),
        ColorPreset(name: "Orange", hex: "#FB923C"),
        ColorPreset(name: "Pink", hex: "#F472B6"),
    ]

    static func colorHexForCheckoutIndex(_ index: Int, seed: String) -> String {
        if index < automaticPaletteHexes.count {
            return automaticPaletteHexes[index]
        }

        return generatedColorHex(seed: seed)
    }

    private static func generatedColorHex(seed: String) -> String {
        let hash = seed.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 33 &+ Int(scalar.value)) & 0x7fff_ffff
        }
        let hue = CGFloat(hash % 360) / 360.0
        let saturation: CGFloat = 0.58
        let brightness: CGFloat = 0.94
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0).hexString
    }

    static func buildGroups(
        repos: [SidebarRepo],
        metadataByRepoId: [UUID: RepoIdentityMetadata]
    ) -> [SidebarRepoGroup] {
        let grouped = Dictionary(grouping: repos) { repo in
            metadataByRepoId[repo.id]?.groupKey ?? "path:\(repo.repoPath.standardizedFileURL.path)"
        }

        return grouped.compactMap { groupKey, groupRepos in
            let deduplicatedRepos = dedupeReposByCheckoutCwd(groupRepos)
            guard !deduplicatedRepos.isEmpty else { return nil }

            let firstRepoId = deduplicatedRepos.first?.id ?? groupRepos.first?.id
            let metadata = firstRepoId.flatMap { metadataByRepoId[$0] }
            let repoTitle =
                metadata?.repoName
                ?? metadata?.lastPathComponent
                ?? deduplicatedRepos.first?.name
                ?? "Repository"
            return SidebarRepoGroup(
                id: groupKey,
                repoTitle: repoTitle,
                organizationName: metadata?.organizationName,
                repos: deduplicatedRepos.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            let leftTitle = lhs.organizationName.map { "\(lhs.repoTitle)\($0)" } ?? lhs.repoTitle
            let rightTitle = rhs.organizationName.map { "\(rhs.repoTitle)\($0)" } ?? rhs.repoTitle
            return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
        }
    }

    private static func dedupeReposByCheckoutCwd(_ repos: [SidebarRepo]) -> [SidebarRepo] {
        var ownerByCwd: [String: OwnerCandidate] = [:]

        for repo in repos {
            for worktree in repo.worktrees {
                let checkoutCwd = normalizedCwdPath(worktree.path)
                let candidate = OwnerCandidate(
                    repoId: repo.id,
                    repoWorktreeCount: repo.worktrees.count,
                    repoPathMatchesWorktree: normalizedCwdPath(repo.repoPath) == checkoutCwd,
                    isMainWorktree: worktree.isMainWorktree,
                    stableTieBreaker: "\(repo.id.uuidString)|\(worktree.id.uuidString)"
                )

                if let existing = ownerByCwd[checkoutCwd] {
                    if shouldPrefer(candidate: candidate, over: existing) {
                        ownerByCwd[checkoutCwd] = candidate
                    }
                } else {
                    ownerByCwd[checkoutCwd] = candidate
                }
            }
        }

        var deduplicatedRepos: [SidebarRepo] = []
        for repo in repos {
            guard !repo.worktrees.isEmpty else { continue }

            var seenWorktreeCwds: Set<String> = []
            let deduplicatedWorktrees = repo.worktrees.filter { worktree in
                let checkoutCwd = normalizedCwdPath(worktree.path)
                guard !seenWorktreeCwds.contains(checkoutCwd) else { return false }
                seenWorktreeCwds.insert(checkoutCwd)
                return ownerByCwd[checkoutCwd]?.repoId == repo.id
            }

            guard !deduplicatedWorktrees.isEmpty else { continue }

            var updated = repo
            updated.worktrees = deduplicatedWorktrees
            deduplicatedRepos.append(updated)
        }

        return deduplicatedRepos
    }

    private static func shouldPrefer(
        candidate: OwnerCandidate,
        over existing: OwnerCandidate
    ) -> Bool {
        if candidate.repoWorktreeCount != existing.repoWorktreeCount {
            return candidate.repoWorktreeCount > existing.repoWorktreeCount
        }
        if candidate.repoPathMatchesWorktree != existing.repoPathMatchesWorktree {
            return candidate.repoPathMatchesWorktree
        }
        if candidate.isMainWorktree != existing.isMainWorktree {
            return candidate.isMainWorktree
        }
        return candidate.stableTieBreaker.localizedCaseInsensitiveCompare(existing.stableTieBreaker)
            == .orderedAscending
    }

    private static func normalizedCwdPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

extension NSColor {
    fileprivate convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat(value & 0xff) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    fileprivate var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        let red = Int((rgb.redComponent * 255.0).rounded())
        let green = Int((rgb.greenComponent * 255.0).rounded())
        let blue = Int((rgb.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// swiftlint:enable file_length
