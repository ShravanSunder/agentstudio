import Foundation

@MainActor
extension PaneCoordinator {
    func logRestoreAllViewsDuration(
        start: ContinuousClock.Instant?,
        paneCount: Int,
        visibleCount: Int,
        hiddenCount: Int,
        progress: RestoreAllViewsProgress
    ) {
        RestoreTrace.logDuration(
            "restore_all_views",
            start: start,
            fields: [
                ("panes", "\(paneCount)"),
                ("visible", "\(visibleCount)"),
                ("hidden", "\(hiddenCount)"),
                ("restored", "\(progress.restored)"),
                ("drawerRestored", "\(progress.drawerRestored)"),
                ("failed", "\(progress.failedPaneIds.count + progress.failedDrawerPaneIds.count)"),
            ]
        )
    }

    func restoreTraceFields(forPaneId paneId: UUID) -> [(String, String)] {
        guard let pane = store.paneAtom.pane(paneId) else {
            return [
                ("pane", paneId.uuidString),
                ("tier", "missing"),
                ("content", "missing"),
            ]
        }
        return restoreTraceFields(for: pane, outcome: nil)
    }

    func restoreTraceFields(for pane: Pane, outcome: String?) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("pane", pane.id.uuidString),
            ("tier", String(describing: visibilityTierResolver.tier(for: PaneId(uuid: pane.id)))),
            ("content", restoreTraceContentKind(for: pane.content)),
        ]
        if let outcome {
            fields.append(("outcome", outcome))
        }
        return fields
    }

    private func restoreTraceContentKind(for content: PaneContent) -> String {
        switch content {
        case .terminal:
            "terminal"
        case .webview:
            "webview"
        case .codeViewer:
            "codeViewer"
        case .bridgePanel:
            "bridgePanel"
        case .unsupported:
            "unsupported"
        }
    }
}
