import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation

private enum RepoExplorerProjectionSlot: Hashable, Sendable {
    case sidebar
}

private enum RepoExplorerRenderedRowContent: Equatable {
    case sectionHeader(RepoExplorerSidebarSectionKind)
    case loadingSectionHeader(
        kind: RepoExplorerSidebarSectionKind,
        state: RepoExplorerLoadingSectionState
    )
    case loadingRepo(
        section: RepoExplorerSidebarSectionKind,
        repoId: UUID,
        name: String,
        isStatusUnavailable: Bool
    )
    case groupHeader(RepoExplorerRenderedGroupHeaderContent)
    case worktree(RepoExplorerRenderedWorktreeContent)
    case pane(RepoExplorerRenderedPaneContent)
    case topologyFault(duplicateIdentityCount: Int)
    case unresolved(id: String)
}

private struct RepoExplorerRenderedGroupHeaderContent: Equatable {
    let id: String
    let title: String
    let organizationName: String?
    let colorHex: String?
    let semanticRepoPath: URL?
    let paneDestinations: [RepoExplorerRenderedPaneDestination]
}

private struct RepoExplorerRenderedWorktreeContent: Equatable {
    let groupId: String
    let rowId: String
    let repoId: UUID
    let worktreeId: UUID
    let worktreePath: URL
    let checkoutTitle: String
    let isMainCheckout: Bool
    let projectedFavoriteState: Bool
    let isMainWorktree: Bool
    let checkoutColorHex: String
    let placementText: String
    let branchStatus: GitBranchStatus
    let branchName: String
    let bridgeCommandResolution: BridgePaneCommandResolution
    let paneDestinations: [RepoExplorerRenderedPaneDestination]
}

private struct RepoExplorerRenderedPaneDestination: Equatable {
    let paneId: UUID
    let worktreeLabel: String
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool
}

private struct RepoExplorerRenderedPaneContent: Equatable {
    let groupId: String
    let rowId: String
    let repoId: UUID
    let paneId: UUID
    let worktreeLabel: String
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool
}

typealias RepoExplorerMaterializedProjection = EagerDerivedAtom<
    RepoExplorerProjectionRequest,
    Int,
    RepoExplorerProjectionResult
>

private typealias RepoExplorerMaterializedProjectionFamily = EagerDerivedAtomFamily<
    RepoExplorerProjectionSlot,
    RepoExplorerProjectionRequest,
    Int,
    RepoExplorerProjectionResult
>

@MainActor
@Observable
final class RepoExplorerProjectionAdapter {
    private(set) var publishedResult: RepoExplorerProjectionResult?
    @ObservationIgnored private var projectionFamily: RepoExplorerMaterializedProjectionFamily!
    @ObservationIgnored private let onProjectionSuppressed:
        @MainActor @Sendable (
            RepoExplorerProjectionResult
        ) -> Void
    @ObservationIgnored private var hasStopped = false

    init(
        onProjectionSuppressed:
            @escaping @MainActor @Sendable (
                RepoExplorerProjectionResult
            ) -> Void = { _ in },
        project:
            @escaping @Sendable (RepoExplorerProjectionRequest) throws(CancellationError)
            -> RepoExplorerProjectionResult = { request throws(CancellationError) in
                do {
                    return try RepoExplorerProjectionWorker.project(request)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    preconditionFailure("Repo Explorer projection threw a non-cancellation error: \(error)")
                }
            }
    ) {
        self.onProjectionSuppressed = onProjectionSuppressed
        projectionFamily = RepoExplorerMaterializedProjectionFamily(
            telemetryLabel: "repo_explorer_projection",
            recordsRepoExplorerKeyedWake: true,
            requestIdentity: \.generation,
            isValueEqual: Self.hasEqualRenderedContent,
            project: project,
            onProjectionCompletion: { [weak self] _, completion in
                self?.handleProjectionCompletion(completion)
            }
        )
        _ = projectionFamily.materialize(for: .sidebar)
    }

    var materializedProjection: RepoExplorerMaterializedProjection? {
        projectionFamily.atom(for: .sidebar)
    }

    func admit(_ request: RepoExplorerProjectionRequest) {
        guard !hasStopped else { return }
        projectionFamily.admit(request, for: .sidebar)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        projectionFamily.stop()
    }

    private func handleProjectionCompletion(
        _ completion: RepoExplorerMaterializedProjection.ProjectionCompletion
    ) {
        guard let result = projectionFamily.currentValue(for: .sidebar) else { return }
        switch completion {
        case .published:
            publishedResult = result
        case .equal:
            onProjectionSuppressed(result)
        case .superseded, .cancelled:
            break
        }
    }

    private nonisolated static func hasEqualRenderedContent(
        _ lhs: RepoExplorerProjectionResult,
        _ rhs: RepoExplorerProjectionResult
    ) -> Bool {
        lhs.snapshot.groupingMode == rhs.snapshot.groupingMode
            && lhs.projection.emptyState == rhs.projection.emptyState
            && renderedRows(for: lhs) == renderedRows(for: rhs)
    }

    private nonisolated static func renderedRows(
        for result: RepoExplorerProjectionResult
    ) -> [RepoExplorerRenderedRowContent] {
        result.rowIndex.entries.map { entry in
            switch entry {
            case .sectionHeader(let kind):
                return .sectionHeader(kind)
            case .loadingSectionHeader(let kind):
                return .loadingSectionHeader(
                    kind: kind,
                    state: result.projection.sections
                        .first(where: { $0.kind == kind })?
                        .loadingState(
                            enrichmentByRepoId: result.snapshot.repoEnrichmentSnapshotByRepoId
                        ) ?? .scanning
                )
            case .loadingRepoRow(let section, let repo):
                let isStatusUnavailable: Bool
                if case .statusUnavailable = result.snapshot.repoEnrichmentSnapshotByRepoId[repo.id] {
                    isStatusUnavailable = true
                } else {
                    isStatusUnavailable = false
                }
                return .loadingRepo(
                    section: section,
                    repoId: repo.id,
                    name: repo.name,
                    isStatusUnavailable: isStatusUnavailable
                )
            case .resolvedGroupHeader(let group):
                return .groupHeader(
                    RepoExplorerRenderedGroupHeaderContent(
                        id: group.id,
                        title: group.repoTitle,
                        organizationName: group.organizationName,
                        colorHex: RepoPresentationColoring.sourceGroupColorHex(for: group),
                        semanticRepoPath: semanticRepoPath(
                            for: group,
                            groupingMode: result.snapshot.groupingMode
                        ),
                        paneDestinations: renderedGroupPaneDestinations(group, result: result)
                    )
                )
            case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId, let rowId):
                guard
                    let context = result.rowIndex.resolve(
                        groupId: groupId,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        rowId: rowId
                    )
                else { return .unresolved(id: entry.id) }
                return .worktree(
                    RepoExplorerRenderedWorktreeContent(
                        groupId: groupId,
                        rowId: rowId,
                        repoId: context.repo.id,
                        worktreeId: context.worktree.id,
                        worktreePath: context.worktree.path,
                        checkoutTitle: checkoutTitle(for: context.worktree, in: context.repo),
                        isMainCheckout: isMainCheckout(context.worktree, in: context.repo),
                        projectedFavoriteState: context.repo.isFavorite,
                        isMainWorktree: context.worktree.isMainWorktree,
                        checkoutColorHex: context.checkoutColorHex,
                        placementText: context.placementContext?.displayText ?? "",
                        branchStatus: result.branchStatusByWorktreeId[worktreeId] ?? .unknown,
                        branchName: result.branchNameByWorktreeId[worktreeId] ?? "detached HEAD",
                        bridgeCommandResolution: result.bridgeCommandResolutionByWorktreeId[worktreeId] ?? .create,
                        paneDestinations: (result.projection.paneDestinationsByWorktreeId[worktreeId] ?? [])
                            .map(renderedPaneDestination)
                    )
                )
            case .resolvedPaneRow(let groupId, let identity, let rowId):
                guard
                    let context = result.rowIndex.resolvePane(
                        groupId: groupId,
                        repoId: identity.repoId,
                        paneId: identity.paneId,
                        rowId: rowId
                    )
                else { return .unresolved(id: entry.id) }
                return .pane(
                    RepoExplorerRenderedPaneContent(
                        groupId: groupId,
                        rowId: rowId,
                        repoId: identity.repoId,
                        paneId: identity.paneId,
                        worktreeLabel: context.destination.worktreeLabel,
                        tabIndex: context.destination.tabIndex,
                        paneIndexInTab: context.destination.paneIndexInTab,
                        isActiveInTab: context.destination.isActiveInTab
                    )
                )
            case .topologyFault(let fault):
                return .topologyFault(duplicateIdentityCount: fault.duplicateIdentityCount)
            }
        }
    }

    private nonisolated static func renderedPaneDestination(
        _ destination: RepoExplorerPaneDestination
    ) -> RepoExplorerRenderedPaneDestination {
        RepoExplorerRenderedPaneDestination(
            paneId: destination.paneId,
            worktreeLabel: destination.worktreeLabel,
            tabIndex: destination.tabIndex,
            paneIndexInTab: destination.paneIndexInTab,
            isActiveInTab: destination.isActiveInTab
        )
    }

    private nonisolated static func renderedGroupPaneDestinations(
        _ group: RepoPresentationGroup,
        result: RepoExplorerProjectionResult
    ) -> [RepoExplorerRenderedPaneDestination] {
        guard result.snapshot.groupingMode != .tab, group.repos.count == 1,
            let repoId = group.repos.first?.id
        else { return [] }
        return (result.projection.paneDestinationsByRepoId[repoId] ?? []).map(renderedPaneDestination)
    }

    private nonisolated static func semanticRepoPath(
        for group: RepoPresentationGroup,
        groupingMode: RepoExplorerGroupingMode
    ) -> URL? {
        guard groupingMode == .repo || groupingMode == .pane, group.repos.count == 1 else { return nil }
        return group.repos.first?.repoPath
    }

    private nonisolated static func checkoutTitle(
        for worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> String {
        let folderName = worktree.path.lastPathComponent
        return folderName.isEmpty ? repo.name : folderName
    }

    private nonisolated static func isMainCheckout(
        _ worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> Bool {
        worktree.isMainWorktree
            || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path
    }
}
