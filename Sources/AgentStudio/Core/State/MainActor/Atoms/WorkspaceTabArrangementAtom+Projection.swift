import Foundation

extension WorkspaceTabArrangementAtom {
    static let resizeRatioStep: Double = 0.05
    static let resizeBaseAmount: Double = 10.0

    func findTabIndex(_ tabId: UUID) -> Int? {
        arrangementStates.firstIndex { $0.tabId == tabId }
    }

    func defaultArrangementIndex(for tabIndex: Int) -> Int {
        arrangementStates[tabIndex].arrangements.firstIndex(where: \.isDefault) ?? 0
    }

    func activeArrangementIndex(for tabIndex: Int) -> Int {
        arrangementStates[tabIndex].arrangements.firstIndex {
            $0.id == arrangementStates[tabIndex].activeArrangementId
        } ?? defaultArrangementIndex(for: tabIndex)
    }

    func defaultArrangement(for tabIndex: Int) -> PaneArrangement {
        arrangementStates[tabIndex].arrangements[defaultArrangementIndex(for: tabIndex)]
    }

    func activeArrangement(for tabIndex: Int) -> PaneArrangement {
        arrangementStates[tabIndex].arrangements[activeArrangementIndex(for: tabIndex)]
    }

    static func defaultArrangementIndex(in state: TabArrangementState) -> Int {
        state.arrangements.firstIndex(where: \.isDefault) ?? 0
    }

    static func activeArrangementIndex(in state: TabArrangementState) -> Int {
        state.arrangements.firstIndex { $0.id == state.activeArrangementId } ?? defaultArrangementIndex(in: state)
    }

    static func defaultArrangement(in state: TabArrangementState) -> PaneArrangement {
        state.arrangements[defaultArrangementIndex(in: state)]
    }

    static func activeArrangement(in state: TabArrangementState) -> PaneArrangement {
        state.arrangements[activeArrangementIndex(in: state)]
    }

    static func appendingPane(_ paneId: UUID, to layout: Layout) -> Layout? {
        guard let lastPaneId = layout.paneIds.last else {
            return Layout(paneId: paneId)
        }
        return layout.inserting(
            paneId: paneId,
            at: lastPaneId,
            direction: .horizontal,
            position: .after,
            sizingMode: .proportional
        )
    }

    static func drawerViewSeed(drawerId: UUID?, drawerPaneIds: [UUID]) -> DrawerView? {
        guard drawerId != nil, !drawerPaneIds.isEmpty else { return nil }
        return DrawerView(
            layout: DrawerGridLayout(topRow: Layout.autoTiled(drawerPaneIds)),
            activeChildId: drawerPaneIds[0],
            minimizedPaneIds: []
        )
    }

    func replaceArrangementStates(_ states: [TabArrangementState]) {
        let cursorReplacement = Self.makeArrangementCursorReplacement(from: states)
        graphAtom.replaceStates(states.map(TabGraphState.init))
        cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: cursorReplacement.activeArrangementIdsByTabId,
            paneCursorsByArrangementId: cursorReplacement.paneCursorsByArrangementId,
            drawerCursorsByKey: cursorReplacement.drawerCursorsByKey
        )
        presentationAtom.replaceStates(states)
    }

    private struct ArrangementCursorReplacement {
        let activeArrangementIdsByTabId: [UUID: UUID]
        let paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState]
        let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    }

    private static func makeArrangementCursorReplacement(
        from states: [TabArrangementState]
    ) -> ArrangementCursorReplacement {
        var activeArrangementIdsByTabId: [UUID: UUID] = [:]
        var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
        var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]

        for state in states {
            activeArrangementIdsByTabId[state.tabId] = state.activeArrangementId
            for arrangement in state.arrangements {
                paneCursorsByArrangementId[arrangement.id] = ArrangementPaneCursorState(
                    activePaneId: arrangement.activePaneId
                )
                for (drawerId, drawerView) in arrangement.drawerViews {
                    let cursorKey = ArrangementDrawerCursorKey(
                        arrangementId: arrangement.id,
                        drawerId: drawerId
                    )
                    drawerCursorsByKey[cursorKey] = ArrangementDrawerCursorState(
                        activeChildId: drawerView.activeChildId
                    )
                }
            }
        }

        return ArrangementCursorReplacement(
            activeArrangementIdsByTabId: activeArrangementIdsByTabId,
            paneCursorsByArrangementId: paneCursorsByArrangementId,
            drawerCursorsByKey: drawerCursorsByKey
        )
    }

    func composedArrangementStates() -> [TabArrangementState] {
        graphAtom.tabStates.map { graphState in
            let arrangements = graphState.arrangements.map { arrangementGraphState in
                var arrangement = PaneArrangement(
                    id: arrangementGraphState.id,
                    name: arrangementGraphState.name,
                    isDefault: arrangementGraphState.isDefault,
                    layout: arrangementGraphState.layout,
                    minimizedPaneIds: arrangementGraphState.minimizedPaneIds,
                    showsMinimizedPanes: arrangementGraphState.showsMinimizedPanes,
                    activePaneId: cursorAtom.activePaneId(forArrangement: arrangementGraphState.id),
                    drawerViews: Dictionary(
                        uniqueKeysWithValues: arrangementGraphState.drawerViews.map { drawerId, drawerGraphState in
                            var drawerView = DrawerView(
                                layout: drawerGraphState.layout,
                                activeChildId: cursorAtom.activeChildId(
                                    forArrangement: arrangementGraphState.id,
                                    drawerId: drawerId
                                ),
                                minimizedPaneIds: drawerGraphState.minimizedPaneIds
                            )
                            // DrawerView normalizes nil active children to the first pane.
                            // Cursor state must win so all-minimized drawers round-trip as nil.
                            drawerView.activeChildId = cursorAtom.activeChildId(
                                forArrangement: arrangementGraphState.id,
                                drawerId: drawerId
                            )
                            return (drawerId, drawerView)
                        }
                    )
                )
                // PaneArrangement also normalizes nil to a fallback pane; preserve the explicit cursor record.
                arrangement.activePaneId = cursorAtom.activePaneId(forArrangement: arrangementGraphState.id)
                return arrangement
            }
            let activeArrangementId =
                cursorAtom.activeArrangementId(forTab: graphState.tabId)
                ?? arrangements.first(where: \.isDefault)?.id
                ?? arrangements.first?.id
                ?? UUID()
            return TabArrangementState(
                tabId: graphState.tabId,
                allPaneIds: graphState.allPaneIds,
                arrangements: arrangements,
                activeArrangementId: activeArrangementId,
                zoomedPaneId: presentationAtom.zoomedPaneId(forTab: graphState.tabId)
            )
        }
    }
}
