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
            "agentstudio.workspace.snapshot.tab_count": .int(snapshot.tabs.count),
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
            let arrangementMismatches = tab.arrangements.flatMap { arrangement in
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

            let arrangedPaneIds = Set(
                tab.arrangements.flatMap { arrangement in
                    arrangement.layout.paneIds
                        + arrangement.drawerViews.values.flatMap(\.layout.paneIds)
                }
            )
            let orphanedMembershipMismatches =
                tabPaneIds
                .subtracting(arrangedPaneIds)
                .sorted(by: { $0.uuidString < $1.uuidString })
                .map {
                    membershipOrphanSummary(
                        tabId: tab.id,
                        paneId: $0
                    )
                }
            return arrangementMismatches + orphanedMembershipMismatches
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

    private func membershipOrphanSummary(tabId: UUID, paneId: UUID) -> String {
        [
            "tab=\(tabId.uuidString)",
            "pane=\(paneId.uuidString)",
            "source=membership_orphan",
        ].joined(separator: "|")
    }

    private func sourceFacetMismatches() -> [String] {
        // Source was removed as durable pane identity; facets are now the only
        // persisted workspace location truth. Keep the empty attribute for
        // trace schema stability, but there is no source/facet pair to compare.
        []
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
