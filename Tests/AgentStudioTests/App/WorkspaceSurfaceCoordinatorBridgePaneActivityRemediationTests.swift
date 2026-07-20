import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceBridgePaneActivityRemediationTests {
    enum ShutdownAuthorityState: CaseIterable, CustomTestStringConvertible {
        case dormant
        case installed

        var testDescription: String {
            switch self {
            case .dormant:
                "dormant authority"
            case .installed:
                "installed authority"
            }
        }
    }

    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("last-pane closePane can undo before Bridge retirement yields")
    func lastPaneCloseThenImmediateUndoSurvivesDeferredBridgeRestore() async throws {
        // Arrange
        let harness = makeSinglePaneBridgeActivityTestHarness()
        try await installBridgeControllerAndEnterForeground(harness)
        let originalAuthorityIdentity = try #require(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
        )
        let originalController = try #require(
            harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller
        )

        // Act — intentionally do not yield between close and undo.
        harness.coordinator.execute(
            .closePane(tabId: harness.tabId, paneId: harness.bridgePane.id)
        )
        harness.coordinator.undoCloseTab()

        // Assert — the synchronous undo must retain the model under fresh authority.
        let replacementAuthorityIdentity = try #require(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
        )
        #expect(harness.store.pane(harness.bridgePane.id) != nil)
        #expect(harness.store.tab(harness.tabId) != nil)
        #expect(replacementAuthorityIdentity != originalAuthorityIdentity)

        // Act — let the retiring controller complete and the deferred replacement install.
        await harness.coordinator.drainBridgePaneRetirements()

        // Assert
        let replacementController = try #require(
            harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller
        )
        #expect(replacementController !== originalController)
        #expect(
            harness.coordinator.runtimeForPane(PaneId(existingUUID: harness.bridgePane.id))
                === replacementController.runtime
        )
        #expect(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
                == replacementAuthorityIdentity
        )
        replacementController.runtime.ingestBridgeEvent(
            .diff(.diffLoaded(stats: DiffStats(filesChanged: 1, insertions: 1, deletions: 0)))
        )
        let runtimeReplay = await replacementController.runtime.eventsSince(seq: 0)
        #expect(runtimeReplay.events.count == 1)
        #expect(runtimeReplay.nextSeq == 1)
        #expect(!runtimeReplay.gapDetected)

        await harness.finish()
    }

    @Test("expanded Bridge drawer follows the zoomed primary pane")
    func expandedBridgeDrawerFollowsZoomedPrimaryPane() async throws {
        // Arrange
        let harness = makeBridgePaneActivityTestHarness()
        enterForegroundNativeEnvironment(harness)
        let drawerBridgePane = try #require(
            harness.store.paneAtom.addDrawerPane(
                to: harness.siblingPane.id,
                content: .bridgePanel(
                    BridgePaneState(
                        panelKind: .diffViewer,
                        source: .commit(sha: "drawer-zoom")
                    )
                ),
                metadata: PaneMetadata(title: "Drawer review")
            )
        )
        let drawerId = try #require(
            harness.store.pane(harness.siblingPane.id)?.drawer?.drawerId
        )
        harness.store.tabArrangementAtom.addDrawerPaneView(
            drawerId: drawerId,
            parentPaneId: harness.siblingPane.id,
            drawerPaneId: drawerBridgePane.id,
            inTab: harness.tabId
        )
        _ = try #require(
            harness.coordinator.createViewForContent(pane: drawerBridgePane)
        )
        await expectBridgePaneActivity(
            .foreground,
            for: drawerBridgePane.id,
            in: harness.coordinator,
            because: "its expanded drawer and parent are visible"
        )
        #expect(harness.store.pane(harness.siblingPane.id)?.drawer?.isExpanded == true)

        // Act — zoom the drawer's owning primary pane.
        harness.store.tabLayoutAtom.toggleZoom(
            paneId: harness.siblingPane.id,
            inTab: harness.tabId
        )
        harness.coordinator.refreshBridgePaneActivities()

        // Assert — the child remains visible with its zoomed parent.
        await expectBridgePaneActivity(
            .foreground,
            for: drawerBridgePane.id,
            in: harness.coordinator,
            because: "its owning primary pane is zoomed"
        )

        // Act — zoom a different primary pane.
        harness.store.tabLayoutAtom.toggleZoom(
            paneId: harness.bridgePane.id,
            inTab: harness.tabId
        )
        harness.coordinator.refreshBridgePaneActivities()

        // Assert
        await expectBridgePaneActivity(
            .loadedHidden,
            for: drawerBridgePane.id,
            in: harness.coordinator,
            because: "a different primary pane is zoomed"
        )

        await harness.finish()
    }

    @Test(
        "shutdown terminally closes every Bridge activity authority",
        arguments: ShutdownAuthorityState.allCases
    )
    func shutdownClosesEveryBridgeActivityAuthority(
        _ authorityState: ShutdownAuthorityState
    ) async throws {
        // Arrange
        let harness = makeBridgePaneActivityTestHarness()
        if authorityState == .installed {
            try await installBridgeControllerAndEnterForeground(harness)
        }
        #expect(
            harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id)
                == (authorityState == .installed ? .foreground : .dormant)
        )

        // Act
        await harness.coordinator.shutdown()

        // Assert
        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .closed)
        try? FileManager.default.removeItem(at: harness.tempDirectory)
    }
}
