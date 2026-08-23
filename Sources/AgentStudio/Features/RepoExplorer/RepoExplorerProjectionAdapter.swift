import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation

enum RepoExplorerProjectionSlot: Hashable, Sendable {
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
    case unresolved(RepoExplorerRowID)
}

private struct RepoExplorerRenderedGroupHeaderContent: Equatable {
    let id: String
    let title: String
    let organizationName: String?
    let colorHex: String?
    let isExpanded: Bool
    let semanticRepoPath: URL?
    let paneDestinations: [RepoExplorerPaneDestination]
}

private struct RepoExplorerRenderedWorktreeContent: Equatable {
    let groupId: String
    let rowId: RepoExplorerRowID
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
    RepoExplorerProjectionIntent,
    Int,
    RepoExplorerProjectionWork,
    RepoExplorerProjectionCandidate,
    RepoExplorerProjectionResult
>

typealias RepoExplorerMaterializedProjectionFamily = EagerDerivedAtomFamily<
    RepoExplorerProjectionSlot,
    RepoExplorerProjectionIntent,
    Int,
    RepoExplorerProjectionWork,
    RepoExplorerProjectionCandidate,
    RepoExplorerProjectionResult
>

@MainActor
@Observable
final class RepoExplorerProjectionAdapter {
    var publishedResult: RepoExplorerProjectionResult?
    var publishedRevision = 0
    @ObservationIgnored var projectionFamily: RepoExplorerMaterializedProjectionFamily!
    @ObservationIgnored let onProjectionSuppressed:
        @MainActor @Sendable (
            RepoExplorerProjectionResult
        ) -> Void
    @ObservationIgnored var hasStopped = false
    @ObservationIgnored var observationGeneration = 0
    @ObservationIgnored var semanticBaselineSequence: UInt64 = 0
    @ObservationIgnored var semanticBaselineResult: RepoExplorerProjectionResult?
    @ObservationIgnored var acknowledgedMaterializationBaseline: RepoExplorerMaterializationBaseline?
    @ObservationIgnored var materializationDemandEpoch: UInt64 = 0
    @ObservationIgnored var isMaterializationDemandSuspended = false
    @ObservationIgnored weak var materializationHost: RepoExplorerMaterializationHost?
    @ObservationIgnored var pendingMaterializationSettlement: RepoExplorerPendingMaterializationSettlement?
    @ObservationIgnored var nextMaterializationCandidateID: UInt64 = 0
    @ObservationIgnored var lastRecoveryBaselineIdentity: RepoExplorerAcknowledgedBaselineIdentity?
    @ObservationIgnored let inputCapture: RepoExplorerProjectionInputCapture?
    @ObservationIgnored let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored let recencyNow: @MainActor @Sendable () -> Date
    @ObservationIgnored let recencyDelay: AsyncDelay
    @ObservationIgnored let initialProjectionTrigger: AppPolicies.SidebarProjection.Trigger
    @ObservationIgnored var isDemanded = false
    @ObservationIgnored var query = ""
    @ObservationIgnored var projectionGeneration = 0
    @ObservationIgnored var cachedProjectionRequest: RepoExplorerProjectionRequest?
    @ObservationIgnored var recencyReferenceDate = Date()
    @ObservationIgnored var recencyDeadlineTask: Task<Void, Never>?
    @ObservationIgnored var observationTokens: Set<RepoExplorerObservationToken> = []
    @ObservationIgnored var pendingInvalidation = RepoExplorerPendingInvalidation()
    @ObservationIgnored var invalidationTask: Task<Void, Never>?
    @ObservationIgnored var observationRegistration = RepoExplorerObservationRegistration.hidden

    func performanceProofReadback(
        focusDisposition: RepoExplorerPerformanceProofReadback.FocusDisposition
    ) -> RepoExplorerPerformanceProofReadback? {
        guard let semanticBaselineResult, let acknowledgedMaterializationBaseline,
            let materializationHost,
            materializationHost.acceptedBaseline == acknowledgedMaterializationBaseline
        else { return nil }
        return RepoExplorerPerformanceProofReadback(
            semanticGeneration: semanticBaselineResult.generation,
            acknowledgedRevision: acknowledgedMaterializationBaseline.revision,
            visibleGeneration: acknowledgedMaterializationBaseline.visibleGeneration,
            representedRowCount: acknowledgedMaterializationBaseline.rowCount,
            groupingMode: semanticBaselineResult.snapshot.groupingMode,
            queryIsEmpty: semanticBaselineResult.snapshot.query.isEmpty,
            isDemanded: isDemanded,
            presentationIsReady: materializationHost.isPresentationReady,
            focusDisposition: focusDisposition,
            accessibilityDisposition: materializationHost.isPresentationReady
                ? .ready
                : .unavailable
        )
    }

    init(
        inputCapture: RepoExplorerProjectionInputCapture? = nil,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        recencyNow: @escaping @MainActor @Sendable () -> Date = Date.init,
        recencyDelay: AsyncDelay = .taskSleep,
        initialProjectionTrigger: AppPolicies.SidebarProjection.Trigger = .startupDiagnostic,
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
        self.inputCapture = inputCapture
        self.performanceTraceRecorder = performanceTraceRecorder
        self.recencyNow = recencyNow
        self.recencyDelay = recencyDelay
        self.initialProjectionTrigger = initialProjectionTrigger
        self.onProjectionSuppressed = onProjectionSuppressed
        projectionFamily = RepoExplorerMaterializedProjectionFamily(
            telemetryLabel: "repo_explorer_projection",
            performanceOutcome: { stage, outcome in
                RepoExplorerPerformanceTelemetry.shared.record(stage: stage, outcome: outcome)
            },
            intentIdentity: \.generation,
            combinePendingIntents: RepoExplorerProjectionIntent.combinePending,
            prepare: { [weak self] intent, _ in
                self?.prepareProjectionWork(intent) ?? .rejected
            },
            project: { work throws(CancellationError) in
                RepoExplorerProjectionCandidate(work: work, result: try project(work))
            },
            classify: { [weak self] candidate, _ in
                self?.classifyProjectionCandidate(candidate) ?? .rejected
            },
            onAwaitingOwner: { [weak self] _, token, candidate, proposedValue in
                self?.applyAwaitingProjectionCandidate(
                    token: token,
                    candidate: candidate,
                    proposedValue: proposedValue
                )
            },
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
        establishDirectAdmissionIntentIfNeeded(request)
        projectionFamily.admit(.full(request), for: .sidebar)
    }

    func admitDelta(
        _ changes: Set<RepoExplorerScopedProjectionChange>,
        request: RepoExplorerProjectionRequest
    ) {
        guard !hasStopped, !changes.isEmpty else { return }
        establishDirectAdmissionIntentIfNeeded(request)
        projectionFamily.admit(
            .delta(
                RepoExplorerProjectionDeltaIntent(
                    targetRequest: request,
                    changes: changes,
                    structuralTarget: RepoExplorerProjectionStructuralTarget(request: request)
                )
            ),
            for: .sidebar
        )
    }

    private func establishDirectAdmissionIntentIfNeeded(
        _ request: RepoExplorerProjectionRequest
    ) {
        guard inputCapture == nil else { return }
        projectionGeneration = request.generation
        cachedProjectionRequest = request
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        suspendDemand()
        projectionFamily.stop()
    }

    func stopAndDrain() async {
        stop()
        await projectionFamily.stopAndDrain()
    }

    func traceAttributes(
        for request: RepoExplorerProjectionRequest,
        phase: String,
        extra: [String: AgentStudioTraceValue] = [:]
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.sidebar.surface": .string("repo"),
            "agentstudio.performance.sidebar.phase": .string(phase),
            "agentstudio.performance.sidebar.trigger": .string(request.trigger.rawValue),
            "agentstudio.performance.sidebar.query_state": .string(
                request.snapshot.query.isEmpty ? "empty" : "non_empty"),
            "agentstudio.performance.sidebar.group_mode": .string(request.snapshot.groupingMode.rawValue),
            "agentstudio.performance.sidebar.sort_order": .string(request.snapshot.sortOrder.rawValue),
            "agentstudio.performance.sidebar.repo.count": .int(request.snapshot.repos.count),
            "agentstudio.performance.sidebar.query_character.count": .int(request.snapshot.query.count),
            "agentstudio.performance.sidebar.collapsed_group.count": .int(request.collapsedGroupIds.count),
            "agentstudio.performance.sidebar.is_filtering": .bool(request.isFiltering),
        ]
        attributes.merge(extra) { _, newValue in newValue }
        return attributes
    }

    nonisolated static func hasEqualRenderedContent(
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
                        isExpanded: result.rowIndex.isGroupExpanded(group.id),
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
