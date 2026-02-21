import Foundation

/// Computes dynamic view projections from workspace state.
/// Pure function — no side effects, no mutation of owned state.
/// Called on demand when the user enters a dynamic view or when workspace state changes
/// while in a dynamic view.
enum DynamicViewProjector {

    /// Project all active panes through the given view type.
    /// Only includes panes with `.active` residency that are in a tab layout.
    static func project(
        viewType: DynamicViewType,
        panes: [UUID: Pane],
        tabs: [Tab],
        repos: [Repo]
    ) -> DynamicViewProjection {
        // Collect only active panes that are in a tab layout
        let layoutPaneIds = Set(tabs.flatMap(\.panes))
        let activePanes = panes.values.filter { layoutPaneIds.contains($0.id) && $0.residency == .active }

        let grouped: [(key: String, name: String, paneIds: [UUID])]

        switch viewType {
        case .byRepo:
            grouped = groupByRepo(panes: activePanes, repos: repos)
        case .byWorktree:
            grouped = groupByWorktree(panes: activePanes, repos: repos)
        case .byCWD:
            grouped = groupByCWD(panes: activePanes)
        case .byAgentType:
            grouped = groupByAgentType(panes: activePanes)
        case .byParentFolder:
            grouped = groupByParentFolder(panes: activePanes, repos: repos)
        }

        // Build groups with auto-tiled layouts, sorted alphabetically
        let groups =
            grouped
            .filter { !$0.paneIds.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { entry in
                DynamicViewGroup(
                    id: entry.key,
                    name: entry.name,
                    paneIds: entry.paneIds,
                    layout: Layout.autoTiled(entry.paneIds)
                )
            }

        return DynamicViewProjection(viewType: viewType, groups: groups)
    }

    // MARK: - Grouping Strategies

    private static func groupByRepo(
        panes: [Pane],
        repos: [Repo]
    ) -> [(key: String, name: String, paneIds: [UUID])] {
        let repoLookup = Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0) })
        var groups: [UUID: (name: String, paneIds: [UUID])] = [:]
        var ungrouped: [UUID] = []

        for pane in panes {
            if let repoId = pane.repoId, let repo = repoLookup[repoId] {
                groups[repoId, default: (name: repo.name, paneIds: [])].paneIds.append(pane.id)
            } else {
                ungrouped.append(pane.id)
            }
        }

        var result = groups.map { (key: $0.key.uuidString, name: $0.value.name, paneIds: $0.value.paneIds) }
        if !ungrouped.isEmpty {
            result.append((key: "ungrouped", name: "Floating", paneIds: ungrouped))
        }
        return result
    }

    private static func groupByWorktree(
        panes: [Pane],
        repos: [Repo]
    ) -> [(key: String, name: String, paneIds: [UUID])] {
        // Build worktree lookup from repos
        let worktreeLookup: [UUID: Worktree] = repos.reduce(into: [:]) { dict, repo in
            for wt in repo.worktrees {
                dict[wt.id] = wt
            }
        }

        var groups: [UUID: (name: String, paneIds: [UUID])] = [:]
        var ungrouped: [UUID] = []

        for pane in panes {
            if let wtId = pane.worktreeId, let wt = worktreeLookup[wtId] {
                groups[wtId, default: (name: wt.name, paneIds: [])].paneIds.append(pane.id)
            } else {
                ungrouped.append(pane.id)
            }
        }

        var result = groups.map { (key: $0.key.uuidString, name: $0.value.name, paneIds: $0.value.paneIds) }
        if !ungrouped.isEmpty {
            result.append((key: "ungrouped", name: "Floating", paneIds: ungrouped))
        }
        return result
    }

    private static func groupByCWD(
        panes: [Pane]
    ) -> [(key: String, name: String, paneIds: [UUID])] {
        var groups: [String: (name: String, paneIds: [UUID])] = [:]
        var ungrouped: [UUID] = []

        for pane in panes {
            if let cwd = pane.metadata.cwd {
                let path = cwd.path
                let name = cwd.lastPathComponent.isEmpty ? path : cwd.lastPathComponent
                groups[path, default: (name: name, paneIds: [])].paneIds.append(pane.id)
            } else {
                ungrouped.append(pane.id)
            }
        }

        var result = groups.map { (key: $0.key, name: $0.value.name, paneIds: $0.value.paneIds) }
        if !ungrouped.isEmpty {
            result.append((key: "ungrouped", name: "No CWD", paneIds: ungrouped))
        }
        return result
    }

    private static func groupByAgentType(
        panes: [Pane]
    ) -> [(key: String, name: String, paneIds: [UUID])] {
        var groups: [String: (name: String, paneIds: [UUID])] = [:]
        var ungrouped: [UUID] = []

        for pane in panes {
            if let agent = pane.agent {
                groups[agent.rawValue, default: (name: agent.displayName, paneIds: [])].paneIds.append(pane.id)
            } else {
                ungrouped.append(pane.id)
            }
        }

        var result = groups.map { (key: $0.key, name: $0.value.name, paneIds: $0.value.paneIds) }
        if !ungrouped.isEmpty {
            result.append((key: "ungrouped", name: "No Agent", paneIds: ungrouped))
        }
        return result
    }

    private static func groupByParentFolder(
        panes: [Pane],
        repos: [Repo]
    ) -> [(key: String, name: String, paneIds: [UUID])] {
        // Build repo → parent folder lookup
        let repoParentFolder: [UUID: URL] = Dictionary(
            uniqueKeysWithValues: repos.map {
                ($0.id, $0.repoPath.deletingLastPathComponent())
            })

        var groups: [String: (name: String, paneIds: [UUID])] = [:]
        var ungrouped: [UUID] = []

        for pane in panes {
            if let repoId = pane.repoId, let parentFolder = repoParentFolder[repoId] {
                let path = parentFolder.path
                let name = parentFolder.lastPathComponent.isEmpty ? path : parentFolder.lastPathComponent
                groups[path, default: (name: name, paneIds: [])].paneIds.append(pane.id)
            } else {
                ungrouped.append(pane.id)
            }
        }

        var result = groups.map { (key: $0.key, name: $0.value.name, paneIds: $0.value.paneIds) }
        if !ungrouped.isEmpty {
            result.append((key: "ungrouped", name: "Floating", paneIds: ungrouped))
        }
        return result
    }
}
