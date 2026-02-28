import AppKit
import Foundation
import SwiftUI

// swiftlint:disable file_length

/// Redesigned sidebar content grouped by repository identity (worktree family / remote).
@MainActor
struct RepoSidebarContentView: View {
    let store: WorkspaceStore
    let workspaceGitStatusStore: WorkspaceGitStatusStore

    @State private var expandedGroups: Set<String> = Self.loadExpandedGroups()
    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isFilterVisible: Bool = false
    @FocusState private var isFilterFocused: Bool

    @State private var repoMetadataById: [UUID: RepoIdentityMetadata] = [:]
    @State private var pullRequestCountByWorktreeId: [UUID: Int] = [:]
    @State private var checkoutColorByRepoId: [String: String] = Self.loadCheckoutColors()
    @State private var notificationCountsByWorktreeId: [UUID: Int] = [:]

    @State private var debounceTask: Task<Void, Never>?
    @State private var metadataReloadTask: Task<Void, Never>?

    private static let filterDebounceMilliseconds = 25
    private static let expandedGroupsKey = "sidebarExpandedRepoGroups"
    private static let checkoutColorsKey = "sidebarCheckoutIconColors"
    private static let initialMetadataReloadDelay: Duration = .milliseconds(120)

    init(
        store: WorkspaceStore,
        workspaceGitStatusStore: WorkspaceGitStatusStore = .shared
    ) {
        self.store = store
        self.workspaceGitStatusStore = workspaceGitStatusStore
    }

    private var reposFingerprint: String {
        store.repos.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate)" }
            .joined(separator: "|")
    }

    private var filteredRepos: [Repo] {
        SidebarFilter.filter(repos: store.repos, query: debouncedQuery)
    }

    private var groups: [SidebarRepoGroup] {
        SidebarRepoGrouping.buildGroups(repos: filteredRepos, metadataByRepoId: repoMetadataById)
    }

    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    private var worktreeStatusById: [UUID: GitBranchStatus] {
        Self.mergeBranchStatuses(
            localSnapshotsByWorktreeId: workspaceGitStatusStore.snapshotsByWorktreeId,
            pullRequestCountsByWorktreeId: pullRequestCountByWorktreeId
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFilterVisible {
                filterBar
            }

            if isFiltering && groups.isEmpty {
                noResultsView
            } else {
                groupList
            }
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 0)
        .task(id: reposFingerprint) {
            reloadMetadataAndStatus()
        }
        .task {
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                switch event {
                case .addRepoRequested:
                    await addRepo()
                case .addFolderRequested:
                    await addFolder()
                case .refreshWorktreesRequested:
                    refreshWorktrees()
                case .filterSidebarRequested:
                    withAnimation(.easeOut(duration: 0.15)) {
                        if isFilterVisible {
                            hideFilter()
                        } else {
                            isFilterVisible = true
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
            metadataReloadTask?.cancel()
        }
        .onChange(of: filterText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
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
            ForEach(groups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { isFiltering || expandedGroups.contains(group.id) },
                        set: { expanded in
                            if expanded {
                                expandedGroups.insert(group.id)
                            } else {
                                expandedGroups.remove(group.id)
                            }
                            saveExpandedGroups()
                        }
                    )
                ) {
                    VStack(spacing: AppStyle.sidebarGroupChildrenSpacing) {
                        ForEach(group.repos) { repo in
                            let sortedWorktrees = sortedWorktrees(for: repo)
                            ForEach(sortedWorktrees) { worktree in
                                SidebarWorktreeRow(
                                    worktree: worktree,
                                    checkoutTitle: checkoutTitle(for: worktree, in: repo),
                                    branchName: worktree.branch.isEmpty ? "detached HEAD" : worktree.branch,
                                    checkoutIconKind: checkoutIconKind(for: worktree, in: repo),
                                    iconColor: colorForCheckout(repo: repo, in: group),
                                    branchStatus: worktreeStatusById[worktree.id] ?? .unknown,
                                    notificationCount: notificationCountsByWorktreeId[worktree.id, default: 0],
                                    onOpen: {
                                        clearNotifications(for: worktree.id)
                                        CommandDispatcher.shared.dispatch(
                                            .openWorktree,
                                            target: worktree.id,
                                            targetType: .worktree
                                        )
                                    },
                                    onOpenNew: {
                                        clearNotifications(for: worktree.id)
                                        CommandDispatcher.shared.dispatch(
                                            .openNewTerminalInTab,
                                            target: worktree.id,
                                            targetType: .worktree
                                        )
                                    },
                                    onOpenInPane: {
                                        clearNotifications(for: worktree.id)
                                        CommandDispatcher.shared.dispatch(
                                            .openWorktreeInPane,
                                            target: worktree.id,
                                            targetType: .worktree
                                        )
                                    },
                                    onSetIconColor: { colorHex in
                                        let key = repo.id.uuidString
                                        if let colorHex {
                                            checkoutColorByRepoId[key] = colorHex
                                        } else {
                                            checkoutColorByRepoId.removeValue(forKey: key)
                                        }
                                        saveCheckoutColors()
                                    }
                                )
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: AppStyle.sidebarListRowLeadingInset,
                                        bottom: 0,
                                        trailing: 0
                                    )
                                )
                            }
                        }
                    }
                    .padding(.leading, -AppStyle.sidebarGroupChildLeadingReduction)
                } label: {
                    SidebarGroupRow(
                        repoTitle: group.repoTitle,
                        organizationName: group.organizationName
                    )
                }
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

                    Button("Refresh Worktrees") {
                        for repo in group.repos {
                            let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
                            store.updateRepoWorktrees(repo.id, worktrees: worktrees)
                        }
                    }

                    Menu("Remove Checkout") {
                        ForEach(group.repos) { repo in
                            Button(repo.name, role: .destructive) {
                                store.removeRepo(repo.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }

    private static func loadExpandedGroups() -> Set<String> {
        guard let keys = UserDefaults.standard.stringArray(forKey: expandedGroupsKey) else { return [] }
        return Set(keys)
    }

    private func saveExpandedGroups() {
        UserDefaults.standard.set(Array(expandedGroups), forKey: Self.expandedGroupsKey)
    }

    private static func loadCheckoutColors() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: checkoutColorsKey) as? [String: String] ?? [:]
    }

    private func saveCheckoutColors() {
        UserDefaults.standard.set(checkoutColorByRepoId, forKey: Self.checkoutColorsKey)
    }

    private func colorForCheckout(repo: Repo, in group: SidebarRepoGroup) -> Color {
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

    private func sortedWorktrees(for repo: Repo) -> [Worktree] {
        repo.worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func clearNotifications(for worktreeId: UUID) {
        notificationCountsByWorktreeId[worktreeId] = 0
    }

    private func checkoutTitle(for worktree: Worktree, in repo: Repo) -> String {
        let folderName = worktree.path.lastPathComponent
        if !folderName.isEmpty {
            return folderName
        }
        return repo.name
    }

    private func checkoutIconKind(for worktree: Worktree, in repo: Repo) -> SidebarCheckoutIconKind {
        let isMainCheckout =
            worktree.isMainWorktree
            || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path

        if !isMainCheckout {
            return .gitWorktree
        }

        return repo.worktrees.count > 1 ? .mainCheckout : .standaloneCheckout
    }

    private func hideFilter() {
        filterText = ""
        debouncedQuery = ""
        isFilterFocused = false
        withAnimation(.easeOut(duration: 0.15)) {
            isFilterVisible = false
        }
        postAppEvent(.refocusTerminalRequested)
    }

    private func addRepo() async {
        var initialDirectory: URL?

        while true {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose one Git repository folder (.git required)."
            panel.prompt = "Add Repo"
            panel.directoryURL = initialDirectory

            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }

            if await GitRepositoryInspector.isGitRepository(at: url) {
                addRepoAndRefreshWorktrees(at: url)
                return
            }

            let alert = NSAlert()
            alert.messageText = "Not a Git Repository"
            alert.informativeText =
                "The selected folder is not a Git repo. You can choose another folder or scan this folder for repos."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Choose Another Folder")
            alert.addButton(withTitle: "Scan This Folder")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                initialDirectory = url.deletingLastPathComponent()
            case .alertSecondButtonReturn:
                await addFolder(startingAt: url)
                return
            default:
                return
            }
        }
    }

    private func addFolder(startingAt initialURL: URL? = nil) async {
        let rootURL: URL

        if let initialURL {
            rootURL = initialURL
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose a folder to scan for Git repositories."
            panel.prompt = "Scan Folder"

            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }
            rootURL = url
        }

        let repoPaths = await Self.scanForGitReposInBackground(rootURL: rootURL, maxDepth: 3)

        guard !repoPaths.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Git Repositories Found"
            alert.informativeText = "No folders with a Git repository were found under \(rootURL.lastPathComponent)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        for repoPath in repoPaths {
            addRepoAndRefreshWorktrees(at: repoPath)
        }
    }

    private func addRepoAndRefreshWorktrees(at path: URL) {
        guard !hasExistingCheckout(at: path) else { return }
        let repo = store.addRepo(at: path)
        let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
        store.updateRepoWorktrees(repo.id, worktrees: worktrees)
    }

    private func hasExistingCheckout(at path: URL) -> Bool {
        let normalizedTarget = normalizedCwdPath(path)

        for repo in store.repos {
            if normalizedCwdPath(repo.repoPath) == normalizedTarget {
                return true
            }
            if repo.worktrees.contains(where: { normalizedCwdPath($0.path) == normalizedTarget }) {
                return true
            }
        }

        return false
    }

    private func normalizedCwdPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private nonisolated static func scanForGitReposInBackground(rootURL: URL, maxDepth: Int) async -> [URL] {
        await Task(priority: .userInitiated) {
            RepoScanner().scanForGitRepos(in: rootURL, maxDepth: maxDepth)
        }.value
    }

    private func refreshWorktrees() {
        for repo in store.repos {
            let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
            store.updateRepoWorktrees(repo.id, worktrees: worktrees)
        }
    }

    private func reloadMetadataAndStatus() {
        metadataReloadTask?.cancel()
        // Patch behavior: whenever sidebar status reloads, refresh worktree discovery first
        // so branch labels and worktree mappings reflect current git state.
        refreshWorktrees()
        let reposSnapshot = store.repos
        let metadataLoadInput = SidebarStatusLoadInput(
            repos: reposSnapshot.map { repo in
                RepoStatusInput(
                    repoId: repo.id,
                    repoName: repo.name,
                    repoPath: repo.repoPath,
                    worktreePaths: repo.worktrees.map(\.path)
                )
            },
            worktrees: []
        )
        let worktreeInputs = reposSnapshot.flatMap { repo in
            repo.worktrees.map { worktree in
                WorktreeStatusInput(
                    worktreeId: worktree.id,
                    path: worktree.path,
                    branch: worktree.branch
                )
            }
        }

        metadataReloadTask = Task {
            // Defer initial sidebar metadata refresh until after the first List
            // layout pass to avoid NSTableView delegate reentrancy during startup.
            try? await Task.sleep(for: Self.initialMetadataReloadDelay)
            guard !Task.isCancelled else { return }

            let metadataSnapshot = await GitRepositoryInspector.metadataAndStatus(for: metadataLoadInput)
            guard !Task.isCancelled else { return }

            // Avoid mutating SwiftUI List-backed state in the same turn as
            // AppKit table delegate callbacks (can trigger reentrant warnings).
            await Task.yield()
            guard !Task.isCancelled else { return }

            repoMetadataById = metadataSnapshot.metadataByRepoId

            // Stage PR metadata after first paint so startup remains responsive.
            let prCounts = await GitRepositoryInspector.prCounts(for: worktreeInputs)
            guard !Task.isCancelled else { return }

            // Same reentrancy guard for incremental row updates.
            await Task.yield()
            guard !Task.isCancelled else { return }

            pullRequestCountByWorktreeId = prCounts
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
    let repos: [Repo]

    var checkoutCount: Int {
        repos.reduce(0) { $0 + $1.worktrees.count }
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
    static func mergeBranchStatuses(
        localSnapshotsByWorktreeId: [UUID: WorkspaceGitStatusStore.WorktreeSnapshot],
        pullRequestCountsByWorktreeId: [UUID: Int]
    ) -> [UUID: GitBranchStatus] {
        let allWorktreeIds = Set(localSnapshotsByWorktreeId.keys).union(pullRequestCountsByWorktreeId.keys)
        var mergedByWorktreeId: [UUID: GitBranchStatus] = [:]
        mergedByWorktreeId.reserveCapacity(allWorktreeIds.count)

        for worktreeId in allWorktreeIds {
            let localSnapshot = localSnapshotsByWorktreeId[worktreeId]
            let pullRequestCount = pullRequestCountsByWorktreeId[worktreeId]
            mergedByWorktreeId[worktreeId] = branchStatus(
                localSnapshot: localSnapshot,
                pullRequestCount: pullRequestCount
            )
        }

        return mergedByWorktreeId
    }

    static func branchStatus(
        localSnapshot: WorkspaceGitStatusStore.WorktreeSnapshot?,
        pullRequestCount: Int?
    ) -> GitBranchStatus {
        guard let localSnapshot else {
            return GitBranchStatus(
                isDirty: GitBranchStatus.unknown.isDirty,
                syncState: GitBranchStatus.unknown.syncState,
                prCount: pullRequestCount,
                linesAdded: GitBranchStatus.unknown.linesAdded,
                linesDeleted: GitBranchStatus.unknown.linesDeleted
            )
        }

        let summary = localSnapshot.summary
        let isDirty = summary.changed > 0 || summary.staged > 0 || summary.untracked > 0
        return GitBranchStatus(
            isDirty: isDirty,
            syncState: .unknown,
            prCount: pullRequestCount,
            linesAdded: 0,
            linesDeleted: 0
        )
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
        repos: [Repo],
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

    private static func dedupeReposByCheckoutCwd(_ repos: [Repo]) -> [Repo] {
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

        var deduplicatedRepos: [Repo] = []
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
