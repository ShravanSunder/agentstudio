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
    @ObservationIgnored private let inputCapture: RepoExplorerProjectionInputCapture?
    @ObservationIgnored private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private let recencyNow: @MainActor @Sendable () -> Date
    @ObservationIgnored private let recencyDelay: AsyncDelay
    @ObservationIgnored private let initialProjectionTrigger: AppPolicies.SidebarProjection.Trigger
    @ObservationIgnored private var isDemanded = false
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var projectionGeneration = 0
    @ObservationIgnored private var cachedProjectionRequest: RepoExplorerProjectionRequest?
    @ObservationIgnored private var recencyReferenceDate = Date()
    @ObservationIgnored private var recencyDeadlineTask: Task<Void, Never>?
    @ObservationIgnored private(set) var observationRegistration = RepoExplorerObservationRegistration.hidden

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
        establishDirectAdmissionIntentIfNeeded(request)
        projectionFamily.admit(.full(request), for: .sidebar)
    }

    func admitDelta(
        _ changes: Set<RepoExplorerScopedProjectionChange>,
        request: RepoExplorerProjectionRequest
    ) {
        guard !hasStopped, !changes.isEmpty else { return }
        establishDirectAdmissionIntentIfNeeded(request)
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

    private func establishDirectAdmissionIntentIfNeeded(
        _ request: RepoExplorerProjectionRequest
    ) {
        guard inputCapture == nil else { return }
        projectionGeneration = request.generation
        cachedProjectionRequest = request
    }

    func updateDemand(isVisible: Bool, query: String) {
        guard !hasStopped else { return }
        let visibilityChanged = isDemanded != isVisible
        let queryChanged = self.query != query
        isDemanded = isVisible
        self.query = query

        guard isVisible else {
            suspendDemand()
            return
        }

        if visibilityChanged {
            recencyReferenceDate = recencyNow()
            startInputObservation(force: true)
        } else if queryChanged {
            captureProjectionInputs(force: false)
        } else if observationRegistration == .hidden {
            startInputObservation(force: true)
        }
    }

    func suspendDemand() {
        isDemanded = false
        observationRegistration = .hidden
        observationGeneration += 1
        recencyDeadlineTask?.cancel()
        recencyDeadlineTask = nil
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        suspendDemand()
        projectionFamily.stop()
    }

    private func startInputObservation(force: Bool) {
        guard isDemanded, inputCapture != nil else { return }
        observationGeneration += 1
        registerInputObservation(generation: observationGeneration, force: force)
    }

    private func registerInputObservation(generation: Int, force: Bool) {
        guard !hasStopped, isDemanded, observationGeneration == generation,
            let inputCapture
        else { return }
        let registration = withObservationTracking {
            inputCapture.observeInputs(isVisible: isDemanded)
        } onChange: { [weak self] in
            Task { @MainActor in
                await Task.yield()
                guard let self, !self.hasStopped, self.isDemanded,
                    self.observationGeneration == generation
                else { return }
                self.registerInputObservation(generation: generation, force: false)
            }
        }
        observationRegistration = registration
        captureProjectionInputs(force: force)
    }

    private func captureProjectionInputs(force: Bool) {
        guard isDemanded, let inputCapture else { return }
        let clock = ContinuousClock()
        let requestBuildStart = clock.now
        let request = inputCapture.captureRequest(
            query: query,
            referenceDate: recencyReferenceDate,
            trigger: initialProjectionTrigger
        )
        let requestBuildDuration = requestBuildStart.duration(to: clock.now)
        if !force {
            RepoExplorerPerformanceTelemetry.shared.record(
                stage: "capture_rebuild",
                outcome: "admitted"
            )
        }
        refreshProjection(
            request: request,
            requestBuildDuration: requestBuildDuration,
            force: force
        )
    }

    private func refreshProjection(
        request: RepoExplorerProjectionRequest,
        requestBuildDuration: Duration,
        force: Bool
    ) {
        let requestKey = RepoExplorerView.projectionRequestKey(for: request)
        if !force, let cachedProjectionRequest,
            RepoExplorerView.projectionRequestKey(for: cachedProjectionRequest) == requestKey
        {
            return
        }

        if !force, let previousRequest = cachedProjectionRequest,
            let scopedChange = request.scopedChange(from: previousRequest)
        {
            projectionGeneration += 1
            let generatedRequest = request.generated(
                generation: projectionGeneration,
                trigger: .dataRefresh
            )
            RepoExplorerPerformanceTelemetry.shared.record(stage: "affected_row", outcome: "admitted")
            cachedProjectionRequest = generatedRequest
            admitDelta([scopedChange], request: generatedRequest)
            return
        }

        if !force {
            let captureScope =
                cachedProjectionRequest.map {
                    request.hasMembershipChange(from: $0) ? "membership_path" : "whole_surface"
                } ?? "whole_surface"
            RepoExplorerPerformanceTelemetry.shared.record(stage: captureScope, outcome: "admitted")
        }

        projectionGeneration += 1
        let trigger = RepoExplorerView.sidebarProjectionTrigger(
            previous: cachedProjectionRequest,
            next: request,
            initialProjectionTrigger: initialProjectionTrigger
        )
        let generatedRequest = request.generated(
            generation: projectionGeneration,
            trigger: trigger
        )
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: requestBuildDuration,
            attributes: traceAttributes(
                for: generatedRequest,
                phase: "request_build_mainactor",
                extra: [
                    "agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: requestBuildDuration))
                ]
            )
        )
        cachedProjectionRequest = generatedRequest
        admit(generatedRequest)
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
            guard result.generation == projectionGeneration,
                result.snapshot == cachedProjectionRequest?.snapshot,
                result.collapsedGroupIds == cachedProjectionRequest?.collapsedGroupIds,
                result.isFiltering == cachedProjectionRequest?.isFiltering
            else {
                RepoExplorerPerformanceTelemetry.shared.record(
                    stage: "mainactor_apply",
                    outcome: "superseded"
                )
                return
            }
            projectionBaselineResult = result
            publishedRevision += 1
            publishedResult = result
            scheduleRecencyDeadline(for: result)
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

    private func scheduleRecencyDeadline(for result: RepoExplorerProjectionResult) {
        recencyDeadlineTask?.cancel()
        recencyDeadlineTask = nil
        guard isDemanded, observationRegistration.requiresRecencyDeadline else { return }

        let demandedPaneIDs = Set(
            result.projection.paneRowsByGroupId.values.flatMap { $0.map(\.destination.paneId) }
                + result.projection.sections.flatMap { section in
                    section.unassociatedPaneDestinations.map(\.paneId)
                }
        )
        let now = recencyNow()
        let presentationChangeDates = result.paneRowFactsByPaneId
            .filter { demandedPaneIDs.contains($0.key) }
            .values
            .map { facts in
                RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                    referenceDate: facts.recencyReferenceDate,
                    now: now
                )
            }
        guard let nextDeadline = presentationChangeDates.min() else { return }

        let delayNanoseconds = Int64(max(0, nextDeadline.timeIntervalSince(now)) * 1_000_000_000)
        recencyDeadlineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await recencyDelay.wait(.nanoseconds(delayNanoseconds))
            } catch {
                return
            }
            guard !Task.isCancelled, isDemanded else { return }
            recencyReferenceDate = recencyNow()
            captureProjectionInputs(force: false)
        }
    }

    private func traceAttributes(
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
