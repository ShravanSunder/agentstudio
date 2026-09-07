import AgentStudioInfrastructure
import Foundation

struct WorkspaceTerminalCreationProposal: Sendable {
    let bundle: WorkspaceSQLiteSaveBundle
    let pane: Pane
    let tab: Tab
    let associationOutcome: PaneAssociationOutcome
}

enum WorkspaceTerminalCreationComposition {
    @concurrent nonisolated static func preparePaneOffMain(
        metadata: PaneMetadata, topology: RepositoryTopologyReadSnapshot
    ) async -> (pane: Pane, outcome: PaneAssociationOutcome) {
        var facets = metadata.facets
        let outcome: PaneAssociationOutcome
        if let repoID = facets.repoId, let worktreeID = facets.worktreeId,
            topology.repo(repoID) != nil, topology.worktree(worktreeID)?.repoId == repoID
        {
            outcome = .stampedKnown
        } else {
            let resolved = topology.repoAndWorktree(containing: facets.cwd ?? metadata.launchDirectory)
            facets.repoId = resolved?.repo.id
            facets.worktreeId = resolved?.worktree.id
            outcome = resolved == nil ? .freeNil : .resolvedChanged
        }
        let cwd =
            [facets.cwd, metadata.launchDirectory, FileManager.default.homeDirectoryForCurrentUser]
            .compactMap { candidate -> URL? in
                guard case .accepted(let location) = PaneFilesystemLocationPolicy.runtimeCWDUpdate(candidate) else {
                    return nil
                }
                return location
            }.first ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        facets.cwd = cwd
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
            metadata: PaneMetadata(launchDirectory: cwd, title: metadata.title, facets: facets))
        return (pane, outcome)
    }

    @concurrent nonisolated static func prepareTabOffMain(
        in source: WorkspaceSQLiteSaveBundle,
        pane: Pane,
        name: String,
        associationOutcome: PaneAssociationOutcome
    ) async -> WorkspaceTerminalCreationProposal {
        let tab = Tab(paneId: pane.id, name: name)
        var updated = source.workspace
        updated.panes.append(pane)
        updated.tabs.append(tab)
        updated.activeTabId = tab.id
        return .init(
            bundle: .init(workspace: updated, captureRevision: source.captureRevision),
            pane: pane, tab: tab, associationOutcome: associationOutcome)
    }
}
