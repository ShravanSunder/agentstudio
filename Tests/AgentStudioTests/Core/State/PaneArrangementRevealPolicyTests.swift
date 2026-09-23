import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("PaneArrangementRevealPolicy", .serialized)
struct PaneArrangementRevealPolicyTests {
    @Test("current visible main pane wins over earlier custom arrangement")
    func currentVisibleMainPaneWins() async throws {
        let fixture = makeMainPaneFixture()
        let snapshot = PaneArrangementRevealSnapshot(
            graphState: fixture.graphState,
            graphRevision: 7,
            activeArrangementID: fixture.currentArrangement.id
        )

        let selection = await PaneArrangementRevealPolicy.resolve(
            target: .mainPane(fixture.targetPaneID),
            from: snapshot
        )

        #expect(selection?.arrangementID == fixture.currentArrangement.id)
        #expect(selection?.requiresDrawerChildExpansion == false)
    }

    @Test("first visible custom in stored order wins when current minimizes main target")
    func firstVisibleCustomMainPaneWins() async throws {
        let fixture = makeMainPaneFixture(currentMinimizesTarget: true)
        let snapshot = PaneArrangementRevealSnapshot(
            graphState: fixture.graphState,
            graphRevision: 8,
            activeArrangementID: fixture.currentArrangement.id
        )

        let selection = await PaneArrangementRevealPolicy.resolve(
            target: .mainPane(fixture.targetPaneID),
            from: snapshot
        )

        #expect(selection?.arrangementID == fixture.firstCustomArrangement.id)
    }

    @Test("Default wins when no custom visibly contains main target")
    func defaultMainPaneFallbackWins() async throws {
        let fixture = makeMainPaneFixture(
            currentMinimizesTarget: true,
            firstCustomContainsTarget: false
        )
        let snapshot = PaneArrangementRevealSnapshot(
            graphState: fixture.graphState,
            graphRevision: 9,
            activeArrangementID: fixture.currentArrangement.id
        )

        let selection = await PaneArrangementRevealPolicy.resolve(
            target: .mainPane(fixture.targetPaneID),
            from: snapshot
        )

        #expect(selection?.arrangementID == fixture.defaultArrangement.id)
    }

    @Test("drawer child uses later visible custom when current child is minimized")
    func visibleCustomDrawerChildWins() async throws {
        let fixture = makeDrawerFixture(currentMinimizesChild: true)
        let snapshot = PaneArrangementRevealSnapshot(
            graphState: fixture.graphState,
            graphRevision: 10,
            activeArrangementID: fixture.currentArrangement.id
        )

        let selection = await PaneArrangementRevealPolicy.resolve(
            target: .drawerChild(
                paneID: fixture.targetPaneID,
                parentPaneID: fixture.parentPaneID,
                drawerID: fixture.drawerID
            ),
            from: snapshot
        )

        #expect(selection?.arrangementID == fixture.firstCustomArrangement.id)
        #expect(selection?.requiresDrawerChildExpansion == false)
    }

    @Test("Default drawer membership permits minimized-child fallback")
    func defaultDrawerMembershipPermitsMinimizedChildFallback() async throws {
        let fixture = makeDrawerFixture(
            currentMinimizesChild: true,
            firstCustomContainsChild: false,
            defaultMinimizesChild: true
        )
        let snapshot = PaneArrangementRevealSnapshot(
            graphState: fixture.graphState,
            graphRevision: 11,
            activeArrangementID: fixture.currentArrangement.id
        )

        let selection = await PaneArrangementRevealPolicy.resolve(
            target: .drawerChild(
                paneID: fixture.targetPaneID,
                parentPaneID: fixture.parentPaneID,
                drawerID: fixture.drawerID
            ),
            from: snapshot
        )

        #expect(selection?.arrangementID == fixture.defaultArrangement.id)
        #expect(selection?.requiresDrawerChildExpansion == true)
    }

    @Test("missing canonical target membership returns no selection")
    func missingCanonicalMembershipReturnsNil() async throws {
        let fixture = makeDrawerFixture(
            currentMinimizesChild: true,
            firstCustomContainsChild: false,
            defaultContainsChild: false
        )
        let snapshot = PaneArrangementRevealSnapshot(
            graphState: fixture.graphState,
            graphRevision: 12,
            activeArrangementID: fixture.currentArrangement.id
        )

        let selection = await PaneArrangementRevealPolicy.resolve(
            target: .drawerChild(
                paneID: fixture.targetPaneID,
                parentPaneID: fixture.parentPaneID,
                drawerID: fixture.drawerID
            ),
            from: snapshot
        )

        #expect(selection == nil)
    }

    @MainActor
    @Test("capture validation rejects superseded graph and arrangement cursor")
    func captureValidationRejectsStaleGraphAndCursor() async throws {
        let fixture = makeMainPaneFixture()
        let arrangementAtom = WorkspaceTabArrangementAtom()
        arrangementAtom.replaceArrangementStates([
            TabArrangementState(
                tabId: fixture.graphState.tabId,
                allPaneIds: fixture.graphState.allPaneIds,
                arrangements: [
                    fixture.defaultArrangement,
                    fixture.firstCustomArrangement,
                    fixture.currentArrangement,
                ],
                activeArrangementId: fixture.currentArrangement.id
            )
        ])
        let graphSnapshot = try #require(
            arrangementAtom.capturePaneArrangementRevealSnapshot(tabID: fixture.graphState.tabId)
        )
        let graphSelection = try #require(
            await PaneArrangementRevealPolicy.resolve(
                target: .mainPane(fixture.targetPaneID),
                from: graphSnapshot
            )
        )
        #expect(arrangementAtom.validatesPaneArrangementRevealSelection(graphSelection))

        var changedGraph = fixture.graphState
        changedGraph.arrangements[0].name = "Changed elsewhere"
        arrangementAtom.graphAtom.replaceTabStates([changedGraph])
        #expect(
            !arrangementAtom.validatesPaneArrangementRevealSelection(
                graphSelection
            )
        )

        arrangementAtom.replaceArrangementStates([
            TabArrangementState(
                tabId: fixture.graphState.tabId,
                allPaneIds: fixture.graphState.allPaneIds,
                arrangements: [
                    fixture.defaultArrangement,
                    fixture.firstCustomArrangement,
                    fixture.currentArrangement,
                ],
                activeArrangementId: fixture.currentArrangement.id
            )
        ])
        #expect(!arrangementAtom.validatesPaneArrangementRevealSelection(graphSelection))
        let cursorSnapshot = try #require(
            arrangementAtom.capturePaneArrangementRevealSnapshot(tabID: fixture.graphState.tabId)
        )
        let cursorSelection = try #require(
            await PaneArrangementRevealPolicy.resolve(
                target: .mainPane(fixture.targetPaneID),
                from: cursorSnapshot
            )
        )
        #expect(arrangementAtom.validatesPaneArrangementRevealSelection(cursorSelection))
        arrangementAtom.cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: [
                fixture.graphState.tabId: fixture.firstCustomArrangement.id
            ],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )

        #expect(
            !arrangementAtom.validatesPaneArrangementRevealSelection(
                cursorSelection
            )
        )
    }
}

private struct MainPaneRevealFixture {
    let targetPaneID: UUID
    let defaultArrangement: PaneArrangement
    let firstCustomArrangement: PaneArrangement
    let currentArrangement: PaneArrangement
    let graphState: TabGraphState
}

private func makeMainPaneFixture(
    currentMinimizesTarget: Bool = false,
    firstCustomContainsTarget: Bool = true
) -> MainPaneRevealFixture {
    let anchorPaneID = UUIDv7.generate()
    let targetPaneID = UUIDv7.generate()
    let defaultArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        layout: Layout.autoTiled([anchorPaneID, targetPaneID])
    )
    let firstCustomArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "First custom",
        isDefault: false,
        layout: Layout.autoTiled(
            firstCustomContainsTarget ? [anchorPaneID, targetPaneID] : [anchorPaneID]
        )
    )
    let currentArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Current",
        isDefault: false,
        layout: Layout.autoTiled([anchorPaneID, targetPaneID]),
        minimizedPaneIds: currentMinimizesTarget ? [targetPaneID] : []
    )
    return MainPaneRevealFixture(
        targetPaneID: targetPaneID,
        defaultArrangement: defaultArrangement,
        firstCustomArrangement: firstCustomArrangement,
        currentArrangement: currentArrangement,
        graphState: TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: [anchorPaneID, targetPaneID],
            arrangements: [
                PaneArrangementGraphState(defaultArrangement),
                PaneArrangementGraphState(firstCustomArrangement),
                PaneArrangementGraphState(currentArrangement),
            ]
        )
    )
}

private struct DrawerPaneRevealFixture {
    let parentPaneID: UUID
    let targetPaneID: UUID
    let drawerID: UUID
    let defaultArrangement: PaneArrangement
    let firstCustomArrangement: PaneArrangement
    let currentArrangement: PaneArrangement
    let graphState: TabGraphState
}

private func makeDrawerFixture(
    currentMinimizesChild: Bool,
    firstCustomContainsChild: Bool = true,
    defaultContainsChild: Bool = true,
    defaultMinimizesChild: Bool = false
) -> DrawerPaneRevealFixture {
    let parentPaneID = UUIDv7.generate()
    let targetPaneID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    func arrangement(
        id: UUID,
        name: String,
        isDefault: Bool,
        containsChild: Bool,
        minimizesChild: Bool
    ) -> PaneArrangement {
        PaneArrangement(
            id: id,
            name: name,
            isDefault: isDefault,
            layout: Layout(paneId: parentPaneID),
            drawerViews: containsChild
                ? [
                    drawerID: DrawerView(
                        layout: DrawerGridLayout(topRow: Layout(paneId: targetPaneID)),
                        minimizedPaneIds: minimizesChild ? [targetPaneID] : []
                    )
                ] : [:]
        )
    }
    let defaultArrangement = arrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        containsChild: defaultContainsChild,
        minimizesChild: defaultMinimizesChild
    )
    let firstCustomArrangement = arrangement(
        id: UUIDv7.generate(),
        name: "First custom",
        isDefault: false,
        containsChild: firstCustomContainsChild,
        minimizesChild: false
    )
    let currentArrangement = arrangement(
        id: UUIDv7.generate(),
        name: "Current",
        isDefault: false,
        containsChild: true,
        minimizesChild: currentMinimizesChild
    )
    return DrawerPaneRevealFixture(
        parentPaneID: parentPaneID,
        targetPaneID: targetPaneID,
        drawerID: drawerID,
        defaultArrangement: defaultArrangement,
        firstCustomArrangement: firstCustomArrangement,
        currentArrangement: currentArrangement,
        graphState: TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: [parentPaneID, targetPaneID],
            arrangements: [
                PaneArrangementGraphState(defaultArrangement),
                PaneArrangementGraphState(firstCustomArrangement),
                PaneArrangementGraphState(currentArrangement),
            ]
        )
    )
}
