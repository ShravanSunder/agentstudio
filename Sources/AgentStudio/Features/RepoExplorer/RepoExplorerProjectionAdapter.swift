import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation

private enum RepoExplorerProjectionSlot: Hashable, Sendable {
    case sidebar
}

private enum RepoExplorerRenderedRowContent: Equatable {
    case sectionHeader(RepoExplorerSidebarSectionKind)
    case loadingSectionHeader(RepoExplorerSidebarSectionKind, RepoExplorerLoadingSectionState)
    case loadingRepo(RepoExplorerSidebarSectionKind, UUID, String, Bool)
    case groupHeader(RepoExplorerRenderedGroupHeaderContent)
    case worktree(RepoExplorerRenderedWorktreeContent)
    case associatedPane(RepoExplorerProjectedPaneRow)
    case unassociatedPane(RepoExplorerUnassociatedPaneDestination, RepoExplorerPaneRowFacts?)
    case topologyFault(Int)
    case unresolved(String)
}

private struct RepoExplorerRenderedGroupHeaderContent: Equatable {
    let id: String
    let title: String
    let organizationName: String?
    let colorHex: String?
    let semanticRepoPath: URL?
    let paneDestinations: [RepoExplorerPaneDestination]
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
    let paneDestinations: [RepoExplorerPaneDestination]
}

typealias RepoExplorerMaterializedProjection = EagerDerivedAtom<
    RepoExplorerProjectionWork,
    Int,
    RepoExplorerProjectionResult
>

private typealias RepoExplorerMaterializedProjectionFamily = EagerDerivedAtomFamily<
    RepoExplorerProjectionSlot,
    RepoExplorerProjectionWork,
    Int,
    RepoExplorerProjectionResult
>

@MainActor
@Observable
final class RepoExplorerProjectionAdapter {
    private(set) var publishedResult: RepoExplorerProjectionResult?
    private(set) var publishedRevision = 0
    @ObservationIgnored private var projectionFamily: RepoExplorerMaterializedProjectionFamily!
    @ObservationIgnored private let onProjectionSuppressed:
        @MainActor @Sendable (
            RepoExplorerProjectionResult
        ) -> Void
    @ObservationIgnored private var hasStopped = false
    @ObservationIgnored private var observationGeneration = 0
    @ObservationIgnored private var projectionBaselineResult: RepoExplorerProjectionResult?

    init(
        onProjectionSuppressed:
            @escaping @MainActor @Sendable (
                RepoExplorerProjectionResult
            ) -> Void = { _ in },
        project:
            @escaping @Sendable (RepoExplorerProjectionWork) throws(CancellationError)
            -> RepoExplorerProjectionResult = { work throws(CancellationError) in
                do {
                    return try RepoExplorerProjectionWorker.project(work)
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
            performanceOutcome: { stage, outcome in
                RepoExplorerPerformanceTelemetry.shared.record(stage: stage, outcome: outcome)
            },
            requestIdentity: \.generation,
            combinePendingRequests: RepoExplorerProjectionWork.combinePending,
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
        projectionFamily.admit(.full(request), for: .sidebar)
    }

    func admitDelta(
        _ changes: Set<RepoExplorerScopedProjectionChange>,
        request: RepoExplorerProjectionRequest
    ) {
        guard !hasStopped, !changes.isEmpty else { return }
        guard let projectionBaselineResult else {
            admit(request)
            return
        }
        projectionFamily.admit(
            .delta(
                RepoExplorerProjectionDelta(
                    baselineRevision: publishedRevision,
                    baselineResult: projectionBaselineResult,
                    targetRequest: request,
                    changes: changes
                )
            ),
            for: .sidebar
        )
    }

    func startObservation(
        observeInputs: @escaping @MainActor () -> Void,
        onInvalidated: @escaping @MainActor (_ force: Bool) -> Void
    ) {
        guard !hasStopped else { return }
        observationGeneration += 1
        registerObservation(
            generation: observationGeneration,
            force: true,
            observeInputs: observeInputs,
            onInvalidated: onInvalidated
        )
    }

    func suspendObservation() {
        observationGeneration += 1
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        suspendObservation()
        projectionFamily.stop()
    }

    private func registerObservation(
        generation: Int,
        force: Bool,
        observeInputs: @escaping @MainActor () -> Void,
        onInvalidated: @escaping @MainActor (_ force: Bool) -> Void
    ) {
        guard !hasStopped, observationGeneration == generation else { return }
        withObservationTracking {
            observeInputs()
        } onChange: { [weak self] in
            Task { @MainActor in
                await Task.yield()
                guard let self, !self.hasStopped, self.observationGeneration == generation else {
                    return
                }
                self.registerObservation(
                    generation: generation,
                    force: false,
                    observeInputs: observeInputs,
                    onInvalidated: onInvalidated
                )
            }
        }
        onInvalidated(force)
    }

    private func handleProjectionCompletion(
        _ completion: RepoExplorerMaterializedProjection.ProjectionCompletion
    ) {
        guard let result = projectionFamily.latestAcceptedValue(for: .sidebar) else { return }
        switch completion {
        case .published:
            guard result.baselineRevision == nil || result.baselineRevision == publishedRevision else {
                return
            }
            projectionBaselineResult = result
            publishedRevision += 1
            publishedResult = result
        case .equal:
            guard result.baselineRevision == nil || result.baselineRevision == publishedRevision else {
                return
            }
            projectionBaselineResult = result
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
            && renderedRows(in: lhs) == renderedRows(in: rhs)
    }

    private nonisolated static func renderedRows(
        in result: RepoExplorerProjectionResult
    ) -> [RepoExplorerRenderedRowContent] {
        result.rowIndex.entries.map { entry in
            switch entry {
            case .sectionHeader(let kind):
                return .sectionHeader(kind)
            case .loadingSectionHeader(let kind):
                let state =
                    result.projection.sections
                    .first(where: { $0.kind == kind })?
                    .loadingState(
                        enrichmentByRepoId: result.snapshot.repoEnrichmentSnapshotByRepoId
                    ) ?? .scanning
                return .loadingSectionHeader(kind, state)
            case .loadingRepoRow(let section, let repo):
                let isUnavailable: Bool
                if case .statusUnavailable = result.snapshot.repoEnrichmentSnapshotByRepoId[repo.id] {
                    isUnavailable = true
                } else {
                    isUnavailable = false
                }
                return .loadingRepo(section, repo.id, repo.name, isUnavailable)
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
                else { return .unresolved(entry.id) }
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
                        paneDestinations: result.projection.paneDestinationsByWorktreeId[worktreeId] ?? []
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
                else { return .unresolved(entry.id) }
                return .associatedPane(context.row)
            case .unassociatedPaneRow(let destination):
                return .unassociatedPane(
                    destination,
                    result.paneRowFactsByPaneId[destination.paneId]
                )
            case .topologyFault(let fault):
                return .topologyFault(fault.duplicateIdentityCount)
            }
        }
    }

    private nonisolated static func renderedGroupPaneDestinations(
        _ group: RepoPresentationGroup,
        result: RepoExplorerProjectionResult
    ) -> [RepoExplorerPaneDestination] {
        guard result.snapshot.groupingMode != .tab, group.repos.count == 1,
            let repositoryID = group.repos.first?.id
        else { return [] }
        return result.projection.paneDestinationsByRepoId[repositoryID] ?? []
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
