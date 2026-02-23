import AppKit
import Foundation
import SwiftUI

/// Redesigned sidebar content grouped by repository identity (worktree family / remote).
@MainActor
struct RepoSidebarContentView: View {
    let store: WorkspaceStore

    @State private var expandedGroups: Set<String> = Self.loadExpandedGroups()
    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isFilterVisible: Bool = false
    @FocusState private var isFilterFocused: Bool

    @State private var repoMetadataById: [UUID: RepoIdentityMetadata] = [:]
    @State private var worktreeStatusById: [UUID: GitBranchStatus] = [:]
    @State private var checkoutColorByRepoId: [String: String] = Self.loadCheckoutColors()
    @State private var notificationCountsByWorktreeId: [UUID: Int] = [:]

    @State private var debounceTask: Task<Void, Never>?
    @State private var metadataReloadTask: Task<Void, Never>?

    private static let filterDebounceMilliseconds = 25
    private static let expandedGroupsKey = "sidebarExpandedRepoGroups"
    private static let checkoutColorsKey = "sidebarCheckoutIconColors"

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
        .onReceive(NotificationCenter.default.publisher(for: .addRepoRequested)) { _ in
            addRepo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addFolderRequested)) { _ in
            addFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWorktreesRequested)) { _ in
            refreshWorktrees()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterSidebarRequested)) { _ in
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .worktreeBellRang)) { notification in
            guard
                let paneId = notification.userInfo?["paneId"] as? UUID,
                let pane = store.pane(paneId),
                let worktreeId = pane.worktreeId
            else { return }
            notificationCountsByWorktreeId[worktreeId, default: 0] += 1
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
                        title: group.title,
                        checkoutCount: group.checkoutCount
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
        NotificationCenter.default.post(name: .refocusTerminalRequested, object: nil)
    }

    private func addRepo() {
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

            if GitRepositoryInspector.isGitRepository(at: url) {
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
                addFolder(startingAt: url)
                return
            default:
                return
            }
        }
    }

    private func addFolder(startingAt initialURL: URL? = nil) {
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

        let scanner = RepoScanner()
        let repoPaths = scanner.scanForGitRepos(in: rootURL, maxDepth: 3)

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
        guard !store.repos.contains(where: { $0.repoPath == path }) else { return }
        let repo = store.addRepo(at: path)
        let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
        store.updateRepoWorktrees(repo.id, worktrees: worktrees)
    }

    private func refreshWorktrees() {
        for repo in store.repos {
            let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
            store.updateRepoWorktrees(repo.id, worktrees: worktrees)
        }
    }

    private func reloadMetadataAndStatus() {
        metadataReloadTask?.cancel()
        let reposSnapshot = store.repos
        let loadInput = SidebarStatusLoadInput(
            repos: reposSnapshot.map { repo in
                RepoStatusInput(
                    repoId: repo.id,
                    repoName: repo.name,
                    repoPath: repo.repoPath
                )
            },
            worktrees: reposSnapshot.flatMap { repo in
                repo.worktrees.map { worktree in
                    WorktreeStatusInput(
                        worktreeId: worktree.id,
                        path: worktree.path,
                        branch: worktree.branch
                    )
                }
            }
        )
        let expectedFingerprint = reposFingerprint

        metadataReloadTask = Task {
            let initialSnapshot = await GitRepositoryInspector.metadataAndStatus(for: loadInput)
            guard !Task.isCancelled else { return }
            guard expectedFingerprint == reposFingerprint else { return }

            repoMetadataById = initialSnapshot.metadataByRepoId
            worktreeStatusById = initialSnapshot.statusByWorktreeId

            // Stage PR metadata after first paint so startup remains responsive.
            let prCounts = await GitRepositoryInspector.prCounts(for: loadInput.worktrees)
            guard !Task.isCancelled else { return }
            guard expectedFingerprint == reposFingerprint else { return }
            guard !prCounts.isEmpty else { return }

            for (worktreeId, prCount) in prCounts {
                guard let status = worktreeStatusById[worktreeId] else { continue }
                worktreeStatusById[worktreeId] = GitBranchStatus(
                    isDirty: status.isDirty,
                    syncState: status.syncState,
                    prCount: prCount,
                    linesAdded: status.linesAdded,
                    linesDeleted: status.linesDeleted
                )
            }
        }
    }
}

private struct SidebarGroupRow: View {
    let title: String
    let checkoutCount: Int

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            OcticonImage(name: "octicon-repo", size: AppStyle.sidebarGroupIconSize)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: AppStyle.textLg, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Text("\(checkoutCount)")
                .font(.system(size: AppStyle.textSm, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppStyle.sidebarCountBadgeHorizontalPadding)
                .padding(.vertical, AppStyle.sidebarCountBadgeVerticalPadding)
                .background(Color.secondary.opacity(AppStyle.sidebarCountBadgeBackgroundOpacity))
                .clipShape(Capsule())
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
            HStack(spacing: AppStyle.spacingStandard) {
                checkoutTypeIcon

                Text(checkoutTitle)
                    .font(
                        .system(size: AppStyle.textBase, weight: checkoutIconKind == .mainCheckout ? .medium : .regular)
                    )
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack(spacing: AppStyle.spacingStandard) {
                OcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
                    .foregroundStyle(.secondary)
                Text(branchName)
                    .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: AppStyle.spacingStandard)
            }

            HStack(spacing: AppStyle.sidebarChipRowSpacing) {
                HStack(spacing: AppStyle.spacingTight) {
                    Text("+\(lineDiffCounts.added)")
                        .foregroundStyle(Color(red: 0.42, green: 0.84, blue: 0.50))
                    Text("-\(lineDiffCounts.deleted)")
                        .foregroundStyle(Color(red: 0.93, green: 0.41, blue: 0.41))
                }
                .font(.system(size: AppStyle.textXs, weight: .medium).monospacedDigit())

                SidebarStatusSyncChip(
                    statusIconAsset: branchStatus.isDirty ? "octicon-dot-fill" : "octicon-check-circle-fill",
                    statusStyle: branchStatus.isDirty ? .warning : .success,
                    aheadText: syncCounts.ahead,
                    behindText: syncCounts.behind,
                    style: syncChipStyle
                )
                SidebarChip(
                    iconAsset: "octicon-git-pull-request",
                    text: "\(branchStatus.prCount ?? 0)",
                    style: .neutral
                )
                SidebarChip(
                    iconAsset: "octicon-bell",
                    text: "\(notificationCount)",
                    style: .neutral
                )
            }
        }
        .padding(.vertical, AppStyle.sidebarRowVerticalInset)
        .padding(.horizontal, AppStyle.spacingTight)
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

    private var syncChipStyle: SidebarChip.Style {
        switch branchStatus.syncState {
        case .synced:
            return .success
        case .ahead, .behind, .diverged:
            return .info
        case .noUpstream, .unknown:
            return .warning
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

        var foreground: Color {
            switch self {
            case .neutral: return .secondary
            case .info: return Color(red: 0.47, green: 0.69, blue: 0.96)
            case .success: return Color(red: 0.42, green: 0.84, blue: 0.50)
            case .warning: return Color(red: 0.93, green: 0.71, blue: 0.34)
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
        .background(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
        .foregroundStyle(style.foreground)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct SidebarStatusSyncChip: View {
    let statusIconAsset: String
    let statusStyle: SidebarChip.Style
    let aheadText: String
    let behindText: String
    let style: SidebarChip.Style

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            OcticonImage(name: statusIconAsset, size: AppStyle.sidebarChipIconSize)
                .foregroundStyle(statusStyle.foreground)
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
        .background(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
        .foregroundStyle(style.foreground)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .clipShape(Capsule())
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

private struct SidebarRepoGroup: Identifiable {
    let id: String
    let title: String
    let repos: [Repo]

    var checkoutCount: Int {
        repos.reduce(0) { $0 + max($1.worktrees.count, 1) }
    }
}

struct RepoIdentityMetadata: Sendable {
    let groupKey: String
    let displayName: String
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

private enum SidebarRepoGrouping {
    struct ColorPreset {
        let name: String
        let hex: String
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

        return grouped.map { groupKey, groupRepos in
            let firstRepoId = groupRepos.first?.id
            let displayName =
                firstRepoId.flatMap { metadataByRepoId[$0]?.displayName }
                ?? groupRepos.first?.name
                ?? "Repository"
            return SidebarRepoGroup(
                id: groupKey,
                title: displayName,
                repos: groupRepos.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
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
