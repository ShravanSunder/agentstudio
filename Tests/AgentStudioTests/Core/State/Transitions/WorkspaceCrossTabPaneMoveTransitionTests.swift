import Foundation
import Testing

@testable import AgentStudio

@Suite("Cross-tab pane move transition")
struct WorkspaceCrossTabPaneMoveTransitionTests {
    @Test("move replaces both tabs and every exact cursor witness")
    func moveProducesStrictTransition() throws {
        // Arrange
        let fixture = makeCrossTabMoveFixture()

        // Act
        let decision = WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
            fixture.request,
            context: fixture.context(
                activeTab: .selected(fixture.sourceTab.tabId),
                sourceZoom: .zoomed(fixture.movedPaneID),
                destinationZoom: .zoomed(fixture.targetPaneID)
            )
        )

        // Assert
        let transition = try requireChangedCrossTabMove(decision)
        #expect(transition.pane == .present(fixture.pane))
        #expect(transition.previousSourceTab == fixture.sourceTab)
        #expect(transition.replacementSourceTab.allPaneIds == [fixture.sourceFallbackPaneID])
        #expect(transition.replacementSourceTab.arrangements.allSatisfy { !$0.layout.contains(fixture.movedPaneID) })
        #expect(transition.previousDestinationTab == fixture.destinationTab)
        #expect(
            transition.replacementDestinationTab.allPaneIds
                == fixture.destinationTab.allPaneIds + [fixture.movedPaneID]
        )
        #expect(
            transition.replacementDestinationTab.arrangements.allSatisfy {
                $0.layout.contains(fixture.movedPaneID) && !$0.minimizedPaneIds.contains(fixture.movedPaneID)
            }
        )
        #expect(
            transition.sourceActiveArrangement
                == .witness(tabID: fixture.sourceTab.tabId, expected: .selected(fixture.sourceActiveArrangementID))
        )
        #expect(
            transition.destinationActiveArrangement
                == .witness(
                    tabID: fixture.destinationTab.tabId,
                    expected: .selected(fixture.destinationActiveArrangementID)
                )
        )
        #expect(
            transition.sourceActivePanes
                == [
                    .replace(
                        arrangementID: fixture.sourceActiveArrangementID,
                        previous: .present(.selected(fixture.movedPaneID)),
                        replacement: .selected(fixture.sourceFallbackPaneID)
                    ),
                    .witness(
                        arrangementID: fixture.sourceOtherArrangementID,
                        expected: .present(.selected(fixture.sourceFallbackPaneID))
                    ),
                ]
        )
        #expect(
            transition.destinationActivePanes
                == [
                    .replace(
                        arrangementID: fixture.destinationActiveArrangementID,
                        previous: .present(.selected(fixture.targetPaneID)),
                        replacement: .selected(fixture.movedPaneID)
                    ),
                    .witness(
                        arrangementID: fixture.destinationOtherArrangementID,
                        expected: .present(.selected(fixture.destinationOtherPaneID))
                    ),
                ]
        )
        #expect(
            transition.activeTab
                == .replace(
                    previous: .selected(fixture.sourceTab.tabId), replacementTabID: fixture.destinationTab.tabId)
        )
        #expect(
            transition.sourceZoom
                == .clear(tabID: fixture.sourceTab.tabId, previousPaneID: fixture.movedPaneID)
        )
        #expect(
            transition.destinationZoom
                == .clear(tabID: fixture.destinationTab.tabId, previousPaneID: fixture.targetPaneID)
        )
        for (previous, replacement) in zip(
            fixture.destinationTab.arrangements.map(\.layout),
            transition.replacementDestinationTab.arrangements.map(\.layout)
        ) {
            #expect(replacement.dividerIds.count == previous.dividerIds.count + 1)
            #expect(replacement.dividerIds.allSatisfy(UUIDv7.isV7))
        }
    }

    @Test("empty selected source arrangement switches to the nonempty default")
    func emptySelectedSourceSwitchesToDefault() throws {
        // Arrange
        var fixture = makeCrossTabMoveFixture()
        let customID = fixture.sourceActiveArrangementID
        let defaultID = fixture.sourceOtherArrangementID
        fixture.sourceTab.arrangements[0] = makeMoveArrangement(
            id: customID,
            isDefault: false,
            paneIDs: [fixture.movedPaneID]
        )
        fixture.sourceTab.arrangements[1] = makeMoveArrangement(
            id: defaultID,
            isDefault: true,
            paneIDs: [fixture.movedPaneID, fixture.sourceFallbackPaneID]
        )
        fixture.sourceCursors = [
            .init(arrangementID: customID, cursor: .present(.selected(fixture.movedPaneID))),
            .init(arrangementID: defaultID, cursor: .present(.selected(fixture.sourceFallbackPaneID))),
        ]

        // Act
        let decision = WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
            fixture.request,
            context: fixture.context()
        )

        // Assert
        let transition = try requireChangedCrossTabMove(decision)
        #expect(
            transition.sourceActiveArrangement
                == .replace(
                    tabID: fixture.sourceTab.tabId,
                    previousArrangementID: customID,
                    replacementArrangementID: defaultID
                )
        )
        #expect(
            transition.sourceActivePanes[0]
                == .replace(
                    arrangementID: customID,
                    previous: .present(.selected(fixture.movedPaneID)),
                    replacement: .noSelection
                )
        )
    }

    @Test("opaque existing identities are accepted")
    func opaqueIdentitiesAreAccepted() throws {
        // Arrange
        let fixture = makeCrossTabMoveFixture(identityFactory: UUID.init)

        // Act
        let decision = WorkspaceCrossTabPaneMoveTransitionPlanner.plan(fixture.request, context: fixture.context())

        // Assert
        _ = try requireChangedCrossTabMove(decision)
    }

    @Test("same tab, ownership, pane kind, residency, and drawer failures are typed")
    func paneAndOwnershipFailuresAreTyped() {
        // Arrange
        let fixture = makeCrossTabMoveFixture()
        var inactivePane = fixture.pane
        inactivePane.residency = .backgrounded
        var populatedDrawerPane = fixture.pane
        populatedDrawerPane.withDrawer { $0.paneIds = [UUIDv7.generate()] }
        var drawerChildPane = fixture.pane
        drawerChildPane.kind = .drawerChild(parentPaneId: UUIDv7.generate())

        // Act / Assert
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request(destinationTabID: fixture.sourceTab.tabId),
                context: fixture.context()
            ) == .rejected(.sameTab(fixture.sourceTab.tabId))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(ownership: .absent)
            ) == .rejected(.paneUnowned(fixture.movedPaneID))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(ownership: .multiple([fixture.sourceTab.tabId, fixture.destinationTab.tabId]))
            )
                == .rejected(
                    .paneMultiplyOwned(fixture.movedPaneID, [fixture.sourceTab.tabId, fixture.destinationTab.tabId]))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(pane: .present(inactivePane))
            ) == .rejected(.paneNotActive(fixture.movedPaneID))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(pane: .present(populatedDrawerPane))
            ) == .rejected(.paneDrawerPopulated(fixture.movedPaneID))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(pane: .present(drawerChildPane))
            ) == .rejected(.paneIsDrawerChild(fixture.movedPaneID))
        )
    }

    @Test("tab, membership, target, and source survival failures are typed")
    func graphFailuresAreTyped() {
        // Arrange
        let fixture = makeCrossTabMoveFixture()
        var partialSource = fixture.sourceTab
        partialSource.arrangements[1] = makeMoveArrangement(
            id: fixture.sourceOtherArrangementID,
            isDefault: false,
            paneIDs: [fixture.sourceFallbackPaneID]
        )
        var destinationContainsPane = fixture.destinationTab
        destinationContainsPane.allPaneIds.append(fixture.movedPaneID)
        let missingTargetPaneID = UUIDv7.generate()

        // Act / Assert
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(sourceTab: .missing)
            ) == .rejected(.sourceTabMissing(fixture.sourceTab.tabId))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(sourceTab: .present(partialSource))
            )
                == .rejected(
                    .sourceArrangementMissingPane(
                        tabID: fixture.sourceTab.tabId,
                        arrangementID: fixture.sourceOtherArrangementID,
                        paneID: fixture.movedPaneID
                    )
                )
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(destinationTab: .present(destinationContainsPane))
            ) == .rejected(.destinationAlreadyContainsPane(fixture.movedPaneID))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request(targetPaneID: missingTargetPaneID),
                context: fixture.context()
            )
                == .rejected(
                    .destinationTargetMissing(
                        tabID: fixture.destinationTab.tabId,
                        paneID: missingTargetPaneID
                    )
                )
        )
        var onePaneSource = fixture.sourceTab
        onePaneSource.allPaneIds = [fixture.movedPaneID]
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(sourceTab: .present(onePaneSource))
            ) == .rejected(.wouldEmptySourceTab(fixture.sourceTab.tabId))
        )
    }

    @Test("duplicate arrangements reject before dictionary construction")
    func duplicateArrangementRejectsWithoutTrap() {
        // Arrange
        let fixture = makeCrossTabMoveFixture()
        var duplicateSource = fixture.sourceTab
        duplicateSource.arrangements[1] = makeMoveArrangement(
            id: fixture.sourceActiveArrangementID,
            isDefault: false,
            paneIDs: [fixture.movedPaneID, fixture.sourceFallbackPaneID]
        )

        // Act
        let decision = WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
            fixture.request,
            context: fixture.context(sourceTab: .present(duplicateSource))
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .duplicateArrangementIdentity(
                        tabID: fixture.sourceTab.tabId, arrangementID: fixture.sourceActiveArrangementID)
                )
        )
    }

    @Test("cursor witness set and selection failures are typed")
    func cursorFailuresAreTyped() {
        // Arrange
        let fixture = makeCrossTabMoveFixture()
        let missing = Array(fixture.sourceCursors.dropLast())
        var invalid = fixture.destinationCursors
        invalid[0] = .init(
            arrangementID: fixture.destinationActiveArrangementID,
            cursor: .present(.selected(UUIDv7.generate()))
        )

        // Act / Assert
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(sourceCursors: missing)
            ) == .rejected(.cursorMissing(fixture.sourceOtherArrangementID))
        )
        #expect(
            WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
                fixture.request,
                context: fixture.context(destinationCursors: invalid)
            )
                == .rejected(
                    .cursorInvalid(
                        arrangementID: fixture.destinationActiveArrangementID,
                        cursor: invalid[0].cursor
                    )
                )
        )
    }

    @Test("transition construction is sealed to its planner source file")
    func transitionConstructionIsFilePrivate() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let ownerURL = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/Transitions/WorkspaceCrossTabPaneMoveTransition.swift"
        )
        let ownerSource = try String(contentsOf: ownerURL, encoding: .utf8)
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let constructionPattern = try NSRegularExpression(
            pattern: #"WorkspaceCrossTabPaneMoveTransition\s*\("#
        )

        // Act
        let externalConstructionSites = try swiftSourceURLs(under: sourcesRoot)
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

private func swiftSourceURLs(under root: URL) throws -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
        return []
    }
    return try enumerator.compactMap { item -> URL? in
        guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
        return try url.resourceValues(forKeys: Set(keys)).isRegularFile == true ? url : nil
    }
}

private struct CrossTabMoveFixture {
    let movedPaneID: UUID
    let sourceFallbackPaneID: UUID
    let targetPaneID: UUID
    let destinationOtherPaneID: UUID
    let pane: PaneGraphState
    var sourceTab: TabGraphState
    let destinationTab: TabGraphState
    let sourceActiveArrangementID: UUID
    let sourceOtherArrangementID: UUID
    let destinationActiveArrangementID: UUID
    let destinationOtherArrangementID: UUID
    var sourceCursors: [WorkspaceCrossTabPaneCursorWitness]
    let destinationCursors: [WorkspaceCrossTabPaneCursorWitness]

    var request: CrossTabPaneMoveRequest {
        request()
    }

    func request(
        destinationTabID: UUID? = nil,
        targetPaneID: UUID? = nil
    ) -> CrossTabPaneMoveRequest {
        .init(
            paneId: movedPaneID,
            sourceTabId: sourceTab.tabId,
            destTabId: destinationTabID ?? destinationTab.tabId,
            targetPaneId: targetPaneID ?? self.targetPaneID,
            direction: .vertical,
            position: .after
        )
    }

    func context(
        pane: WorkspaceCrossTabPaneWitness? = nil,
        ownership: WorkspaceCrossTabPaneOwnershipWitness? = nil,
        sourceTab: WorkspaceCrossTabTabWitness? = nil,
        destinationTab: WorkspaceCrossTabTabWitness? = nil,
        sourceActiveArrangement: WorkspaceActiveArrangementSelection? = nil,
        destinationActiveArrangement: WorkspaceActiveArrangementSelection? = nil,
        sourceCursors: [WorkspaceCrossTabPaneCursorWitness]? = nil,
        destinationCursors: [WorkspaceCrossTabPaneCursorWitness]? = nil,
        activeTab: WorkspaceTabCursorSelection = .selected(UUIDv7.generate()),
        sourceZoom: WorkspaceZoomSelection = .notZoomed,
        destinationZoom: WorkspaceZoomSelection = .notZoomed
    ) -> WorkspaceCrossTabPaneMovePlanningContext {
        .init(
            pane: pane ?? .present(self.pane),
            ownership: ownership ?? .owned(tabID: self.sourceTab.tabId),
            sourceTab: sourceTab ?? .present(self.sourceTab),
            destinationTab: destinationTab ?? .present(self.destinationTab),
            sourceActiveArrangement: sourceActiveArrangement ?? .selected(sourceActiveArrangementID),
            destinationActiveArrangement: destinationActiveArrangement ?? .selected(destinationActiveArrangementID),
            sourcePaneCursors: sourceCursors ?? self.sourceCursors,
            destinationPaneCursors: destinationCursors ?? self.destinationCursors,
            activeTab: activeTab,
            sourceZoom: sourceZoom,
            destinationZoom: destinationZoom
        )
    }
}

private func makeCrossTabMoveFixture(
    identityFactory: () -> UUID = UUIDv7.generate
) -> CrossTabMoveFixture {
    let moved = identityFactory()
    let sourceFallback = identityFactory()
    let target = identityFactory()
    let destinationOther = identityFactory()
    let sourceActive = identityFactory()
    let sourceOther = identityFactory()
    let destinationActive = identityFactory()
    let destinationOtherArrangement = identityFactory()
    let source = TabGraphState(
        tabId: identityFactory(),
        allPaneIds: [moved, sourceFallback],
        arrangements: [
            makeMoveArrangement(id: sourceActive, isDefault: true, paneIDs: [moved, sourceFallback]),
            makeMoveArrangement(id: sourceOther, isDefault: false, paneIDs: [moved, sourceFallback]),
        ]
    )
    let destination = TabGraphState(
        tabId: identityFactory(),
        allPaneIds: [target, destinationOther],
        arrangements: [
            makeMoveArrangement(id: destinationActive, isDefault: true, paneIDs: [target, destinationOther]),
            makeMoveArrangement(
                id: destinationOtherArrangement,
                isDefault: false,
                paneIDs: [destinationOther, target]
            ),
        ]
    )
    return .init(
        movedPaneID: moved,
        sourceFallbackPaneID: sourceFallback,
        targetPaneID: target,
        destinationOtherPaneID: destinationOther,
        pane: PaneGraphState(
            pane: Pane(
                id: moved,
                content: .terminal(
                    TerminalState(
                        provider: .ghostty,
                        lifetime: .temporary,
                        zmxSessionID: .generateUUIDv7()
                    )
                ),
                metadata: PaneMetadata(title: "Moved"),
                residency: .active,
                kind: .layout(drawer: Drawer(drawerId: identityFactory(), parentPaneId: moved))
            )
        ),
        sourceTab: source,
        destinationTab: destination,
        sourceActiveArrangementID: sourceActive,
        sourceOtherArrangementID: sourceOther,
        destinationActiveArrangementID: destinationActive,
        destinationOtherArrangementID: destinationOtherArrangement,
        sourceCursors: [
            .init(arrangementID: sourceActive, cursor: .present(.selected(moved))),
            .init(arrangementID: sourceOther, cursor: .present(.selected(sourceFallback))),
        ],
        destinationCursors: [
            .init(arrangementID: destinationActive, cursor: .present(.selected(target))),
            .init(arrangementID: destinationOtherArrangement, cursor: .present(.selected(destinationOther))),
        ]
    )
}

private func makeMoveArrangement(
    id: UUID,
    isDefault: Bool,
    paneIDs: [UUID]
) -> PaneArrangementGraphState {
    .init(
        id: id,
        name: isDefault ? "Default" : "Other",
        isDefault: isDefault,
        layout: Layout.autoTiled(paneIDs),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
}

private func requireChangedCrossTabMove(
    _ decision: WorkspaceCrossTabPaneMoveTransitionDecision
) throws -> WorkspaceCrossTabPaneMoveTransition {
    guard case .changed(let transition) = decision else {
        throw CrossTabMoveTestError.expectedChangedTransition
    }
    return transition
}

private enum CrossTabMoveTestError: Error {
    case expectedChangedTransition
}
