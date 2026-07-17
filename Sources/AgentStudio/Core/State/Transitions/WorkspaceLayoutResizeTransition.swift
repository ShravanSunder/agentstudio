import Foundation

enum WorkspaceLayoutResizeCheckpoint: Equatable, Sendable {
    case mainSplit(tabID: UUID, arrangementID: UUID, splitID: UUID, ratio: Double)
    // Exact discriminated checkpoint shape; correlated fields are intentionally non-optional.
    // swiftlint:disable:next enum_case_associated_values_count
    case mainVisiblePair(
        tabID: UUID,
        arrangementID: UUID,
        leftPaneID: UUID,
        rightPaneID: UUID,
        ratio: Double
    )
    // swiftlint:disable:next enum_case_associated_values_count
    case drawerSplit(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        splitID: UUID,
        ratio: Double
    )
    // swiftlint:disable:next enum_case_associated_values_count
    case drawerVisiblePair(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        leftPaneID: UUID,
        rightPaneID: UUID,
        ratio: Double
    )
}

struct WorkspaceMainSplitResizeTarget: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let splitID: UUID
}

struct WorkspaceMainVisiblePairResizeTarget: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let leftPaneID: UUID
    let rightPaneID: UUID
}

struct WorkspaceDrawerSplitResizeTarget: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let drawerID: UUID
    let splitID: UUID
}

struct WorkspaceDrawerVisiblePairResizeTarget: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let drawerID: UUID
    let leftPaneID: UUID
    let rightPaneID: UUID
}

enum WorkspaceLayoutResizeTarget: Equatable, Sendable {
    case mainSplit(WorkspaceMainSplitResizeTarget)
    case mainVisiblePair(WorkspaceMainVisiblePairResizeTarget)
    case drawerSplit(WorkspaceDrawerSplitResizeTarget)
    case drawerVisiblePair(WorkspaceDrawerVisiblePairResizeTarget)
}

enum WorkspaceLayoutResizePlanningContext: Equatable, Sendable {
    case missingTab
    case missingActiveArrangement(tab: TabGraphState)
    case selectedActiveArrangement(tab: TabGraphState, arrangementID: UUID)
}

struct WorkspaceLayoutResizeTransition: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let expectedActiveArrangement: WorkspaceActiveArrangementSelection
    let previousTabGraph: TabGraphState
    let replacementTabGraph: TabGraphState
}

enum WorkspaceLayoutResizeRejection: Equatable, Sendable {
    case invalidRatio(Double)
    case missingTab(UUID)
    case tabIdentityMismatch(requested: UUID, actual: UUID)
    case missingActiveArrangement(UUID)
    case activeArrangementMismatch(tabID: UUID, requested: UUID, active: UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case missingMainSplit(tabID: UUID, arrangementID: UUID, splitID: UUID)
    case invalidMainVisiblePair(tabID: UUID, arrangementID: UUID, leftPaneID: UUID, rightPaneID: UUID)
    case missingDrawer(tabID: UUID, arrangementID: UUID, drawerID: UUID)
    case missingDrawerSplit(tabID: UUID, arrangementID: UUID, drawerID: UUID, splitID: UUID)
    // swiftlint:disable:next enum_case_associated_values_count
    case drawerVisiblePairCrossesRows(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        leftPaneID: UUID,
        rightPaneID: UUID
    )
    // swiftlint:disable:next enum_case_associated_values_count
    case invalidDrawerVisiblePair(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        leftPaneID: UUID,
        rightPaneID: UUID
    )
}

enum WorkspaceLayoutResizeDecision: Equatable, Sendable {
    case changed(WorkspaceLayoutResizeTransition)
    case unchanged
    case rejected(WorkspaceLayoutResizeRejection)
}

enum WorkspaceLayoutResizeTransitionPlanner {
    // The exhaustive checkpoint switch keeps all four strict union variants visible together.
    // swiftlint:disable:next function_body_length
    static func plan(
        _ checkpoint: WorkspaceLayoutResizeCheckpoint,
        context: WorkspaceLayoutResizePlanningContext
    ) -> WorkspaceLayoutResizeDecision {
        guard checkpoint.ratio.isFinite, (0.1...0.9).contains(checkpoint.ratio) else {
            return .rejected(.invalidRatio(checkpoint.ratio))
        }

        let tab: TabGraphState
        let activeArrangementID: UUID
        switch context {
        case .missingTab:
            return .rejected(.missingTab(checkpoint.tabID))
        case .missingActiveArrangement(let contextTab):
            guard contextTab.tabId == checkpoint.tabID else {
                return .rejected(
                    .tabIdentityMismatch(requested: checkpoint.tabID, actual: contextTab.tabId)
                )
            }
            return .rejected(.missingActiveArrangement(checkpoint.tabID))
        case .selectedActiveArrangement(let contextTab, let selectedArrangementID):
            guard contextTab.tabId == checkpoint.tabID else {
                return .rejected(
                    .tabIdentityMismatch(requested: checkpoint.tabID, actual: contextTab.tabId)
                )
            }
            tab = contextTab
            activeArrangementID = selectedArrangementID
        }

        guard activeArrangementID == checkpoint.arrangementID else {
            return .rejected(
                .activeArrangementMismatch(
                    tabID: checkpoint.tabID,
                    requested: checkpoint.arrangementID,
                    active: activeArrangementID
                )
            )
        }
        guard let arrangementIndex = tab.arrangements.firstIndex(where: { $0.id == checkpoint.arrangementID }) else {
            return .rejected(
                .missingArrangement(tabID: checkpoint.tabID, arrangementID: checkpoint.arrangementID)
            )
        }

        var replacement = tab
        switch checkpoint {
        case .mainSplit(_, _, let splitID, let ratio):
            guard replacement.arrangements[arrangementIndex].layout.dividerIds.contains(splitID) else {
                return .rejected(
                    .missingMainSplit(
                        tabID: checkpoint.tabID,
                        arrangementID: checkpoint.arrangementID,
                        splitID: splitID
                    )
                )
            }
            replacement.arrangements[arrangementIndex].layout = replacement.arrangements[arrangementIndex].layout
                .resizing(splitId: splitID, ratio: ratio)
        case .mainVisiblePair(_, _, let leftPaneID, let rightPaneID, let ratio):
            let arrangement = replacement.arrangements[arrangementIndex]
            guard
                PaneResizeVisibilityResolver.validatesCollapsedRunPair(
                    layoutPaneIds: arrangement.layout.paneIds,
                    minimizedPaneIds: arrangement.minimizedPaneIds,
                    leftPaneId: leftPaneID,
                    rightPaneId: rightPaneID
                )
            else {
                return .rejected(
                    .invalidMainVisiblePair(
                        tabID: checkpoint.tabID,
                        arrangementID: checkpoint.arrangementID,
                        leftPaneID: leftPaneID,
                        rightPaneID: rightPaneID
                    )
                )
            }
            replacement.arrangements[arrangementIndex].layout = arrangement.layout.resizingPanePair(
                leftPaneId: leftPaneID,
                rightPaneId: rightPaneID,
                ratio: ratio
            )
        case .drawerSplit(_, _, let drawerID, let splitID, let ratio):
            guard var drawer = replacement.arrangements[arrangementIndex].drawerViews[drawerID] else {
                return .rejected(
                    .missingDrawer(
                        tabID: checkpoint.tabID,
                        arrangementID: checkpoint.arrangementID,
                        drawerID: drawerID
                    )
                )
            }
            guard drawer.layout.dividerIds.contains(splitID) else {
                return .rejected(
                    .missingDrawerSplit(
                        tabID: checkpoint.tabID,
                        arrangementID: checkpoint.arrangementID,
                        drawerID: drawerID,
                        splitID: splitID
                    )
                )
            }
            drawer.layout = drawer.layout.resizing(splitId: splitID, ratio: ratio)
            replacement.arrangements[arrangementIndex].drawerViews[drawerID] = drawer
        case .drawerVisiblePair(_, _, let drawerID, let leftPaneID, let rightPaneID, let ratio):
            guard var drawer = replacement.arrangements[arrangementIndex].drawerViews[drawerID] else {
                return .rejected(
                    .missingDrawer(
                        tabID: checkpoint.tabID,
                        arrangementID: checkpoint.arrangementID,
                        drawerID: drawerID
                    )
                )
            }
            let leftIsInTopRow = drawer.layout.topRow.contains(leftPaneID)
            let rightIsInTopRow = drawer.layout.topRow.contains(rightPaneID)
            let leftIsInBottomRow = drawer.layout.bottomRow?.contains(leftPaneID) == true
            let rightIsInBottomRow = drawer.layout.bottomRow?.contains(rightPaneID) == true
            guard
                (leftIsInTopRow || leftIsInBottomRow)
                    && (rightIsInTopRow || rightIsInBottomRow)
            else {
                return invalidDrawerPair(checkpoint, drawerID, leftPaneID, rightPaneID)
            }
            let topContainsBoth = leftIsInTopRow && rightIsInTopRow
            let bottomContainsBoth = leftIsInBottomRow && rightIsInBottomRow
            guard topContainsBoth || bottomContainsBoth else {
                return .rejected(
                    .drawerVisiblePairCrossesRows(
                        tabID: checkpoint.tabID,
                        arrangementID: checkpoint.arrangementID,
                        drawerID: drawerID,
                        leftPaneID: leftPaneID,
                        rightPaneID: rightPaneID
                    )
                )
            }
            if topContainsBoth {
                guard validatesPair(drawer.layout.topRow, drawer: drawer, leftPaneID, rightPaneID) else {
                    return invalidDrawerPair(checkpoint, drawerID, leftPaneID, rightPaneID)
                }
                drawer.layout.topRow = drawer.layout.topRow.resizingPanePair(
                    leftPaneId: leftPaneID,
                    rightPaneId: rightPaneID,
                    ratio: ratio
                )
            } else if let bottomRow = drawer.layout.bottomRow {
                guard validatesPair(bottomRow, drawer: drawer, leftPaneID, rightPaneID) else {
                    return invalidDrawerPair(checkpoint, drawerID, leftPaneID, rightPaneID)
                }
                drawer.layout.bottomRow = bottomRow.resizingPanePair(
                    leftPaneId: leftPaneID,
                    rightPaneId: rightPaneID,
                    ratio: ratio
                )
            }
            replacement.arrangements[arrangementIndex].drawerViews[drawerID] = drawer
        }

        guard replacement != tab else { return .unchanged }
        return .changed(
            WorkspaceLayoutResizeTransition(
                tabID: checkpoint.tabID,
                arrangementID: checkpoint.arrangementID,
                expectedActiveArrangement: .selected(activeArrangementID),
                previousTabGraph: tab,
                replacementTabGraph: replacement
            )
        )
    }

    private static func validatesPair(
        _ layout: Layout,
        drawer: DrawerViewGraphState,
        _ leftPaneID: UUID,
        _ rightPaneID: UUID
    ) -> Bool {
        PaneResizeVisibilityResolver.validatesCollapsedRunPair(
            layoutPaneIds: layout.paneIds,
            minimizedPaneIds: drawer.minimizedPaneIds,
            leftPaneId: leftPaneID,
            rightPaneId: rightPaneID
        )
    }

    private static func invalidDrawerPair(
        _ checkpoint: WorkspaceLayoutResizeCheckpoint,
        _ drawerID: UUID,
        _ leftPaneID: UUID,
        _ rightPaneID: UUID
    ) -> WorkspaceLayoutResizeDecision {
        .rejected(
            .invalidDrawerVisiblePair(
                tabID: checkpoint.tabID,
                arrangementID: checkpoint.arrangementID,
                drawerID: drawerID,
                leftPaneID: leftPaneID,
                rightPaneID: rightPaneID
            )
        )
    }
}

extension WorkspaceLayoutResizeCheckpoint {
    var target: WorkspaceLayoutResizeTarget {
        switch self {
        case .mainSplit(let tabID, let arrangementID, let splitID, _):
            .mainSplit(.init(tabID: tabID, arrangementID: arrangementID, splitID: splitID))
        case .mainVisiblePair(let tabID, let arrangementID, let leftPaneID, let rightPaneID, _):
            .mainVisiblePair(
                .init(
                    tabID: tabID,
                    arrangementID: arrangementID,
                    leftPaneID: leftPaneID,
                    rightPaneID: rightPaneID
                )
            )
        case .drawerSplit(let tabID, let arrangementID, let drawerID, let splitID, _):
            .drawerSplit(
                .init(
                    tabID: tabID,
                    arrangementID: arrangementID,
                    drawerID: drawerID,
                    splitID: splitID
                )
            )
        case .drawerVisiblePair(
            let tabID,
            let arrangementID,
            let drawerID,
            let leftPaneID,
            let rightPaneID,
            _
        ):
            .drawerVisiblePair(
                .init(
                    tabID: tabID,
                    arrangementID: arrangementID,
                    drawerID: drawerID,
                    leftPaneID: leftPaneID,
                    rightPaneID: rightPaneID
                )
            )
        }
    }

    var tabID: UUID {
        switch self {
        case .mainSplit(let tabID, _, _, _),
            .mainVisiblePair(let tabID, _, _, _, _),
            .drawerSplit(let tabID, _, _, _, _),
            .drawerVisiblePair(let tabID, _, _, _, _, _):
            tabID
        }
    }

    var arrangementID: UUID {
        switch self {
        case .mainSplit(_, let arrangementID, _, _),
            .mainVisiblePair(_, let arrangementID, _, _, _),
            .drawerSplit(_, let arrangementID, _, _, _),
            .drawerVisiblePair(_, let arrangementID, _, _, _, _):
            arrangementID
        }
    }

    var ratio: Double {
        switch self {
        case .mainSplit(_, _, _, let ratio),
            .mainVisiblePair(_, _, _, _, let ratio),
            .drawerSplit(_, _, _, _, let ratio),
            .drawerVisiblePair(_, _, _, _, _, let ratio):
            ratio
        }
    }
}
