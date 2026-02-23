import AppKit
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
    @State private var groupColorByKey: [String: String] = Self.loadGroupColors()
    @State private var notificationCountsByWorktreeId: [UUID: Int] = [:]

    @State private var debounceTask: Task<Void, Never>?
    @State private var metadataReloadTask: Task<Void, Never>?

    private static let filterDebounceMilliseconds = 25
    private static let expandedGroupsKey = "sidebarExpandedRepoGroups"
    private static let groupColorsKey = "sidebarRepoGroupColors"

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
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("Filter...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
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
                        .font(.system(size: 12))
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
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .opacity(0.5)

            Text("No results")
                .font(.system(size: 12, weight: .medium))
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
                    VStack(spacing: 2) {
                        ForEach(group.repos) { repo in
                            let sortedWorktrees = sortedWorktrees(for: repo)
                            ForEach(sortedWorktrees) { worktree in
                                SidebarWorktreeRow(
                                    worktree: worktree,
                                    title: worktree.isMainWorktree
                                        ? "main checkout: \(worktree.branch)" : worktree.name,
                                    groupColor: colorForGroup(group.id),
                                    branchStatus: worktreeStatusById[worktree.id] ?? .unknown,
                                    openPaneCount: store.paneCount(for: worktree.id),
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
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0))
                            }
                        }
                    }
                } label: {
                    SidebarGroupRow(
                        title: group.title,
                        checkoutCount: group.checkoutCount,
                        color: colorForGroup(group.id)
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0))
                .contextMenu {
                    Menu("Set Color") {
                        ForEach(SidebarRepoGrouping.colorPresets, id: \.hex) { preset in
                            Button(preset.name) {
                                groupColorByKey[group.id] = preset.hex
                                saveGroupColors()
                            }
                        }
                        Divider()
                        Button("Reset to Auto") {
                            groupColorByKey.removeValue(forKey: group.id)
                            saveGroupColors()
                        }
                    }

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

    private static func loadGroupColors() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: groupColorsKey) as? [String: String] ?? [:]
    }

    private func saveGroupColors() {
        UserDefaults.standard.set(groupColorByKey, forKey: Self.groupColorsKey)
    }

    private func colorForGroup(_ groupKey: String) -> Color {
        if let hex = groupColorByKey[groupKey], let nsColor = NSColor(hex: hex) {
            return Color(nsColor: nsColor)
        }
        let fallback = SidebarRepoGrouping.defaultColorHex(for: groupKey)
        return Color(nsColor: NSColor(hex: fallback) ?? .controlAccentColor)
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
                    prCount: prCount
                )
            }
        }
    }
}

private struct SidebarGroupRow: View {
    let title: String
    let checkoutCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: AppStyle.fontPrimary, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Text("\(checkoutCount)")
                .font(.system(size: AppStyle.fontSmall, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct SidebarWorktreeRow: View {
    let worktree: Worktree
    let title: String
    let groupColor: Color
    let branchStatus: GitBranchStatus
    let openPaneCount: Int
    let notificationCount: Int
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onOpenInPane: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: AppStyle.spacingStandard) {
                if worktree.isMainWorktree {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(groupColor)
                } else {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(groupColor)
                }

                Text(title)
                    .font(.system(size: AppStyle.fontBody, weight: worktree.isMainWorktree ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack(spacing: 6) {
                SidebarChip(
                    text: branchStatus.isDirty ? "dirty" : "clean", style: branchStatus.isDirty ? .warning : .success)
                SidebarChip(text: branchStatus.syncLabel, style: .neutral)

                if let prCount = branchStatus.prCount {
                    SidebarChip(text: "pr:\(prCount)", style: .neutral)
                }

                SidebarChip(text: "open:\(openPaneCount)", style: .neutral)

                if notificationCount > 0 {
                    SidebarChip(text: "bell:\(notificationCount)", style: .info)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
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
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            }
        }
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(style.foreground.opacity(0.16))
            .foregroundStyle(style.foreground)
            .clipShape(Capsule())
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

    static let unknown = Self(isDirty: false, syncState: .unknown, prCount: nil)

    var syncLabel: String {
        switch syncState {
        case .synced:
            return "synced"
        case .ahead(let count):
            return "ahead +\(count)"
        case .behind(let count):
            return "behind -\(count)"
        case .diverged(let ahead, let behind):
            return "ahead +\(ahead) / behind -\(behind)"
        case .noUpstream:
            return "no-upstream"
        case .unknown:
            return "unknown"
        }
    }
}

private enum SidebarRepoGrouping {
    struct ColorPreset {
        let name: String
        let hex: String
    }

    static let colorPresets: [ColorPreset] = [
        ColorPreset(name: "Amber", hex: "#F59E0B"),
        ColorPreset(name: "Blue", hex: "#3B82F6"),
        ColorPreset(name: "Green", hex: "#22C55E"),
        ColorPreset(name: "Teal", hex: "#14B8A6"),
        ColorPreset(name: "Pink", hex: "#EC4899"),
        ColorPreset(name: "Red", hex: "#EF4444"),
        ColorPreset(name: "Indigo", hex: "#6366F1"),
        ColorPreset(name: "Orange", hex: "#F97316"),
    ]

    static func defaultColorHex(for key: String) -> String {
        let hash = key.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fff_ffff
        }
        return colorPresets[hash % colorPresets.count].hex
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
}
