import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation
import Observation

/// Temporary App composition snapshot for Repo Explorer command presentation.
/// It is advisory only; command execution always re-enters `AppCommandDispatcher`.
@MainActor
@Observable
final class RepoExplorerCommandPresentationBatch {
    /// Every sidebar request's capability derives from `WorkspaceCommandValidator.validate` over
    /// `actionStateSnapshot()`, which reads only these four global facts plus repo/worktree
    /// membership (tracked separately per visible key). Pane-to-worktree association never
    /// changes a capability result, so it is intentionally absent here.
    private struct CapabilityFactsFingerprint: Equatable {
        let activeTabID: UUID?
        let activePaneID: UUID?
        let activeTabZoom: ZoomPresentation?
        let isManagementLayerActive: Bool

        func globalCapabilitiesMatch(_ previous: Self) -> Bool {
            self == previous
        }
    }

    private struct ObservationCapture {
        let visibleWorktreeIDs: Set<UUID>
        let visibleRepositoryIDs: Set<UUID>
        let progressByRepositoryID: [UUID: RepositoryFactUpdateProgress]
        let capabilityFactsFingerprint: CapabilityFactsFingerprint
        let requests: Set<RepoExplorerCommandPresentationRequest>
        let favoriteStateByRepositoryID: [UUID: Bool]
    }

    private struct ResolvedBatch {
        let visibleSnapshot: RepoExplorerVisibleWorktreeSnapshot
        let visibleSetDelta: Set<UUID>
        let capabilityFactsFingerprint: CapabilityFactsFingerprint
        let requests: Set<RepoExplorerCommandPresentationRequest>
        let requestsToResolve: Set<RepoExplorerCommandPresentationRequest>
        let nextSnapshot: RepoExplorerCommandPresentationSnapshot
        let affectedWorktreeIDs: Set<UUID>
        let affectedRepositoryIDs: Set<UUID>
        let affectedRequestIdentities: Set<RepoExplorerCommandPresentationRequest>
        let toolbarChanged: Bool
        let shouldPublish: Bool
    }

    /// Which entry produced one refresh. `visibleSnapshot` means the materializer handed the
    /// batch a changed visible-worktree snapshot; `observation` means a tracked atom changed.
    package enum WakeTrigger: String, Sendable {
        case visibleSnapshot = "visible_snapshot"
        case observation = "observation"
    }

    /// Stable identity this batch presents to `RepoExplorerPresentationHostView.Coordinator` so it
    /// republishes the visible snapshot at least once for a newly attached batch, then suppresses
    /// republication for updates that carry an unchanged snapshot from the same batch.
    let consumerToken: UUID = UUIDv7.generate()

    private(set) var snapshot = RepoExplorerCommandPresentationSnapshot.empty
    private(set) var latestDelta: RepoExplorerCommandPresentationDelta?

    private let store: WorkspaceStore
    private let repoExplorerPrefs: RepoExplorerSidebarPrefsAtom
    private let dispatcher: AppCommandDispatcher
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var lastVisibleWorktreeIDs: Set<UUID> = []
    @ObservationIgnored private var lastVisibleRepositoryIDs: Set<UUID> = []
    @ObservationIgnored private var lastProgressByRepositoryID: [UUID: RepositoryFactUpdateProgress] = [:]
    @ObservationIgnored private var lastRequests: Set<RepoExplorerCommandPresentationRequest> = []
    @ObservationIgnored private var lastCapabilityFactsFingerprint: CapabilityFactsFingerprint?
    @ObservationIgnored private var currentVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot?
    @ObservationIgnored private var lastResolvedVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot?
    /// Only the most recently armed Observation tracking may schedule a refresh; older one-shot trackings stay installed until they fire and must be ignored.
    @ObservationIgnored private var armedTrackingGeneration: UInt64 = 0
    /// Generation of the newest observation wake awaiting the coalescing yield; nil when no wake is pending.
    @ObservationIgnored private var pendingObservationWakeGeneration: UInt64?

    init(
        store: WorkspaceStore,
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        dispatcher: AppCommandDispatcher,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.store = store
        self.repoExplorerPrefs = repoExplorerPrefs
        self.dispatcher = dispatcher
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    func start() {
        let observationID = UUID()
        self.observationID = observationID
        lastVisibleWorktreeIDs = []
        lastVisibleRepositoryIDs = []
        lastProgressByRepositoryID = [:]
        lastRequests = []
        lastCapabilityFactsFingerprint = nil
        currentVisibleSnapshot = nil
        lastResolvedVisibleSnapshot = nil
        latestDelta = nil
        armedTrackingGeneration &+= 1
    }

    func stop() {
        observationID = nil
        armedTrackingGeneration &+= 1
    }

    func acceptVisibleWorktreeSnapshot(_ visibleSnapshot: RepoExplorerVisibleWorktreeSnapshot) {
        guard let observationID else { return }
        guard currentVisibleSnapshot != visibleSnapshot else { return }
        currentVisibleSnapshot = visibleSnapshot
        refresh(observationID: observationID, trigger: .visibleSnapshot)
    }

    private func refresh(observationID: UUID, trigger: WakeTrigger) {
        guard self.observationID == observationID,
            let capturedVisibleSnapshot = currentVisibleSnapshot
        else { return }
        armedTrackingGeneration &+= 1
        let armedGeneration = armedTrackingGeneration
        let capture = withObservationTracking {
            let visibleWorktreeIDs = capturedVisibleSnapshot.worktreeIDs
            let progressByRepositoryID = Dictionary(
                uniqueKeysWithValues: capturedVisibleSnapshot.repositoryIDs.compactMap { repositoryID in
                    atom(\.repoCache).repositoryFactUpdateProgress(for: repositoryID).map {
                        (repositoryID, $0)
                    }
                }
            )
            return ObservationCapture(
                visibleWorktreeIDs: visibleWorktreeIDs,
                visibleRepositoryIDs: capturedVisibleSnapshot.repositoryIDs,
                progressByRepositoryID: progressByRepositoryID,
                capabilityFactsFingerprint: observeGlobalCapabilityFacts(),
                requests: commandPresentationRequests(
                    visibleWorktreeIDs: visibleWorktreeIDs,
                    visibleRepositoryIDs: capturedVisibleSnapshot.repositoryIDs
                ),
                favoriteStateByRepositoryID: favoriteStateByRepositoryID(
                    visibleWorktreeIDs: visibleWorktreeIDs
                )
            )
        } onChange: { [weak self] in
            // A wake arriving while one is pending records its (current) generation instead of
            // scheduling a second task. After the yield, refresh only if no other refresh
            // (visible snapshot, start, stop) has superseded the newest wake seen.
            Task { @MainActor [weak self] in
                guard let self, self.armedTrackingGeneration == armedGeneration else { return }
                if self.pendingObservationWakeGeneration != nil {
                    self.pendingObservationWakeGeneration = armedGeneration
                    return
                }
                self.pendingObservationWakeGeneration = armedGeneration
                await Task.yield()
                let newestWakeGeneration = self.pendingObservationWakeGeneration
                self.pendingObservationWakeGeneration = nil
                guard newestWakeGeneration == self.armedTrackingGeneration else { return }
                self.refresh(observationID: observationID, trigger: .observation)
            }
        }
        let resolvedBatch = resolve(
            capture: capture,
            capturedVisibleSnapshot: capturedVisibleSnapshot
        )
        publish(resolvedBatch, trigger: trigger)
    }

    private func resolve(
        capture: ObservationCapture,
        capturedVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot
    ) -> ResolvedBatch {
        let nextVisibleSnapshot = capturedVisibleSnapshot
        let visibleSetDelta = capture.visibleWorktreeIDs.symmetricDifference(lastVisibleWorktreeIDs)
        let previousFingerprint = lastCapabilityFactsFingerprint
        let globalCapabilitiesMatch =
            previousFingerprint.map {
                capture.capabilityFactsFingerprint.globalCapabilitiesMatch($0)
            } ?? false
        let retainedResults = snapshot.results.filter { capture.requests.contains($0.key) }
        let changedProgressRepositoryIDs = Set(lastProgressByRepositoryID.keys)
            .union(capture.progressByRepositoryID.keys)
            .filter { lastProgressByRepositoryID[$0] != capture.progressByRepositoryID[$0] }
        let requestsToResolve: Set<RepoExplorerCommandPresentationRequest>
        if snapshot.generation == 0 || !globalCapabilitiesMatch {
            requestsToResolve = capture.requests
        } else {
            var affectedRequests = capture.requests.subtracting(lastRequests)
            affectedRequests.formUnion(
                changedProgressRepositoryIDs.map { repositoryID in
                    RepoExplorerRepositoryCommandPresentation.request(repoID: repositoryID)
                }
            )
            requestsToResolve = affectedRequests
        }
        let nextGeneration = snapshot.generation &+ 1
        let resolvedResults =
            requestsToResolve.isEmpty
            ? [:]
            : dispatcher.repoExplorerCommandPresentationSnapshot(
                requests: requestsToResolve,
                generation: nextGeneration
            ).results
        let nextSnapshot = RepoExplorerCommandPresentationSnapshot(
            generation: nextGeneration,
            results: retainedResults.merging(resolvedResults) { _, resolved in resolved },
            favoriteStateByRepositoryID: capture.favoriteStateByRepositoryID
        )
        let targetChanged = nextVisibleSnapshot.target != lastResolvedVisibleSnapshot?.target
        let presentationChanged =
            snapshot.results != nextSnapshot.results
            || snapshot.favoriteStateByRepositoryID != nextSnapshot.favoriteStateByRepositoryID
        let affectedRequestIdentities =
            requestsToResolve
            .union(lastRequests.subtracting(capture.requests))
            .union(
                Set(snapshot.results.keys).union(nextSnapshot.results.keys).filter { request in
                    snapshot.results[request] != nextSnapshot.results[request]
                }
            )
        let affectedTargets = affectedTargets(
            requestIdentities: affectedRequestIdentities,
            visibleSetDelta: visibleSetDelta,
            targetChanged: targetChanged,
            visibleWorktreeIDs: capture.visibleWorktreeIDs
        )
        return ResolvedBatch(
            visibleSnapshot: nextVisibleSnapshot,
            visibleSetDelta: visibleSetDelta,
            capabilityFactsFingerprint: capture.capabilityFactsFingerprint,
            requests: capture.requests,
            requestsToResolve: requestsToResolve,
            nextSnapshot: nextSnapshot,
            affectedWorktreeIDs: affectedTargets.worktreeIDs,
            affectedRepositoryIDs: affectedTargets.repositoryIDs,
            affectedRequestIdentities: affectedRequestIdentities,
            toolbarChanged: Self.toolbarPresentationChanged(
                previous: snapshot.results,
                next: nextSnapshot.results
            ),
            shouldPublish: presentationChanged || targetChanged
        )
    }

    private func affectedTargets(
        requestIdentities: Set<RepoExplorerCommandPresentationRequest>,
        visibleSetDelta: Set<UUID>,
        targetChanged: Bool,
        visibleWorktreeIDs: Set<UUID>
    ) -> (worktreeIDs: Set<UUID>, repositoryIDs: Set<UUID>) {
        var affectedWorktreeIDs = visibleSetDelta
        var affectedRepositoryIDs: Set<UUID> = []
        for request in requestIdentities {
            switch request.targetType {
            case .worktree:
                if let target = request.target { affectedWorktreeIDs.insert(target) }
            case .repo:
                if let target = request.target { affectedRepositoryIDs.insert(target) }
            default:
                break
            }
        }
        if targetChanged {
            affectedWorktreeIDs.formUnion(lastVisibleWorktreeIDs)
            affectedWorktreeIDs.formUnion(visibleWorktreeIDs)
        }
        for worktreeID in visibleWorktreeIDs {
            guard let worktree = store.repositoryTopologyAtom.worktree(worktreeID) else { continue }
            if affectedRepositoryIDs.contains(worktree.repoId) {
                affectedWorktreeIDs.insert(worktreeID)
            }
        }
        return (affectedWorktreeIDs, affectedRepositoryIDs)
    }

    private func publish(_ resolvedBatch: ResolvedBatch, trigger: WakeTrigger) {
        lastVisibleWorktreeIDs = resolvedBatch.visibleSnapshot.worktreeIDs
        lastVisibleRepositoryIDs = resolvedBatch.visibleSnapshot.repositoryIDs
        lastProgressByRepositoryID = Dictionary(
            uniqueKeysWithValues: resolvedBatch.visibleSnapshot.repositoryIDs.compactMap { repositoryID in
                atom(\.repoCache).repositoryFactUpdateProgress(for: repositoryID).map {
                    (repositoryID, $0)
                }
            }
        )
        lastRequests = resolvedBatch.requests
        lastCapabilityFactsFingerprint = resolvedBatch.capabilityFactsFingerprint
        lastResolvedVisibleSnapshot = resolvedBatch.visibleSnapshot
        if resolvedBatch.shouldPublish {
            let affectedItemCount = Self.affectedItemCount(
                previous: snapshot.results,
                next: resolvedBatch.nextSnapshot.results
            )
            if affectedItemCount == 1 {
                RepoExplorerPerformanceTelemetry.shared.record(
                    stage: "command_affected_row",
                    outcome: "changed"
                )
            } else {
                RepoExplorerPerformanceTelemetry.shared.record(
                    stage: "command_whole_surface",
                    outcome: "changed"
                )
            }
            snapshot = resolvedBatch.nextSnapshot
            latestDelta = RepoExplorerCommandPresentationDelta(
                commandGeneration: resolvedBatch.nextSnapshot.generation,
                target: resolvedBatch.visibleSnapshot.target,
                snapshot: resolvedBatch.nextSnapshot,
                affectedWorktreeIDs: resolvedBatch.affectedWorktreeIDs,
                affectedRepositoryIDs: resolvedBatch.affectedRepositoryIDs,
                affectedRequestIdentities: resolvedBatch.affectedRequestIdentities,
                toolbarChanged: resolvedBatch.toolbarChanged
            )
        }
        let reusedCount = resolvedBatch.requests.count - resolvedBatch.requestsToResolve.count
        performanceTraceRecorder?.record(
            .repoExplorerCommandPresentation,
            attributes: [
                "agentstudio.performance.repo_explorer.visible_set.count": .int(
                    resolvedBatch.visibleSnapshot.worktreeIDs.count
                ),
                "agentstudio.performance.repo_explorer.visible_set_delta.count": .int(
                    resolvedBatch.visibleSetDelta.count
                ),
                "agentstudio.performance.repo_explorer.command_resolution.count": .int(
                    resolvedBatch.requestsToResolve.count
                ),
                "agentstudio.performance.repo_explorer.command_reused.count": .int(reusedCount),
                "agentstudio.performance.repo_explorer.wake_trigger": .string(trigger.rawValue),
            ]
        )
    }

    private static func toolbarPresentationChanged(
        previous: [RepoExplorerCommandPresentationRequest: Bool],
        next: [RepoExplorerCommandPresentationRequest: Bool]
    ) -> Bool {
        Set(previous.keys).union(next.keys).contains { request in
            request.target == nil && previous[request] != next[request]
        }
    }

    private static func affectedItemCount(
        previous: [RepoExplorerCommandPresentationRequest: Bool],
        next: [RepoExplorerCommandPresentationRequest: Bool]
    ) -> Int {
        Set(previous.keys).union(next.keys).count { request in
            previous[request] != next[request]
        }
    }

    /// Reads only the global facts `actionStateSnapshot()` feeds into every sidebar request's
    /// capability: the active tab, its active pane, that tab's zoom presentation, and the
    /// management layer. Never iterates tabs or panes and never assembles a `Tab`.
    private func observeGlobalCapabilityFacts() -> CapabilityFactsFingerprint {
        let activeTabID = store.tabLayoutAtom.activeTabId
        let activePaneID = activeTabID.flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
        let activeTabZoom = activeTabID.flatMap { store.panePresentationAtom.zoomPresentation(forTab: $0) }
        let isManagementLayerActive = atom(\.managementLayer).isActive
        return CapabilityFactsFingerprint(
            activeTabID: activeTabID,
            activePaneID: activePaneID,
            activeTabZoom: activeTabZoom,
            isManagementLayerActive: isManagementLayerActive
        )
    }

    private func commandPresentationRequests(
        visibleWorktreeIDs: Set<UUID>,
        visibleRepositoryIDs: Set<UUID>
    ) -> Set<RepoExplorerCommandPresentationRequest> {
        let nextSortOrder = repoExplorerPrefs.sortOrder.toggled
        var requests = RepoExplorerToolbarCommandPresentation.requests(
            nextSortOrder: nextSortOrder
        )
        requests.formUnion(
            visibleRepositoryIDs.map { repositoryID in
                RepoExplorerRepositoryCommandPresentation.request(repoID: repositoryID)
            }
        )

        for worktreeID in visibleWorktreeIDs {
            guard let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
                let repo = store.repositoryTopologyAtom.repo(worktree.repoId)
            else { continue }
            requests.formUnion(
                RepoExplorerWorktreeCommandPresentation.requests(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    isFavorite: repo.isFavorite,
                    showsFavoriteControl: worktree.isMainWorktree
                )
            )
        }
        return requests
    }

    private func favoriteStateByRepositoryID(
        visibleWorktreeIDs: Set<UUID>
    ) -> [UUID: Bool] {
        var favoriteStateByRepositoryID: [UUID: Bool] = [:]
        for worktreeID in visibleWorktreeIDs {
            guard let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
                let repo = store.repositoryTopologyAtom.repo(worktree.repoId)
            else { continue }
            favoriteStateByRepositoryID[repo.id] = repo.isFavorite
        }
        return favoriteStateByRepositoryID
    }
}
