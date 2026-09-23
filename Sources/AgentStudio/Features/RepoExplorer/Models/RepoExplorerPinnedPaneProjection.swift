import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package struct RepoExplorerPinnedPaneProjectionRequest: Sendable {
    let paneStatesByID: [UUID: PaneGraphState]
    let tabStatesByID: [UUID: TabGraphState]
    let tabIDsInOrder: [UUID]
    let activityFactsByPaneID: [UUID: PaneActivityStatusFact]
    let topologySnapshot: RepositoryTopologyReadSnapshot
    let organizationPreferences: RepoExplorerPaneOrganizationPreferences
    let terminalShellExecutablePath: String

    @MainActor
    package init(
        coreAtoms: CoreAtoms,
        sidebarPreferences: RepoExplorerSidebarPrefsAtom,
        referenceDate: Date,
        calendar: Calendar = .current,
        terminalShellExecutablePath: String = SessionConfiguration.defaultShell()
    ) {
        self.paneStatesByID = coreAtoms.workspacePaneGraph.paneStateSnapshot()
        self.tabStatesByID = coreAtoms.workspaceTabGraph.tabStateSnapshot()
        self.tabIDsInOrder = coreAtoms.workspaceTabGraph.tabIDsInOrder
        self.activityFactsByPaneID = coreAtoms.paneActivityStatus.statusSnapshot()
        self.topologySnapshot = coreAtoms.workspaceRepositoryTopology.captureReadSnapshot()
        self.organizationPreferences = RepoExplorerPaneOrganizationPreferences(
            groupingMode: sidebarPreferences.groupingMode(for: .panes),
            subgroupMode: sidebarPreferences.subgroupMode(for: .panes),
            sortField: sidebarPreferences.sortField(for: .panes),
            sortOrder: sidebarPreferences.sortDirection(for: .panes),
            referenceDate: referenceDate,
            calendar: calendar
        )
        self.terminalShellExecutablePath = terminalShellExecutablePath
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

        var members: [RepoExplorerPaneOrganizationMember] = []
        var seenPaneIDs = Set<UUID>()
        for (tabOrder, tabID) in request.tabIDsInOrder.enumerated() {
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

                let facets = paneState.durableContextFacets
                let association = request.topologySnapshot.validatedAssociation(
                    repoId: facets.repoId,
                    worktreeId: facets.worktreeId
                )
                let shellExecutablePath: String? =
                    if case .terminal = paneState.paneContent {
                        request.terminalShellExecutablePath
                    } else {
                        nil
                    }
                members.append(
                    RepoExplorerPaneOrganizationMember(
                        paneID: paneID,
                        repositoryID: association?.repo.id,
                        repositoryName: association?.repo.name,
                        tabID: tabID,
                        tabOrder: tabOrder,
                        normalizedTitle: RepoExplorerPaneTitleNormalizer.normalizedTitle(
                            liveTitle: paneState.title,
                            cwd: facets.cwd,
                            shellExecutablePath: shellExecutablePath,
                            isDrawer: paneState.isDrawerChild
                        ),
                        isPinned: true,
                        activityAt: request.activityFactsByPaneID[paneID]?.observedAt
                    )
                )
            }
        }

        return RepoExplorerPinnedPaneNavigationPolicy.orderedPaneIDs(
            RepoExplorerPaneOrganizationInput(
                members: members,
                preferences: request.organizationPreferences
            )
        )
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
