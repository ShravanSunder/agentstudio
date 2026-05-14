import Foundation

enum PaneManagementIcon: Equatable {
    case octicon(String)
    case system(String)
}

struct PaneManagementIdentityRow: Equatable, Identifiable {
    let id: String
    let icon: PaneManagementIcon
    let text: String
    let toolTip: String?
}

@MainActor
struct PaneManagementContext: Equatable {
    let identityRows: [PaneManagementIdentityRow]
    let statusChips: WorkspaceStatusChipsModel?
    let targetPath: URL?
    let showsIdentityBlock: Bool

    static func project(
        paneId: UUID,
        store: WorkspaceStore
    ) -> Self {
        let workspacePane = store.paneAtom
        let workspaceRepositoryTopology = store.repositoryTopologyAtom
        let workspaceLookup = atom(\.workspaceLookup)
        let parts = atom(\.paneDisplay).displayParts(for: paneId)
        let repoCache = atom(\.repoCache)
        let pane = workspacePane.pane(paneId)
        let resolvedContext =
            pane?.worktreeId.flatMap { worktreeId in
                pane?.repoId.flatMap { repoId in
                    workspaceRepositoryTopology.repo(repoId).flatMap { repo in
                        workspaceRepositoryTopology.worktree(worktreeId).map { (repo: repo, worktree: $0) }
                    }
                }
            }
            ?? workspaceLookup.repoAndWorktree(containing: pane?.metadata.cwd).map {
                (repo: $0.repo, worktree: $0.worktree)
            }
        let resolvedTargetPath = pane?.metadata.cwd ?? resolvedContext?.worktree.path
        let hasWorkspaceAssociation =
            pane?.repoId != nil
            || pane?.worktreeId != nil
            || parts.repoName != nil
            || parts.worktreeFolderName != nil
        let showsIdentityBlock: Bool = {
            switch pane?.metadata.contentType {
            case .browser:
                return hasWorkspaceAssociation
            case .none:
                return false
            default:
                return true
            }
        }()

        let statusChips: WorkspaceStatusChipsModel?
        if let worktreeId = pane?.worktreeId {
            let branchStatus = RepoExplorerView.branchStatus(
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktreeId],
                pullRequestCount: repoCache.pullRequestCountByWorktreeId[worktreeId]
            )
            statusChips = WorkspaceStatusChipsModel(
                branchStatus: branchStatus,
                notificationCount: repoCache.notificationCountByWorktreeId[worktreeId, default: 0]
            )
        } else if let resolvedWorktreeId =
            workspaceLookup.repoAndWorktree(containing: pane?.metadata.cwd)?.worktree.id
        {
            let branchStatus = RepoExplorerView.branchStatus(
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[resolvedWorktreeId],
                pullRequestCount: repoCache.pullRequestCountByWorktreeId[resolvedWorktreeId]
            )
            statusChips = WorkspaceStatusChipsModel(
                branchStatus: branchStatus,
                notificationCount: repoCache.notificationCountByWorktreeId[resolvedWorktreeId, default: 0]
            )
        } else {
            statusChips = nil
        }

        let identityRows = projectIdentityRows(
            pane: pane,
            resolvedContext: resolvedContext,
            displayParts: parts,
            targetPath: resolvedTargetPath
        )

        return Self(
            identityRows: identityRows,
            statusChips: statusChips,
            targetPath: resolvedTargetPath,
            showsIdentityBlock: showsIdentityBlock
        )
    }

    private static func projectIdentityRows(
        pane: Pane?,
        resolvedContext: (repo: Repo, worktree: Worktree)?,
        displayParts: PaneDisplayParts,
        targetPath: URL?
    ) -> [PaneManagementIdentityRow] {
        var rows: [PaneManagementIdentityRow] = []

        if let repoName = resolvedContext?.repo.name ?? displayParts.repoName {
            rows.append(
                PaneManagementIdentityRow(
                    id: "repo",
                    icon: .octicon("octicon-repo"),
                    text: repoName,
                    toolTip: nil
                )
            )
        }

        if let branchName = displayParts.branchName {
            rows.append(
                PaneManagementIdentityRow(
                    id: "branch",
                    icon: .octicon("octicon-git-branch"),
                    text: branchName,
                    toolTip: nil
                )
            )
        }

        if let worktree = resolvedContext?.worktree {
            rows.append(
                PaneManagementIdentityRow(
                    id: "worktree",
                    icon: .octicon(worktree.isMainWorktree ? "octicon-star-fill" : "octicon-git-worktree"),
                    text: worktree.name,
                    toolTip: worktree.path.path
                )
            )
        }

        if let targetPath {
            let compactPath = compactPathLabel(
                for: targetPath,
                worktreeRoot: resolvedContext?.worktree.path
            )
            rows.append(
                PaneManagementIdentityRow(
                    id: "cwd",
                    icon: .system("folder"),
                    text: compactPath,
                    toolTip: targetPath.path
                )
            )
        }

        if rows.isEmpty, let fallback = displayParts.cwdFolderName ?? displayParts.primaryLabel.nilIfEmpty {
            rows.append(
                PaneManagementIdentityRow(
                    id: "fallback",
                    icon: .system("terminal"),
                    text: fallback,
                    toolTip: nil
                )
            )
        }

        return rows
    }

    private static func compactPathLabel(for targetPath: URL, worktreeRoot: URL?) -> String {
        let normalizedTarget = targetPath.standardizedFileURL.path

        if let worktreeRoot {
            let normalizedRoot = worktreeRoot.standardizedFileURL.path
            if normalizedTarget == normalizedRoot {
                let folderName = targetPath.lastPathComponent
                return folderName.isEmpty ? normalizedTarget : folderName
            }
            let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
            if normalizedTarget.hasPrefix(prefix) {
                return String(normalizedTarget.dropFirst(prefix.count))
            }
        }

        let components = normalizedTarget.split(separator: "/")
        if components.count >= 2 {
            return "…/" + components.suffix(2).joined(separator: "/")
        }

        return targetPath.lastPathComponent.isEmpty ? normalizedTarget : targetPath.lastPathComponent
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
