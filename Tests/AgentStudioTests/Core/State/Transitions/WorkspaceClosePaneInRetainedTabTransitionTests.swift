import Foundation
import Testing

@testable import AgentStudio

@Suite("Close pane in retained tab transition")
struct WorkspaceClosePaneInRetainedTabTransitionTests {
    @Test("close removes one pane everywhere and selects strict fallbacks")
    func closeProducesExactRetainedTabTransition() throws {
        // Arrange
        let fixture = makeRetainedTabCloseFixture()

        // Act
        let decision = WorkspaceClosePaneInRetainedTabTransitionPlanner.plan(
            fixture.request,
            context: fixture.context(zoom: .zoomed(fixture.closedPaneID))
        )

        // Assert
        let transition = try requireRetainedTabCloseTransition(decision)
        #expect(transition.previousPane == fixture.pane)
        #expect(transition.previousTab == fixture.tab)
        #expect(transition.replacementTab.allPaneIds == [fixture.fallbackPaneID])
        #expect(
            transition.replacementTab.arrangements.allSatisfy {
                !$0.layout.contains(fixture.closedPaneID)
                    && !$0.minimizedPaneIds.contains(fixture.closedPaneID)
            }
        )
        #expect(transition.replacementTab.arrangements[0].layout.isEmpty)
        #expect(transition.replacementTab.arrangements[1].layout.paneIds == [fixture.fallbackPaneID])
        #expect(
            transition.activeArrangement
                == .replace(
                    tabID: fixture.tab.tabId,
                    previousArrangementID: fixture.selectedArrangementID,
                    replacementArrangementID: fixture.defaultArrangementID
                )
        )
        #expect(
            transition.activePanes
                == [
                    .replace(
                        arrangementID: fixture.selectedArrangementID,
                        previous: .present(.selected(fixture.closedPaneID)),
                        replacement: .noSelection
                    ),
                    .witness(
                        arrangementID: fixture.defaultArrangementID,
                        expected: .present(.selected(fixture.fallbackPaneID))
                    ),
                ]
        )
        #expect(
            transition.zoom
                == .clear(tabID: fixture.tab.tabId, previousPaneID: fixture.closedPaneID)
        )
        #expect(transition.drawerCursor == .collapsed)
    }

    @Test("not zoomed close retains an exact zoom witness")
    func notZoomedCloseRetainsWitness() throws {
        // Arrange
        let fixture = makeRetainedTabCloseFixture()

        // Act
        let decision = WorkspaceClosePaneInRetainedTabTransitionPlanner.plan(
            fixture.request,
            context: fixture.context(zoom: .notZoomed)
        )

        // Assert
        let transition = try requireRetainedTabCloseTransition(decision)
        #expect(transition.zoom == .witness(tabID: fixture.tab.tabId, expected: .notZoomed))
    }

    @Test("pane identity ownership activity and drawer failures are typed")
    func paneFailuresAreTyped() throws {
        // Arrange
        let fixture = makeRetainedTabCloseFixture()
        let wrongPaneID = UUIDv7.generate()
        let wrongOwnerID = UUIDv7.generate()
        let secondOwnerID = UUIDv7.generate()
        let wrongPane = PaneGraphState(
            pane: Pane(
                id: wrongPaneID,
                content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
                metadata: .init(title: "Wrong"),
                residency: .active,
                kind: .layout(drawer: Drawer(drawerId: UUIDv7.generate(), parentPaneId: wrongPaneID))
            )
        )
        var inactive = fixture.pane
        inactive.residency = .backgrounded
        var drawerChild = fixture.pane
        drawerChild.kind = .drawerChild(parentPaneId: fixture.fallbackPaneID)
        var mismatchedParent = fixture.pane
        mismatchedParent.kind = .layout(
            drawer: DrawerGraphState(
                drawerId: UUIDv7.generate(),
                parentPaneId: fixture.fallbackPaneID
            )
        )
        var populatedDrawer = fixture.pane
        populatedDrawer.withDrawer { $0.paneIds = [UUIDv7.generate()] }

        // Act / Assert
        #expect(planRetainedTabClose(fixture, pane: .missing) == .rejected(.paneMissing(fixture.closedPaneID)))
        #expect(
            planRetainedTabClose(fixture, pane: .present(wrongPane))
                == .rejected(.paneIdentityMismatch(expected: fixture.closedPaneID, actual: wrongPaneID))
        )
        #expect(planRetainedTabClose(fixture, ownership: .absent) == .rejected(.paneUnowned(fixture.closedPaneID)))
        #expect(
            planRetainedTabClose(fixture, ownership: .owned(tabID: wrongOwnerID))
                == .rejected(
                    .paneOwnedByWrongTab(
                        paneID: fixture.closedPaneID,
                        expectedTabID: fixture.tab.tabId,
                        actualTabID: wrongOwnerID
                    )
                )
        )
        #expect(
            planRetainedTabClose(
                fixture,
                ownership: .multiple([fixture.tab.tabId, secondOwnerID])
            )
                == .rejected(
                    .paneMultiplyOwned(
                        fixture.closedPaneID,
                        [fixture.tab.tabId, secondOwnerID]
                    )
                )
        )
        #expect(
            planRetainedTabClose(fixture, pane: .present(inactive)) == .rejected(.paneNotActive(fixture.closedPaneID)))
        #expect(
            planRetainedTabClose(fixture, pane: .present(drawerChild))
                == .rejected(.paneIsDrawerChild(fixture.closedPaneID)))
        #expect(
            planRetainedTabClose(fixture, pane: .present(mismatchedParent))
                == .rejected(
                    .paneDrawerParentMismatch(
                        paneID: fixture.closedPaneID,
                        actualParentPaneID: fixture.fallbackPaneID
                    )
                )
        )
        #expect(
            planRetainedTabClose(fixture, pane: .present(populatedDrawer))
                == .rejected(.paneDrawerPopulated(fixture.closedPaneID))
        )
        let drawerID = try #require(fixture.pane.drawer?.drawerId)
        #expect(
            WorkspaceClosePaneInRetainedTabTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(drawerCursor: .expanded(drawerID: drawerID))
            ) == .rejected(.paneDrawerExpanded(drawerID: drawerID))
        )
    }

    @Test("tab drain malformed graph and cursor failures are typed")
    func graphAndCursorFailuresAreTyped() {
        // Arrange
        let fixture = makeRetainedTabCloseFixture()
        var drained = fixture.tab
        drained.allPaneIds = [fixture.closedPaneID]
        var missingFromArrangement = fixture.tab
        missingFromArrangement.arrangements[1].layout = .autoTiled([fixture.fallbackPaneID])
        var duplicateArrangement = fixture.tab
        duplicateArrangement.arrangements[1] = makeRetainedTabCloseArrangement(
            id: fixture.selectedArrangementID,
            isDefault: true,
            paneIDs: [fixture.closedPaneID, fixture.fallbackPaneID]
        )
        var invalidCursor = fixture.cursors
        invalidCursor[0] = .init(
            arrangementID: fixture.selectedArrangementID,
            cursor: .present(.selected(UUIDv7.generate()))
        )

        // Act / Assert
        #expect(planRetainedTabClose(fixture, tab: .missing) == .rejected(.tabMissing(fixture.tab.tabId)))
        #expect(
            planRetainedTabClose(fixture, tab: .present(drained))
                == .rejected(.wouldRemoveLastPane(fixture.tab.tabId))
        )
        #expect(
            planRetainedTabClose(fixture, tab: .present(missingFromArrangement))
                == .rejected(
                    .arrangementMissingPane(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.defaultArrangementID,
                        paneID: fixture.closedPaneID
                    )
                )
        )
        #expect(
            planRetainedTabClose(fixture, tab: .present(duplicateArrangement))
                == .rejected(
                    .duplicateArrangementIdentity(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.selectedArrangementID
                    )
                )
        )
        #expect(
            planRetainedTabClose(fixture, cursors: Array(fixture.cursors.dropLast()))
                == .rejected(.cursorMissing(fixture.defaultArrangementID))
        )
        #expect(
            planRetainedTabClose(fixture, cursors: invalidCursor)
                == .rejected(
                    .cursorInvalid(
                        arrangementID: fixture.selectedArrangementID,
                        cursor: invalidCursor[0].cursor
                    )
                )
        )
    }

    @Test("transition construction is sealed to its planner source file")
    func transitionConstructionIsFilePrivate() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let ownerURL = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/Transitions/WorkspaceClosePaneInRetainedTabTransition.swift"
        )
        let ownerSource = try String(contentsOf: ownerURL, encoding: .utf8)
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let constructionPattern = try NSRegularExpression(
            pattern: #"WorkspaceClosePaneInRetainedTabTransition\s*\("#
        )

        // Act
        let externalConstructionSites = try retainedTabCloseSwiftSourceURLs(under: sourcesRoot)
            .filter { $0.standardizedFileURL != ownerURL.standardizedFileURL }
            .filter { url in
                let source = try String(contentsOf: url, encoding: .utf8)
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                return constructionPattern.firstMatch(in: source, range: range) != nil
            }

        // Assert
        #expect(ownerSource.contains("    fileprivate init("))
        #expect(externalConstructionSites.isEmpty)
    }
}

private func retainedTabCloseSwiftSourceURLs(under root: URL) throws -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys
        )
    else {
        return []
    }
    return try enumerator.compactMap { item -> URL? in
        guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
        let values = try url.resourceValues(forKeys: Set(keys))
        return values.isRegularFile == true ? url : nil
    }
}

struct RetainedTabCloseFixture {
    let closedPaneID: UUID
    let fallbackPaneID: UUID
    let selectedArrangementID: UUID
    let defaultArrangementID: UUID
    let pane: PaneGraphState
    let tab: TabGraphState
    let cursors: [WorkspaceClosePaneCursorWitness]

    var request: WorkspaceClosePaneInRetainedTabRequest {
        .init(paneID: closedPaneID, tabID: tab.tabId)
    }

    func context(
        pane: WorkspaceClosePaneWitness? = nil,
        ownership: WorkspaceClosePaneOwnershipWitness? = nil,
        tab: WorkspaceClosePaneTabWitness? = nil,
        activeArrangement: WorkspaceActiveArrangementSelection? = nil,
        cursors: [WorkspaceClosePaneCursorWitness]? = nil,
        drawerCursor: WorkspaceDrawerCursorSelection = .collapsed,
        zoom: WorkspaceZoomSelection = .notZoomed
    ) -> WorkspaceClosePaneInRetainedTabPlanningContext {
        .init(
            pane: pane ?? .present(self.pane),
            ownership: ownership ?? .owned(tabID: self.tab.tabId),
            tab: tab ?? .present(self.tab),
            activeArrangement: activeArrangement ?? .selected(selectedArrangementID),
            paneCursors: cursors ?? self.cursors,
            drawerCursor: drawerCursor,
            zoom: zoom
        )
    }
}

func makeRetainedTabCloseFixture() -> RetainedTabCloseFixture {
    let closedPaneID = UUIDv7.generate()
    let fallbackPaneID = UUIDv7.generate()
    let selectedArrangementID = UUIDv7.generate()
    let defaultArrangementID = UUIDv7.generate()
    let pane = PaneGraphState(
        pane: Pane(
            id: closedPaneID,
            content: .terminal(
                .init(provider: .ghostty, lifetime: .temporary, zmxSessionID: .generateUUIDv7())
            ),
            metadata: .init(title: "Closed"),
            residency: .active,
            kind: .layout(drawer: Drawer(drawerId: UUIDv7.generate(), parentPaneId: closedPaneID))
        )
    )
    let tab = TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: [closedPaneID, fallbackPaneID],
        arrangements: [
            makeRetainedTabCloseArrangement(
                id: selectedArrangementID,
                isDefault: false,
                paneIDs: [closedPaneID]
            ),
            makeRetainedTabCloseArrangement(
                id: defaultArrangementID,
                isDefault: true,
                paneIDs: [closedPaneID, fallbackPaneID],
                minimizedPaneIDs: [closedPaneID]
            ),
        ]
    )
    return .init(
        closedPaneID: closedPaneID,
        fallbackPaneID: fallbackPaneID,
        selectedArrangementID: selectedArrangementID,
        defaultArrangementID: defaultArrangementID,
        pane: pane,
        tab: tab,
        cursors: [
            .init(arrangementID: selectedArrangementID, cursor: .present(.selected(closedPaneID))),
            .init(arrangementID: defaultArrangementID, cursor: .present(.selected(fallbackPaneID))),
        ]
    )
}

func makeRetainedTabCloseArrangement(
    id: UUID,
    isDefault: Bool,
    paneIDs: [UUID],
    minimizedPaneIDs: [UUID] = []
) -> PaneArrangementGraphState {
    .init(
        id: id,
        name: isDefault ? "Default" : "Selected",
        isDefault: isDefault,
        layout: .autoTiled(paneIDs),
        minimizedPaneIds: Set(minimizedPaneIDs),
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
}

func planRetainedTabClose(
    _ fixture: RetainedTabCloseFixture,
    pane: WorkspaceClosePaneWitness? = nil,
    ownership: WorkspaceClosePaneOwnershipWitness? = nil,
    tab: WorkspaceClosePaneTabWitness? = nil,
    cursors: [WorkspaceClosePaneCursorWitness]? = nil
) -> WorkspaceClosePaneInRetainedTabDecision {
    WorkspaceClosePaneInRetainedTabTransitionPlanner.plan(
        fixture.request,
        context: fixture.context(pane: pane, ownership: ownership, tab: tab, cursors: cursors)
    )
}

func requireRetainedTabCloseTransition(
    _ decision: WorkspaceClosePaneInRetainedTabDecision
) throws -> WorkspaceClosePaneInRetainedTabTransition {
    guard case .changed(let transition) = decision else {
        throw RetainedTabCloseTestError.expectedTransition
    }
    return transition
}

enum RetainedTabCloseTestError: Error {
    case expectedTransition
}
