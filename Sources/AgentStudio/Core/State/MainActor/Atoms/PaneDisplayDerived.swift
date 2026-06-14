import Foundation
import os.log

private let paneDisplayLogger = Logger(subsystem: "com.agentstudio", category: "PaneDisplayDerived")

struct PaneDisplayParts: Equatable {
    let primaryLabel: String
    let note: String?
    let repoName: String?
    let branchName: String?
    let worktreeFolderName: String?
    let cwdFolderName: String?
}

struct CollapsedBarLabelPart: Equatable {
    enum IconKind: Equatable {
        case octicon(String)
        case system(String)
    }

    enum IconTextSpacing: Equatable {
        case tight
        case loose
    }

    enum TextWeight: Equatable {
        case semibold
        case regular
    }

    let icon: IconKind
    let text: String
    let weight: TextWeight
    var iconTextSpacing: IconTextSpacing = .tight
}

private struct WorkspaceContextParts {
    let repoName: String
    let worktreeName: String
    let worktreeIconName: String
    let branchName: String?
}

@MainActor
struct PaneDisplayDerived {
    func displayParts(for paneId: UUID) -> PaneDisplayParts {
        let workspacePane = atom(\.workspacePane)
        guard let pane = workspacePane.pane(paneId) else {
            paneDisplayLogger.warning("displayParts: pane \(paneId.uuidString, privacy: .public) not found")
            return PaneDisplayParts(
                primaryLabel: "Terminal",
                note: nil,
                repoName: nil,
                branchName: nil,
                worktreeFolderName: nil,
                cwdFolderName: nil
            )
        }

        return displayParts(for: pane)
    }

    func displayParts(for pane: Pane) -> PaneDisplayParts {
        let rawTitle = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLabel = rawTitle.isEmpty ? "Terminal" : rawTitle
        let cwdFolderName: String? = {
            guard let cwdFolder = pane.metadata.cwd?.lastPathComponent else { return nil }
            return cwdFolder.isEmpty ? nil : cwdFolder
        }()

        if let workspaceContext = resolvedWorkspaceContext(for: pane) {
            let primaryLabel = [
                workspaceContext.repoName,
                workspaceContext.branchName,
                workspaceContext.worktreeName,
            ]
            .compactMap { label in
                guard let label else { return nil }
                return label.isEmpty ? nil : label
            }
            .joined(separator: " | ")
            return PaneDisplayParts(
                primaryLabel: primaryLabel.isEmpty ? defaultLabel : primaryLabel,
                note: pane.metadata.note,
                repoName: workspaceContext.repoName,
                branchName: workspaceContext.branchName,
                worktreeFolderName: workspaceContext.worktreeName,
                cwdFolderName: cwdFolderName
            )
        }

        if let cwdFolderName {
            return PaneDisplayParts(
                primaryLabel: cwdFolderName,
                note: pane.metadata.note,
                repoName: nil,
                branchName: nil,
                worktreeFolderName: nil,
                cwdFolderName: cwdFolderName
            )
        }

        return PaneDisplayParts(
            primaryLabel: defaultLabel,
            note: pane.metadata.note,
            repoName: nil,
            branchName: nil,
            worktreeFolderName: nil,
            cwdFolderName: nil
        )
    }

    func displayLabel(for paneId: UUID) -> String {
        displayParts(for: paneId).primaryLabel
    }

    func tabDisplayLabel(for tab: Tab) -> String {
        let paneLabels = tab.activePaneIds.map { displayLabel(for: $0) }
        if paneLabels.count > 1 {
            return paneLabels.joined(separator: " | ")
        }
        return paneLabels.first ?? "Terminal"
    }

    func paneKeywords(for pane: Pane) -> [String] {
        let parts = displayParts(for: pane)
        return [
            parts.note, parts.primaryLabel, parts.repoName, parts.branchName, parts.worktreeFolderName,
            parts.cwdFolderName,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    }

    func resolvedBranchName(
        worktree _: Worktree,
        enrichment: WorktreeEnrichment?
    ) -> String {
        let cachedBranch = enrichment?.branch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cachedBranch.isEmpty {
            return cachedBranch
        }

        return "detached HEAD"
    }

    func accentColorHex(for paneId: UUID) -> String? {
        let workspacePane = atom(\.workspacePane)
        let workspaceRepositoryTopology = atom(\.workspaceRepositoryTopology)
        let repoCache = atom(\.repoCache)
        let sidebarCache = atom(\.sidebarCache)

        guard let pane = workspacePane.pane(paneId) else {
            paneDisplayLogger.warning("accentColorHex: pane \(paneId.uuidString, privacy: .public) not found")
            return nil
        }
        guard let repoId = pane.repoId ?? pane.metadata.repoId else { return nil }
        let sidebarRepos = workspaceRepositoryTopology.repos.map(RepoPresentationItem.init(repo:))
        guard let sidebarRepo = sidebarRepos.first(where: { $0.id == repoId }) else { return nil }

        let repoEnrichmentByRepoId = Dictionary(
            uniqueKeysWithValues: sidebarRepos.compactMap { repo in
                repoCache.repoEnrichment(for: repo.id).map { (repo.id, $0) }
            }
        )
        let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId,
        )
        let resolvedGroups = RepoPresentationGrouping.buildGroups(
            repos: sidebarRepos,
            metadataByRepoId: repoMetadataById
        )

        let checkoutColorOverrides = Dictionary(
            uniqueKeysWithValues: sidebarCache.checkoutColors.map { key, value in
                (key.rawValue, value)
            }
        )

        if let group = resolvedGroups.first(where: { group in
            group.repos.contains(where: { $0.id == repoId })
        }) {
            return RepoPresentationColoring.checkoutColorHex(
                for: sidebarRepo,
                in: group,
                checkoutColorOverrides: checkoutColorOverrides
            )
        }

        return sidebarCache.checkoutColors[SidebarCheckoutColorKey(repoId.uuidString)]
    }

    func collapsedBarLabelParts(for paneId: UUID) -> [CollapsedBarLabelPart] {
        let workspacePane = atom(\.workspacePane)

        guard let pane = workspacePane.pane(paneId) else {
            paneDisplayLogger.warning("collapsedBarLabelParts: pane \(paneId.uuidString, privacy: .public) not found")
            return [CollapsedBarLabelPart(icon: .system("terminal"), text: "Terminal", weight: .regular)]
        }

        let parts = displayParts(for: pane)
        let notePart = parts.note.map {
            CollapsedBarLabelPart(
                icon: .system("long.text.page.and.pencil"),
                text: $0,
                weight: .semibold,
                iconTextSpacing: .loose
            )
        }

        if let workspaceContext = resolvedWorkspaceContext(for: pane) {
            var labelParts = [
                CollapsedBarLabelPart(
                    icon: .octicon("octicon-repo"),
                    text: workspaceContext.repoName,
                    weight: .semibold
                ),
                CollapsedBarLabelPart(
                    icon: .octicon(workspaceContext.worktreeIconName),
                    text: workspaceContext.worktreeName,
                    weight: .regular
                ),
            ]
            if let branchName = workspaceContext.branchName, !branchName.isEmpty {
                labelParts.append(
                    CollapsedBarLabelPart(icon: .octicon("octicon-git-branch"), text: branchName, weight: .regular)
                )
            }
            return labelParts + [notePart].compactMap { $0 }
        }

        if let cwdFolder = parts.cwdFolderName {
            return [CollapsedBarLabelPart(icon: .system("folder"), text: cwdFolder, weight: .regular)]
                + [notePart].compactMap { $0 }
        }

        let label = parts.primaryLabel.isEmpty ? "Terminal" : parts.primaryLabel
        return [CollapsedBarLabelPart(icon: .system("terminal"), text: label, weight: .regular)]
            + [notePart].compactMap { $0 }
    }

    private func resolvedWorkspaceContext(for pane: Pane) -> WorkspaceContextParts? {
        let workspaceRepositoryTopology = atom(\.workspaceRepositoryTopology)
        let workspaceLookup = atom(\.workspaceLookup)
        let repoCache = atom(\.repoCache)

        let explicitRepoId = pane.repoId ?? pane.metadata.repoId
        let explicitWorktreeId = pane.worktreeId ?? pane.metadata.worktreeId

        if let explicitRepoId,
            let explicitWorktreeId,
            let repo = workspaceRepositoryTopology.repo(explicitRepoId),
            let worktree = workspaceRepositoryTopology.worktree(explicitWorktreeId)
        {
            return WorkspaceContextParts(
                repoName: pane.metadata.repoName ?? repo.name,
                worktreeName: pane.metadata.worktreeName ?? worktree.path.lastPathComponent,
                worktreeIconName: worktree.isMainWorktree ? "octicon-star-fill" : "octicon-git-worktree",
                branchName: resolvedBranchName(
                    worktree: worktree,
                    enrichment: repoCache.worktreeEnrichment(for: worktree.id)
                )
            )
        }

        if explicitRepoId != nil || explicitWorktreeId != nil {
            paneDisplayLogger.warning(
                "resolvedWorkspaceContext: explicit repo/worktree for pane \(pane.id.uuidString, privacy: .public) missing from topology; falling back"
            )
        }

        if let resolvedContext = workspaceLookup.repoAndWorktree(containing: pane.metadata.cwd) {
            return WorkspaceContextParts(
                repoName: pane.metadata.repoName ?? resolvedContext.repo.name,
                worktreeName: pane.metadata.worktreeName ?? resolvedContext.worktree.name,
                worktreeIconName: resolvedContext.worktree.isMainWorktree
                    ? "octicon-star-fill" : "octicon-git-worktree",
                branchName: resolvedBranchName(
                    worktree: resolvedContext.worktree,
                    enrichment: repoCache.worktreeEnrichment(for: resolvedContext.worktree.id)
                )
            )
        }

        if let repoName = pane.metadata.repoName, let worktreeName = pane.metadata.worktreeName {
            let branchName = explicitWorktreeId.flatMap { worktreeId in
                let branch = repoCache.worktreeEnrichment(for: worktreeId)?.branch ?? ""
                return branch.isEmpty ? nil : branch
            }
            return WorkspaceContextParts(
                repoName: repoName,
                worktreeName: worktreeName,
                worktreeIconName: "octicon-git-worktree",
                branchName: branchName
            )
        }

        return nil
    }
}
