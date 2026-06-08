import Foundation

struct WorkspaceSQLiteSnapshotDiagnostics: Sendable {
    private let snapshot: WorkspaceSQLiteSnapshot

    init(snapshot: WorkspaceSQLiteSnapshot) {
        self.snapshot = snapshot
    }

    func attributes(error: (any Error)? = nil) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.workspace.snapshot.active_tab_id": .string(snapshot.activeTabId?.uuidString ?? "nil"),
            "agentstudio.workspace.snapshot.arrangement_count": .int(snapshot.tabs.flatMap(\.arrangements).count),
            "agentstudio.workspace.snapshot.pane_count": .int(snapshot.panes.count),
            "agentstudio.workspace.snapshot.repo_count": .int(snapshot.repos.count),
            "agentstudio.workspace.snapshot.tab_count": .int(snapshot.tabs.count),
            "agentstudio.workspace.snapshot.worktree_count": .int(snapshot.worktrees.count),
        ]

        let tabPaneMembershipMismatches = tabPaneMembershipMismatches()
        let sourceFacetMismatches = sourceFacetMismatches()
        attributes["agentstudio.workspace.snapshot.has_tab_membership_mismatch"] =
            .bool(!tabPaneMembershipMismatches.isEmpty)
        attributes["agentstudio.workspace.snapshot.has_source_facet_mismatch"] =
            .bool(!sourceFacetMismatches.isEmpty)
        attributes["agentstudio.workspace.snapshot.tab_pane_counts"] =
            .stringArray(snapshot.tabs.map(Self.tabPaneCountSummary(_:)))
        attributes["agentstudio.workspace.snapshot.arrangement_pane_counts"] =
            .stringArray(snapshot.tabs.flatMap(Self.arrangementPaneCountSummaries(_:)))
        attributes["agentstudio.workspace.snapshot.drawer_view_pane_counts"] =
            .stringArray(snapshot.tabs.flatMap(Self.drawerViewPaneCountSummaries(_:)))
        attributes["agentstudio.workspace.snapshot.tab_membership_mismatches"] =
            .stringArray(tabPaneMembershipMismatches)
        attributes["agentstudio.workspace.snapshot.source_facet_mismatches"] =
            .stringArray(sourceFacetMismatches)

        if let error {
            attributes["agentstudio.persistence.error.description"] = .string(String(describing: error))
        }

        return attributes
    }

    private func tabPaneMembershipMismatches() -> [String] {
        snapshot.tabs.flatMap { tab in
            let tabPaneIds = Set(tab.allPaneIds)
            return tab.arrangements.flatMap { arrangement in
                arrangement.layout.paneIds.compactMap {
                    mismatchSummary(
                        tabId: tab.id,
                        arrangementId: arrangement.id,
                        drawerId: nil,
                        paneId: $0,
                        source: "arrangement_layout",
                        tabPaneIds: tabPaneIds
                    )
                }
                    + arrangement.drawerViews.flatMap { drawerId, drawerView in
                        drawerView.layout.paneIds.compactMap {
                            mismatchSummary(
                                tabId: tab.id,
                                arrangementId: arrangement.id,
                                drawerId: drawerId,
                                paneId: $0,
                                source: "drawer_view",
                                tabPaneIds: tabPaneIds
                            )
                        }
                    }
            }
        }
    }

    private func mismatchSummary(
        tabId: UUID,
        arrangementId: UUID,
        drawerId: UUID?,
        paneId: UUID,
        source: String,
        tabPaneIds: Set<UUID>
    ) -> String? {
        guard !tabPaneIds.contains(paneId) else { return nil }
        var parts = [
            "tab=\(tabId.uuidString)",
            "arrangement=\(arrangementId.uuidString)",
        ]
        if let drawerId {
            parts.append("drawer=\(drawerId.uuidString)")
        }
        parts.append("pane=\(paneId.uuidString)")
        parts.append("source=\(source)")
        return parts.joined(separator: "|")
    }

    private func sourceFacetMismatches() -> [String] {
        snapshot.panes.compactMap { pane in
            guard
                case .worktree(let worktreeId, let repoId, _) = pane.metadata.source,
                pane.metadata.facets.repoId != nil || pane.metadata.facets.worktreeId != nil
            else {
                return nil
            }

            var parts: [String] = ["pane=\(pane.id.uuidString)"]
            if let facetRepoId = pane.metadata.facets.repoId, facetRepoId != repoId {
                parts.append("sourceRepo=\(repoId.uuidString)")
                parts.append("facetRepo=\(facetRepoId.uuidString)")
            }
            if let facetWorktreeId = pane.metadata.facets.worktreeId, facetWorktreeId != worktreeId {
                parts.append("sourceWorktree=\(worktreeId.uuidString)")
                parts.append("facetWorktree=\(facetWorktreeId.uuidString)")
            }
            return parts.count > 1 ? parts.joined(separator: "|") : nil
        }
    }

    private static func tabPaneCountSummary(_ tab: Tab) -> String {
        "tab=\(tab.id.uuidString)|panes=\(tab.allPaneIds.count)"
    }

    private static func arrangementPaneCountSummaries(_ tab: Tab) -> [String] {
        tab.arrangements.map { arrangement in
            [
                "tab=\(tab.id.uuidString)",
                "arrangement=\(arrangement.id.uuidString)",
                "panes=\(arrangement.layout.paneIds.count)",
            ].joined(separator: "|")
        }
    }

    private static func drawerViewPaneCountSummaries(_ tab: Tab) -> [String] {
        tab.arrangements.flatMap { arrangement in
            arrangement.drawerViews.keys.sorted(by: { $0.uuidString < $1.uuidString }).compactMap { drawerId in
                guard let drawerView = arrangement.drawerViews[drawerId] else { return nil }
                return [
                    "tab=\(tab.id.uuidString)",
                    "arrangement=\(arrangement.id.uuidString)",
                    "drawer=\(drawerId.uuidString)",
                    "panes=\(drawerView.layout.paneIds.count)",
                ].joined(separator: "|")
            }
        }
    }
}
