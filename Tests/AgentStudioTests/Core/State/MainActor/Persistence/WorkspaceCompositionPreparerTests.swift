import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace composition preparer")
struct WorkspaceCompositionPreparerTests {
    @Test("stale worktree metadata cannot discard composition panes")
    func staleWorktreeMetadataCannotDiscardCompositionPanes() async throws {
        // Arrange
        let staleWorktreeID = UUIDv7.generate()
        let storedText = "frozen-zmx-anchor"
        let zmxSessionID = try #require(ZmxSessionID(restoring: storedText))
        let pane = makeCompositionPane(
            worktreeID: staleWorktreeID,
            zmxSessionID: zmxSessionID
        )
        let tab = makeCompositionTab(paneID: pane.id)
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Composition",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id
        )

        // Act
        // This test deliberately crosses out of inherited MainActor isolation to prove the preparer is Sendable.
        // swiftlint:disable:next no_task_detached
        let result = await Task.detached {
            WorkspaceCompositionPreparer.prepare(snapshot)
        }.value

        // Assert
        let prepared = try requirePreparedComposition(result)
        #expect(prepared.panes.map(\.id) == [pane.id])
        #expect(prepared.panes[0].worktreeId == staleWorktreeID)
        #expect(prepared.panes[0].terminalState?.zmxSessionID.rawValue == storedText)
        #expect(prepared.paneGraph.replacement.paneStates[pane.id] != nil)
        #expect(prepared.tabs.map(\.id) == [tab.id])
        let activation = try #require(prepared.terminalActivationInput.entries.first)
        #expect(activation.paneID.uuid == pane.id)
        #expect(activation.visibilityPriority == .activeVisible)
        #expect(activation.hostPlacement == .tab(tabID: tab.id))
        guard case .zmx = activation.provider else {
            Issue.record("expected zmx activation backend")
            return
        }
        #expect(activation.zmxSessionID.rawValue == storedText)
        #expect(activation.launchConfiguration.launchDirectory == .stored(URL(filePath: "/tmp/composition")))
        #expect(activation.launchConfiguration.lifetime == .persistent)
    }

    @Test("duplicate composition identities reject off-main before apply")
    func duplicateCompositionIdentitiesRejectOffMainBeforeApply() async {
        // Arrange
        let pane = makeCompositionPane()
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            panes: [pane, pane]
        )

        // Act
        // This test deliberately crosses out of inherited MainActor isolation to prove rejection is prepared off-main.
        // swiftlint:disable:next no_task_detached
        let result = await Task.detached {
            WorkspaceCompositionPreparer.prepare(snapshot)
        }.value

        // Assert
        #expect(result == .rejected(.duplicatePaneID(pane.id)))
    }

    @Test("missing drawer membership rejects instead of pruning composition")
    func missingDrawerMembershipRejectsInsteadOfPruningComposition() throws {
        // Arrange
        let firstPane = makeCompositionPane()
        let secondPane = makeCompositionPane()
        let missingPaneID = UUIDv7.generate()
        var parentPane = firstPane
        parentPane.withDrawer { drawer in
            drawer.paneIds = [secondPane.id, missingPaneID]
            drawer.isExpanded = true
        }
        let tab = makeCompositionTab(
            paneID: parentPane.id,
            allPaneIDs: [parentPane.id, secondPane.id, missingPaneID]
        )
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Projection",
            panes: [parentPane, secondPane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 333
        )

        // Act
        let result = WorkspaceCompositionPreparer.prepare(snapshot)

        // Assert
        #expect(
            result
                == .rejected(
                    .drawerContainsMissingPane(
                        drawerID: try #require(parentPane.drawer?.drawerId),
                        paneID: missingPaneID
                    ))
        )
    }

    @Test("invalid active tab rejects instead of selecting fallback")
    func invalidActiveTabRejectsInsteadOfSelectingFallback() {
        // Arrange
        let pane = makeCompositionPane()
        let tab = makeCompositionTab(paneID: pane.id)
        let missingTabID = UUIDv7.generate()
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            panes: [pane],
            tabs: [tab],
            activeTabId: missingTabID
        )

        // Act
        let result = WorkspaceCompositionPreparer.prepare(snapshot)

        // Assert
        #expect(result == .rejected(.activeTabNotFound(missingTabID)))
    }

    @Test("inexact tab membership rejects instead of rebuilding membership")
    func inexactTabMembershipRejectsInsteadOfRebuildingMembership() {
        // Arrange
        let pane = makeCompositionPane()
        let unreferencedPane = makeCompositionPane()
        let tab = makeCompositionTab(
            paneID: pane.id,
            allPaneIDs: [pane.id, unreferencedPane.id]
        )
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            panes: [pane, unreferencedPane],
            tabs: [tab],
            activeTabId: tab.id
        )

        // Act
        let result = WorkspaceCompositionPreparer.prepare(snapshot)

        // Assert
        #expect(
            result
                == .rejected(
                    .tabPaneMissingFromArrangements(
                        tabID: tab.id,
                        paneID: unreferencedPane.id
                    ))
        )
    }

    @Test("accepted composition preserves pane and tab values exactly")
    func acceptedCompositionPreservesPaneAndTabValuesExactly() throws {
        // Arrange
        let pane = makeCompositionPane()
        var tab = makeCompositionTab(paneID: pane.id)
        tab.zoomedPaneId = pane.id
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Projection",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 333
        )

        // Act
        let prepared = try requirePreparedComposition(
            WorkspaceCompositionPreparer.prepare(snapshot)
        )

        // Assert
        #expect(prepared.panes == snapshot.panes)
        #expect(prepared.tabs == snapshot.tabs)
        #expect(prepared.activeTabID == snapshot.activeTabId)
        #expect(prepared.identity.workspaceID == snapshot.id)
        #expect(prepared.windowMemory.sidebarWidth == 333)
    }

    @Test("prepared content inputs exhaustively partition panes in stable priority order")
    func preparedContentInputsExhaustivelyPartitionPanesInStablePriorityOrder() throws {
        // Arrange
        let fixture = try makePreparedContentPartitionFixture()

        // Act
        let firstPreparation = try requirePreparedComposition(
            WorkspaceCompositionPreparer.prepare(fixture.snapshot)
        )
        let repeatedPreparation = try requirePreparedComposition(
            WorkspaceCompositionPreparer.prepare(fixture.snapshot)
        )

        // Assert
        let terminalEntries = firstPreparation.terminalActivationInput.entries
        let nonterminalEntries = firstPreparation.nonterminalContentMountInput.entries
        let terminalPaneIDs = terminalEntries.map(\.paneID.uuid)
        let nonterminalPaneIDs = nonterminalEntries.map(\.paneID.uuid)
        #expect(terminalPaneIDs == [fixture.activeTerminal.id, fixture.hiddenTerminal.id])
        #expect(
            nonterminalPaneIDs == [
                fixture.visibleWebview.id,
                fixture.hiddenBridge.id,
                fixture.hiddenCodeViewer.id,
                fixture.hiddenUnsupported.id,
            ]
        )
        #expect(Set(terminalPaneIDs).isDisjoint(with: Set(nonterminalPaneIDs)))
        #expect(Set(terminalPaneIDs + nonterminalPaneIDs) == Set(fixture.snapshot.panes.map(\.id)))
        #expect(terminalEntries.map(\.pane) == [fixture.activeTerminal, fixture.hiddenTerminal])
        #expect(firstPreparation.terminalActivationInput == repeatedPreparation.terminalActivationInput)
        #expect(firstPreparation.nonterminalContentMountInput == repeatedPreparation.nonterminalContentMountInput)

        let webviewEntry = try #require(nonterminalEntries.first)
        guard case .webview(let acceptedWebviewPane) = webviewEntry.content else {
            Issue.record("expected first nonterminal entry to preserve webview content")
            return
        }
        #expect(acceptedWebviewPane == fixture.visibleWebview)
        #expect(webviewEntry.visibilityPriority == .visible)
        #expect(webviewEntry.hostPlacement == .tab(tabID: fixture.activeTab.id))

        guard case .bridgePanel(let acceptedBridgePane) = nonterminalEntries[1].content else {
            Issue.record("expected bridge content")
            return
        }
        #expect(acceptedBridgePane == fixture.hiddenBridge)
        guard case .codeViewer(let acceptedCodeViewerPane) = nonterminalEntries[2].content else {
            Issue.record("expected code-viewer content")
            return
        }
        #expect(acceptedCodeViewerPane == fixture.hiddenCodeViewer)
        guard case .unsupported(let acceptedUnsupportedPane) = nonterminalEntries[3].content else {
            Issue.record("expected unsupported content")
            return
        }
        #expect(acceptedUnsupportedPane == fixture.hiddenUnsupported)
        #expect(nonterminalEntries.dropFirst().allSatisfy { $0.visibilityPriority == .hidden })
    }
}

private enum WorkspaceCompositionPreparerTestError: Error {
    case preparationRejected
}

private struct PreparedContentPartitionFixture {
    let snapshot: WorkspaceSQLiteSnapshot
    let activeTab: Tab
    let activeTerminal: Pane
    let hiddenTerminal: Pane
    let visibleWebview: Pane
    let hiddenCodeViewer: Pane
    let hiddenBridge: Pane
    let hiddenUnsupported: Pane
}

private func makePreparedContentPartitionFixture() throws -> PreparedContentPartitionFixture {
    let activeTerminal = makeCompositionPane(title: "Active terminal")
    let hiddenTerminal = makeCompositionPane(title: "Hidden terminal")
    let visibleWebview = makeCompositionPane(
        title: "Visible webview",
        content: .webview(
            WebviewState(
                url: try #require(URL(string: "https://example.com/prepared-content")),
                title: "Prepared webview",
                showNavigation: false
            )
        )
    )
    let hiddenCodeViewer = makeCompositionPane(
        title: "Hidden code viewer",
        content: .codeViewer(
            CodeViewerState(
                filePath: URL(filePath: "/tmp/prepared-content.swift"),
                scrollToLine: 42
            )
        )
    )
    let hiddenBridge = makeCompositionPane(
        title: "Hidden bridge",
        content: .bridgePanel(
            BridgePaneState(
                panelKind: .diffViewer,
                source: .commit(sha: "prepared-content")
            )
        )
    )
    let hiddenUnsupported = makeCompositionPane(
        title: "Hidden unsupported",
        content: .unsupported(
            UnsupportedContent(
                type: "future-prepared-content",
                version: 7,
                rawState: .object(["preserved": .bool(true)])
            )
        )
    )
    let activeTab = makeCompositionTab(
        paneIDs: [activeTerminal.id, visibleWebview.id],
        activePaneID: activeTerminal.id
    )
    let hiddenTab = makeCompositionTab(
        paneIDs: [hiddenTerminal.id, hiddenCodeViewer.id, hiddenBridge.id, hiddenUnsupported.id],
        activePaneID: hiddenTerminal.id
    )
    let panes = [
        hiddenBridge,
        hiddenTerminal,
        hiddenCodeViewer,
        activeTerminal,
        hiddenUnsupported,
        visibleWebview,
    ]
    return PreparedContentPartitionFixture(
        snapshot: WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Prepared content partition",
            panes: panes,
            tabs: [hiddenTab, activeTab],
            activeTabId: activeTab.id
        ),
        activeTab: activeTab,
        activeTerminal: activeTerminal,
        hiddenTerminal: hiddenTerminal,
        visibleWebview: visibleWebview,
        hiddenCodeViewer: hiddenCodeViewer,
        hiddenBridge: hiddenBridge,
        hiddenUnsupported: hiddenUnsupported
    )
}

private func requirePreparedComposition(
    _ result: WorkspaceCompositionPreparationResult
) throws -> PreparedWorkspaceComposition {
    guard case .prepared(let prepared) = result else {
        throw WorkspaceCompositionPreparerTestError.preparationRejected
    }
    return prepared
}

private func makeCompositionPane(
    id: UUID = UUIDv7.generate(),
    title: String = "Terminal",
    worktreeID: UUID? = nil,
    zmxSessionID: ZmxSessionID = .generateUUIDv7(),
    content: PaneContent? = nil
) -> Pane {
    let resolvedContent =
        content
        ?? .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: zmxSessionID
            ))
    return Pane(
        id: id,
        content: resolvedContent,
        metadata: PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/composition"),
            title: title,
            facets: PaneContextFacets(worktreeId: worktreeID)
        )
    )
}

private func makeCompositionTab(
    paneID: UUID,
    allPaneIDs: [UUID]? = nil
) -> Tab {
    let arrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneID),
        activePaneId: paneID
    )
    return Tab(
        id: UUIDv7.generate(),
        name: "Tab",
        allPaneIds: allPaneIDs ?? [paneID],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id
    )
}

private func makeCompositionTab(
    paneIDs: [UUID],
    activePaneID: UUID
) -> Tab {
    let arrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        layout: Layout.autoTiled(paneIDs),
        activePaneId: activePaneID
    )
    return Tab(
        id: UUIDv7.generate(),
        name: "Tab",
        allPaneIds: paneIDs,
        arrangements: [arrangement],
        activeArrangementId: arrangement.id
    )
}
