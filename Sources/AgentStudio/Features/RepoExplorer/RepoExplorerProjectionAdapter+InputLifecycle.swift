import AgentStudioInfrastructure
import Foundation
import Observation

struct RepoExplorerPendingInvalidation {
    var requiresStructuralCapture = false
    var requiresPresentationCapture = false
    var repositoryIDs = Set<UUID>()
    var worktreeIDs = Set<UUID>()
    var paneIDs = Set<UUID>()
    var tabIDs = Set<UUID>()
    var includesAttention = false
    var requiresActivityHydrationCapture = false
    var repositoryActivityIDs = Set<UUID>()

    var isEmpty: Bool {
        !requiresStructuralCapture
            && !requiresPresentationCapture
            && repositoryIDs.isEmpty
            && worktreeIDs.isEmpty
            && paneIDs.isEmpty
            && tabIDs.isEmpty
            && !includesAttention
            && !requiresActivityHydrationCapture
            && repositoryActivityIDs.isEmpty
    }

    mutating func insert(_ invalidation: RepoExplorerInputInvalidation) {
        switch invalidation {
        case .structural:
            requiresStructuralCapture = true
        case .presentation:
            requiresPresentationCapture = true
        case .repository(let repositoryID):
            repositoryIDs.insert(repositoryID)
        case .worktree(let worktreeID):
            worktreeIDs.insert(worktreeID)
        case .pane(let paneID):
            paneIDs.insert(paneID)
        case .tab(let tabID):
            tabIDs.insert(tabID)
        case .attention:
            includesAttention = true
        case .activityHydration:
            requiresActivityHydrationCapture = true
        case .repositoryActivity(let repositoryID):
            repositoryActivityIDs.insert(repositoryID)
        }
    }
}

extension RepoExplorerProjectionAdapter {
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

        resumeRegisteredMaterializationHostIfNeeded()
        guard materializationHost != nil, acknowledgedMaterializationBaseline != nil else {
            return
        }

        if visibilityChanged || cachedProjectionRequest == nil {
            recencyReferenceDate = recencyNow()
            captureFullProjection(force: true)
        } else if queryChanged {
            capturePresentationProjection()
        } else if observationTokens.isEmpty {
            installObservationTokens()
        }
    }

    func materializationHostDidRegister() {
        guard !hasStopped, isDemanded else { return }
        recencyReferenceDate = recencyNow()
        captureFullProjection(force: true)
    }

    func suspendDemand() {
        isDemanded = false
        suspendMaterializationDemand()
        observationRegistration = .hidden
        observationTokens = []
        observationGeneration += 1
        pendingInvalidation = RepoExplorerPendingInvalidation()
        invalidationTask?.cancel()
        invalidationTask = nil
        recencyDeadlineTask?.cancel()
        recencyDeadlineTask = nil
    }

    private func installObservationTokens() {
        guard !hasStopped, isDemanded, let inputCapture, let cachedProjectionRequest else { return }
        observationGeneration += 1
        let generation = observationGeneration
        let tokens = inputCapture.observationTokens(for: cachedProjectionRequest)
        observationTokens = tokens
        observationRegistration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            groupingMode: cachedProjectionRequest.snapshot.groupingMode,
            repositoryIDs: Set(cachedProjectionRequest.snapshot.repos.map(\.id)),
            worktreeIDs: Set(cachedProjectionRequest.snapshot.repos.flatMap(\.worktrees).map(\.id)),
            paneIDs: Set(cachedProjectionRequest.paneRowFactsByPaneId.keys),
            tabIDs: Set(cachedProjectionRequest.tabGroupFactsByTabId.keys)
        )
        for token in tokens {
            registerObservation(token, generation: generation)
        }
    }

    private func registerObservation(
        _ token: RepoExplorerObservationToken,
        generation: Int
    ) {
        guard !hasStopped, isDemanded, observationGeneration == generation,
            observationTokens.contains(token), let inputCapture
        else { return }
        withObservationTracking {
            inputCapture.observe(token, request: cachedProjectionRequest)
        } onChange: { [weak self] in
            Task { @MainActor in
                await Task.yield()
                guard let self, !self.hasStopped, self.isDemanded,
                    self.observationGeneration == generation,
                    self.observationTokens.contains(token)
                else { return }
                if token == .demand, !inputCapture.isRepoSurfaceVisible {
                    self.suspendDemand()
                    return
                }
                self.registerObservation(token, generation: generation)
                let currentActivityHydrationDisposition =
                    inputCapture.coreAtoms.repositoryLocalActivity.hydrationDisposition
                if token == .activityHydration,
                    self.cachedProjectionRequest?.localActivityHydrationDisposition
                        == currentActivityHydrationDisposition
                {
                    return
                }
                if case .repositoryActivity = token,
                    self.cachedProjectionRequest?.localActivityHydrationDisposition
                        != currentActivityHydrationDisposition
                {
                    return
                }
                self.enqueueInvalidation(inputCapture.invalidation(for: token))
            }
        }
    }

    private func enqueueInvalidation(_ invalidation: RepoExplorerInputInvalidation) {
        guard isDemanded else { return }
        pendingInvalidation.insert(invalidation)
        guard invalidationTask == nil else { return }
        invalidationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.invalidationTask = nil
            self.processPendingInvalidation()
        }
    }

    private func processPendingInvalidation() {
        guard isDemanded, !pendingInvalidation.isEmpty, let inputCapture else { return }
        let pending = pendingInvalidation
        pendingInvalidation = RepoExplorerPendingInvalidation()
        if pending.requiresStructuralCapture {
            captureFullProjection(force: false)
            return
        }
        if pending.requiresPresentationCapture {
            capturePresentationProjection()
            return
        }
        if pending.requiresActivityHydrationCapture {
            recencyReferenceDate = recencyNow()
            captureFullProjection(force: false)
            return
        }
        if !pending.repositoryActivityIDs.isEmpty {
            recencyReferenceDate = recencyNow()
        }
        guard var request = cachedProjectionRequest else {
            captureFullProjection(force: false)
            return
        }

        let invalidations =
            pending.repositoryIDs.map(RepoExplorerInputInvalidation.repository)
            + pending.repositoryActivityIDs.map(RepoExplorerInputInvalidation.repositoryActivity)
            + pending.worktreeIDs.map(RepoExplorerInputInvalidation.worktree)
            + pending.paneIDs.map(RepoExplorerInputInvalidation.pane)
            + pending.tabIDs.map(RepoExplorerInputInvalidation.tab)
            + (pending.includesAttention ? [.attention] : [])
        var changes = Set<RepoExplorerScopedProjectionChange>()
        var requiresFullProjection = false
        var requiresObservationRetarget = false
        for invalidation in invalidations {
            guard
                let capture = inputCapture.captureScoped(
                    invalidation,
                    previous: request,
                    referenceDate: recencyReferenceDate
                )
            else {
                captureFullProjection(force: false)
                return
            }
            if capture.requiresObservationRetarget {
                recencyReferenceDate = recencyNow()
                request = capture.request.replacing(
                    activityReferenceDate: recencyReferenceDate
                )
            } else {
                request = capture.request
            }
            changes.formUnion(capture.changes)
            requiresFullProjection = requiresFullProjection || capture.requiresFullProjection
            requiresObservationRetarget =
                requiresObservationRetarget || capture.requiresObservationRetarget
        }
        refreshProjection(
            request: request,
            requestBuildDuration: .zero,
            force: false,
            scopedChanges: changes,
            requiresFullProjection: requiresFullProjection
        )
        if requiresObservationRetarget {
            installObservationTokens()
        }
    }

    private func captureFullProjection(force: Bool) {
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
            RepoExplorerPerformanceTelemetry.shared.record(stage: "membership_path", outcome: "admitted")
        }
        refreshProjection(
            request: request,
            requestBuildDuration: requestBuildDuration,
            force: force,
            scopedChanges: [],
            requiresFullProjection: true
        )
        installObservationTokens()
    }

    private func capturePresentationProjection() {
        guard isDemanded, let inputCapture, let previous = cachedProjectionRequest else {
            captureFullProjection(force: false)
            return
        }
        let clock = ContinuousClock()
        let requestBuildStart = clock.now
        let request = inputCapture.capturePresentationRequest(
            previous: previous,
            query: query,
            referenceDate: recencyReferenceDate
        )
        let requestBuildDuration = requestBuildStart.duration(to: clock.now)
        let groupingChanged = request.snapshot.groupingMode != previous.snapshot.groupingMode
        refreshProjection(
            request: request,
            requestBuildDuration: requestBuildDuration,
            force: false,
            scopedChanges: [],
            requiresFullProjection: true
        )
        if groupingChanged {
            installObservationTokens()
        }
    }

    private func refreshProjection(
        request: RepoExplorerProjectionRequest,
        requestBuildDuration: Duration,
        force: Bool,
        scopedChanges: Set<RepoExplorerScopedProjectionChange>,
        requiresFullProjection: Bool
    ) {
        let requestKey = RepoExplorerView.projectionRequestKey(for: request)
        if !force, let cachedProjectionRequest,
            RepoExplorerView.projectionRequestKey(for: cachedProjectionRequest) == requestKey
        {
            return
        }

        projectionGeneration += 1
        let trigger = RepoExplorerView.sidebarProjectionTrigger(
            previous: cachedProjectionRequest,
            next: request,
            initialProjectionTrigger: initialProjectionTrigger
        )
        let generatedRequest = request.generated(generation: projectionGeneration, trigger: trigger)
        if !scopedChanges.isEmpty, !requiresFullProjection {
            RepoExplorerPerformanceTelemetry.shared.record(stage: "affected_row", outcome: "admitted")
            cachedProjectionRequest = generatedRequest
            admitDelta(scopedChanges, request: generatedRequest)
            return
        }

        RepoExplorerPerformanceTelemetry.shared.record(stage: "whole_surface", outcome: "admitted")
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

    func scheduleRecencyDeadline(for result: RepoExplorerProjectionResult) {
        recencyDeadlineTask?.cancel()
        recencyDeadlineTask = nil
        guard isDemanded else { return }

        let now = recencyNow()
        let nextDatesByPaneID = result.paneRowFactsByPaneId.mapValues { facts in
            RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                referenceDate: facts.recencyReferenceDate,
                now: now
            )
        }
        let nextPaneDeadline =
            observationRegistration.requiresRecencyDeadline
            ? nextDatesByPaneID.values.min()
            : nil
        guard
            let nextDeadline = [nextPaneDeadline, result.nextRepositoryActivityTransitionAt]
                .compactMap(\.self).min()
        else { return }
        let deadlinePaneIDs = Set(
            nextDatesByPaneID.compactMap { paneID, deadline in deadline == nextDeadline ? paneID : nil }
        )
        let delayNanoseconds = Int64(max(0, nextDeadline.timeIntervalSince(now)) * 1_000_000_000)
        let generation = observationGeneration
        let delay = recencyDelay
        recencyDeadlineTask = Task { [weak self] in
            do {
                try await Self.waitForRecencyDeadline(
                    delay: delay,
                    duration: .nanoseconds(delayNanoseconds)
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isDemanded, self.observationGeneration == generation else { return }
                self.recencyReferenceDate = self.recencyNow()
                for (repositoryID, transitionAt) in result.repositoryActivityTransitionAtByRepoId
                where transitionAt == nextDeadline {
                    self.pendingInvalidation.insert(.repositoryActivity(repositoryID))
                }
                for paneID in deadlinePaneIDs {
                    self.pendingInvalidation.insert(.pane(paneID))
                }
                self.enqueuePendingInvalidationTurn()
            }
        }
    }

    @concurrent nonisolated private static func waitForRecencyDeadline(
        delay: AsyncDelay,
        duration: Duration
    ) async throws {
        try await delay.wait(duration)
    }

    private func enqueuePendingInvalidationTurn() {
        guard invalidationTask == nil else { return }
        invalidationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.invalidationTask = nil
            self.processPendingInvalidation()
        }
    }
}
