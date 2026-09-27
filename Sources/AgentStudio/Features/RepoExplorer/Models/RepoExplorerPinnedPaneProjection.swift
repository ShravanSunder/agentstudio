import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package struct RepoExplorerPinnedPaneProjectionRequest: Sendable {
    let paneStatesByID: [UUID: PaneGraphState]
    let tabStatesByID: [UUID: TabGraphState]
    let tabIDsInOrder: [UUID]
    let activityTimesByPaneID: [UUID: PaneActivityTime]

    @MainActor
    package init(
        coreAtoms: CoreAtoms
    ) {
        self.paneStatesByID = coreAtoms.workspacePaneGraph.paneStateSnapshot()
        self.tabStatesByID = coreAtoms.workspaceTabGraph.tabStateSnapshot()
        self.tabIDsInOrder = coreAtoms.workspaceTabGraph.tabIDsInOrder
        self.activityTimesByPaneID = coreAtoms.paneActivityTime.snapshot()
    }
}

package enum RepoExplorerPinnedPaneProjector {
    @concurrent nonisolated package static func project(
        _ request: RepoExplorerPinnedPaneProjectionRequest,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) async throws -> [UUID] {
        let clock = ContinuousClock()
        let started = clock.now
        defer {
            performanceTraceRecorder?.recordDuration(
                .sidebarProjection,
                duration: started.duration(to: clock.now),
                attributes: [
                    "agentstudio.performance.sidebar.surface": .string("repo"),
                    "agentstudio.performance.sidebar.query_state": .string("empty"),
                    "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
                    "agentstudio.performance.sidebar.phase": .string("pinned_projection_worker"),
                    "agentstudio.performance.sidebar.trigger": .string("pinned_navigation"),
                ]
            )
        }
        try Task.checkCancellation()

        var eligiblePaneIDs: [UUID] = []
        var seenPaneIDs = Set<UUID>()
        for tabID in request.tabIDsInOrder {
            guard let tabState = request.tabStatesByID[tabID] else { continue }
            for paneID in tabState.paneIDs {
                guard seenPaneIDs.insert(paneID).inserted,
                    let paneState = request.paneStatesByID[paneID],
                    paneState.sessionResidency.isActive,
                    paneState.isPinned
                else {
                    continue
                }
                try Task.checkCancellation()

                eligiblePaneIDs.append(paneID)
            }
        }

        return eligiblePaneIDs.sorted { lhsPaneID, rhsPaneID in
            RepoExplorerProjection.activityPrecedes(
                lhsPaneID: lhsPaneID,
                lhsTime: request.activityTimesByPaneID[lhsPaneID],
                rhsPaneID: rhsPaneID,
                rhsTime: request.activityTimesByPaneID[rhsPaneID]
            )
        }
    }

    @concurrent nonisolated package static func targetPaneID(
        from request: RepoExplorerPinnedPaneProjectionRequest,
        originPaneID: UUID?,
        previous: Bool,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) async throws -> UUID? {
        let orderedPaneIDs = try await project(request, performanceTraceRecorder: performanceTraceRecorder)
        return RepoExplorerPinnedPaneNavigationPolicy.targetPaneID(
            from: originPaneID,
            direction: previous ? .previous : .next,
            orderedPaneIDs: orderedPaneIDs
        )
    }
}
