import Foundation

struct WorkspaceKeyboardResizeRequest: Equatable {
    let tabID: UUID
    let paneID: UUID
    let direction: SplitResizeDirection
    let amount: UInt16
}

enum WorkspaceKeyboardResizePlanningContext: Equatable, Sendable {
    case missingTab
    case present(
        tab: TabGraphState,
        activeArrangement: WorkspaceActiveArrangementSelection,
        zoom: WorkspaceZoomSelection
    )
}

enum WorkspaceKeyboardResizeRejection: Equatable {
    case missingTab(UUID)
    case tabIdentityMismatch(requested: UUID, actual: UUID)
    case missingActiveArrangement(UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case zoomed(tabID: UUID, paneID: UUID)
    case missingPane(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case missingVisiblePair(
        tabID: UUID,
        arrangementID: UUID,
        paneID: UUID,
        direction: SplitResizeDirection
    )
    case missingCurrentRatio(
        tabID: UUID,
        arrangementID: UUID,
        leftPaneID: UUID,
        rightPaneID: UUID
    )
}

enum WorkspaceKeyboardResizeDecision: Equatable {
    case changed(WorkspaceLayoutResizeCheckpoint)
    case unchanged
    case rejected(WorkspaceKeyboardResizeRejection)
}

enum WorkspaceKeyboardResizePersistenceFailure: Equatable {
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case planning(WorkspaceKeyboardResizeRejection)
    case layoutResize(WorkspaceLayoutResizePersistenceFailure)
}

enum WorkspaceKeyboardResizePersistenceResult: Equatable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceKeyboardResizePersistenceFailure)
}

private struct WorkspaceKeyboardResizeResolvedPair {
    let arrangement: PaneArrangementGraphState
    let pair: VisiblePaneResizePair
    let increasesRatio: Bool
    let currentRatio: Double
}

enum WorkspaceKeyboardResizeCheckpointPlanner {
    static let ratioStep = 0.05
    static let baseAmount = 10.0

    static func plan(
        _ request: WorkspaceKeyboardResizeRequest,
        context: WorkspaceKeyboardResizePlanningContext
    ) -> WorkspaceKeyboardResizeDecision {
        let tab: TabGraphState
        let activeArrangement: WorkspaceActiveArrangementSelection
        let zoom: WorkspaceZoomSelection
        switch context {
        case .missingTab:
            return .rejected(.missingTab(request.tabID))
        case .present(let presentTab, let presentActiveArrangement, let presentZoom):
            tab = presentTab
            activeArrangement = presentActiveArrangement
            zoom = presentZoom
        }

        guard tab.tabId == request.tabID else {
            return .rejected(.tabIdentityMismatch(requested: request.tabID, actual: tab.tabId))
        }
        switch zoom {
        case .notZoomed:
            break
        case .zoomed(let paneID):
            return .rejected(.zoomed(tabID: request.tabID, paneID: paneID))
        }

        let arrangementID: UUID
        switch activeArrangement {
        case .missing:
            return .rejected(.missingActiveArrangement(request.tabID))
        case .selected(let selectedArrangementID):
            arrangementID = selectedArrangementID
        }
        guard let arrangement = tab.arrangements.first(where: { $0.id == arrangementID }) else {
            return .rejected(.missingArrangement(tabID: request.tabID, arrangementID: arrangementID))
        }
        guard arrangement.layout.contains(request.paneID) else {
            return .rejected(
                .missingPane(
                    tabID: request.tabID,
                    arrangementID: arrangementID,
                    paneID: request.paneID
                )
            )
        }
        guard request.amount > 0 else { return .unchanged }
        guard
            let target = PaneResizeVisibilityResolver.keyboardPair(
                layout: arrangement.layout,
                minimizedPaneIds: arrangement.minimizedPaneIds,
                paneId: request.paneID,
                direction: request.direction
            )
        else {
            return .rejected(
                .missingVisiblePair(
                    tabID: request.tabID,
                    arrangementID: arrangementID,
                    paneID: request.paneID,
                    direction: request.direction
                )
            )
        }
        guard
            let currentRatio = arrangement.layout.ratioForPanePair(
                leftPaneId: target.pair.leftPaneId,
                rightPaneId: target.pair.rightPaneId
            )
        else {
            return .rejected(
                .missingCurrentRatio(
                    tabID: request.tabID,
                    arrangementID: arrangementID,
                    leftPaneID: target.pair.leftPaneId,
                    rightPaneID: target.pair.rightPaneId
                )
            )
        }

        return decision(
            for: request,
            resolved: WorkspaceKeyboardResizeResolvedPair(
                arrangement: arrangement,
                pair: target.pair,
                increasesRatio: target.increase,
                currentRatio: currentRatio
            )
        )
    }

    private static func decision(
        for request: WorkspaceKeyboardResizeRequest,
        resolved: WorkspaceKeyboardResizeResolvedPair
    ) -> WorkspaceKeyboardResizeDecision {
        let delta = ratioStep * (Double(request.amount) / baseAmount)
        let requestedRatio = resolved.increasesRatio ? resolved.currentRatio + delta : resolved.currentRatio - delta
        let replacementRatio = min(0.9, max(0.1, requestedRatio))
        guard replacementRatio != resolved.currentRatio else { return .unchanged }
        guard
            let leftPaneIndex = resolved.arrangement.layout.paneIds.firstIndex(of: resolved.pair.leftPaneId),
            let rightPaneIndex = resolved.arrangement.layout.paneIds.firstIndex(of: resolved.pair.rightPaneId)
        else {
            return .rejected(
                .missingVisiblePair(
                    tabID: request.tabID,
                    arrangementID: resolved.arrangement.id,
                    paneID: request.paneID,
                    direction: request.direction
                )
            )
        }
        if rightPaneIndex == leftPaneIndex + 1 {
            return .changed(
                .mainSplit(
                    tabID: request.tabID,
                    arrangementID: resolved.arrangement.id,
                    splitID: resolved.arrangement.layout.dividerIds[leftPaneIndex],
                    ratio: replacementRatio
                )
            )
        }
        return .changed(
            .mainVisiblePair(
                tabID: request.tabID,
                arrangementID: resolved.arrangement.id,
                leftPaneID: resolved.pair.leftPaneId,
                rightPaneID: resolved.pair.rightPaneId,
                ratio: replacementRatio
            )
        )
    }
}
