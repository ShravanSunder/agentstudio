import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceBridgePaneActivityIntegrationTests {
    enum ActivityHidingMutation: CaseIterable, CustomTestStringConvertible {
        case applicationInactive
        case owningWindowHidden
        case owningWindowMiniaturized
        case owningWindowOccluded
        case inactiveTab
        case inactiveArrangement
        case minimized
        case zoomExcluded
        case backgroundedResidency

        var testDescription: String {
            switch self {
            case .applicationInactive:
                "application inactive"
            case .owningWindowHidden:
                "owning window hidden"
            case .owningWindowMiniaturized:
                "owning window miniaturized"
            case .owningWindowOccluded:
                "owning window occluded"
            case .inactiveTab:
                "inactive tab"
            case .inactiveArrangement:
                "inactive arrangement"
            case .minimized:
                "minimized pane"
            case .zoomExcluded:
                "zoom-excluded pane"
            case .backgroundedResidency:
                "backgrounded residency"
            }
        }
    }

    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("prepared initial mount leaves hidden Bridge panes dormant until steady-state selection")
    func preparedInitialMountLeavesHiddenBridgePaneDormantUntilSteadyStateSelection() async throws {
        // Arrange
        let harness = makeBridgePaneActivityTestHarness()
        let hiddenBridgePane = harness.store.createPane(
            content: .bridgePanel(
                BridgePaneState(
                    panelKind: .fileViewer,
                    source: .commit(sha: "hidden-restore")
                )
            ),
            metadata: PaneMetadata(title: "Hidden files")
        )
        let hiddenTab = Tab(paneId: hiddenBridgePane.id, name: "Hidden")
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(harness.tabId)
        enterForegroundNativeEnvironment(harness)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1200, height: 800)
        )
        harness.windowLifecycleStore.recordLaunchLayoutSettled()
        harness.coordinator.refreshBridgePaneActivities()
        let generation = WorkspaceContentMountGeneration()
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(entries: []),
            nonterminalContentMountInput: NonterminalContentMountInput(
                entries: [
                    NonterminalContentMountDescriptor(
                        content: .bridgePanel(harness.bridgePane),
                        visibilityPriority: .activeVisible,
                        hostPlacement: .tab(tabID: harness.tabId)
                    ),
                    NonterminalContentMountDescriptor(
                        content: .bridgePanel(hiddenBridgePane),
                        visibilityPriority: .hidden,
                        hostPlacement: .tab(tabID: hiddenTab.id)
                    ),
                ]
            )
        )
        harness.viewRegistry.beginInitialRestore()
        let mountCoordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: harness.viewRegistry,
            terminalAdmissionPort: PreparedTerminalMountAdmissionPort(
                generation: generation,
                initialFramesByPaneID: [:],
                viewRegistry: harness.viewRegistry,
                mountHandler: harness.coordinator
            ),
            nonterminalAdmissionPort: PreparedNonterminalMountAdmissionPort(
                generation: generation,
                coordinator: harness.coordinator
            )
        )

        // Act
        let settlement = await mountCoordinator.mount()

        // Assert
        #expect(harness.viewRegistry.allBridgeViews[harness.bridgePane.id] != nil)
        await expectBridgePaneActivity(
            .dormant,
            for: hiddenBridgePane.id,
            in: harness.coordinator,
            because: "startup must not construct a hidden Bridge host"
        )
        let hiddenAuthorityIdentity = harness.coordinator.bridgePaneActivityAuthorityIdentity(
            for: hiddenBridgePane.id
        )
        #expect(hiddenAuthorityIdentity != nil)
        #expect(harness.viewRegistry.allBridgeViews[hiddenBridgePane.id] == nil)
        #expect(harness.viewRegistry.registeredPaneIds == [harness.bridgePane.id])
        #expect(
            Set(settlement.nonterminal.outcomesByPaneID.keys)
                == [PaneId(existingUUID: harness.bridgePane.id)]
        )
        #expect(
            harness.viewRegistry.preparedContentMountState(
                for: PaneId(existingUUID: hiddenBridgePane.id),
                generation: generation
            ) == nil
        )

        // Act — selection reveals the pane through the established steady-state mount path.
        harness.store.setActiveTab(hiddenTab.id)
        let mountedHiddenBridgeView = try #require(
            harness.coordinator.createViewForContent(pane: hiddenBridgePane)
        )
        harness.coordinator.refreshBridgePaneActivities()

        // Assert
        await expectBridgePaneActivity(
            .foreground,
            for: hiddenBridgePane.id,
            in: harness.coordinator,
            because: "the hidden restored tab activated"
        )
        let registeredHiddenBridgeView = try #require(
            harness.viewRegistry.allBridgeViews[hiddenBridgePane.id]
        )
        #expect(mountedHiddenBridgeView === registeredHiddenBridgeView)
        #expect(harness.viewRegistry.registeredPaneIds == [harness.bridgePane.id, hiddenBridgePane.id])
        #expect(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: hiddenBridgePane.id)
                == hiddenAuthorityIdentity
        )
        await harness.finish()
    }

    @Test("installed Bridge pane is foreground only through exact app, window, and workspace facts")
    func installedBridgePaneBecomesForegroundFromExactNativeFacts() async throws {
        let harness = makeBridgePaneActivityTestHarness()

        try await installBridgeControllerAndEnterForeground(harness)

        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .foreground)
        #expect(harness.viewRegistry.allBridgeViews[harness.bridgePane.id] != nil)

        await harness.finish()
    }

    @Test(
        "each native hiding fact demotes an installed Bridge pane to loaded-hidden",
        arguments: ActivityHidingMutation.allCases
    )
    func eachNativeHidingFactDemotesToLoadedHidden(_ mutation: ActivityHidingMutation) async throws {
        let harness = makeBridgePaneActivityTestHarness()
        try await installBridgeControllerAndEnterForeground(harness)

        apply(mutation, to: harness)

        await expectBridgePaneActivity(
            .loadedHidden,
            for: harness.bridgePane.id,
            in: harness.coordinator,
            because: mutation.testDescription
        )
        #expect(harness.viewRegistry.view(for: harness.bridgePane.id) != nil)

        await harness.finish()
    }

    @Test("key, focus, and active viewer signals cannot mint foreground activity")
    func keyFocusAndViewerSignalsCannotMintForegroundActivity() async throws {
        let harness = makeBridgePaneActivityTestHarness()
        try await installBridgeControllerAndEnterForeground(harness)
        let foreignVisibleWindowId = UUID()
        harness.windowLifecycleStore.recordWindowRegistered(foreignVisibleWindowId)
        harness.windowLifecycleStore.recordWindowPresentation(
            WindowPresentationFacts(
                isVisible: true,
                isMiniaturized: false,
                isOccluded: false
            ),
            for: foreignVisibleWindowId
        )
        harness.windowLifecycleStore.recordWindowVisibility(false, for: harness.owningWindowId)
        await expectBridgePaneActivity(
            .loadedHidden,
            for: harness.bridgePane.id,
            in: harness.coordinator,
            because: "the exact owning window is hidden"
        )
        harness.windowLifecycleStore.recordWindowBecameKey(foreignVisibleWindowId)
        harness.windowLifecycleStore.recordWindowBecameFocused(foreignVisibleWindowId)
        let controller = try #require(harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller)

        controller.setActiveViewerModeAcceptedSignalForExplicitReviewRequestWithoutAdmissionCheck(
            streamId: "viewer-signal-must-not-mint-activity",
            generation: 1
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .loadedHidden)

        await harness.finish()
    }

    @Test("repair teardown preserves authority identity and never returns a loaded pane to dormant")
    func repairTeardownPreservesAuthorityIdentityAndLoadedState() async throws {
        let harness = makeBridgePaneActivityTestHarness()
        try await installBridgeControllerAndEnterForeground(harness)
        let originalAuthorityIdentity = try #require(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
        )
        let originalController = try #require(
            harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller
        )

        harness.coordinator.teardownView(
            for: harness.bridgePane.id,
            shouldUnregisterRuntime: false
        )

        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .loadedHidden)
        #expect(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
                == originalAuthorityIdentity
        )
        await harness.coordinator.drainBridgePaneRetirements()
        await expectBridgePaneActivity(
            .foreground,
            for: harness.bridgePane.id,
            in: harness.coordinator,
            because: "repair recreated the installed Bridge controller"
        )
        let replacementController = try #require(
            harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller
        )
        #expect(replacementController !== originalController)
        #expect(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
                == originalAuthorityIdentity
        )

        await harness.finish()
    }

    @Test("close publishes terminal activity before asynchronous Bridge retirement completes")
    func closePublishesTerminalActivitySynchronously() async throws {
        let harness = makeBridgePaneActivityTestHarness()
        try await installBridgeControllerAndEnterForeground(harness)
        let originalAuthorityIdentity = try #require(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
        )

        harness.coordinator.teardownView(
            for: harness.bridgePane.id,
            shouldUnregisterRuntime: true
        )

        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .closed)
        #expect(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
                == originalAuthorityIdentity
        )
        #expect(harness.coordinator.pendingBridgePaneRetirementCount == 1)
        #expect(harness.viewRegistry.view(for: harness.bridgePane.id) != nil)
        await harness.coordinator.drainBridgePaneRetirements()
        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .closed)

        await harness.finish()
    }

    @Test("close then undo installs fresh authority immune to stale retirement completion")
    func closeThenUndoInstallsFreshAuthority() async throws {
        let harness = makeBridgePaneActivityTestHarness()
        try await installBridgeControllerAndEnterForeground(harness)
        let originalAuthorityIdentity = try #require(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
        )
        let originalController = try #require(
            harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller
        )

        harness.coordinator.execute(.closeTab(tabId: harness.tabId))
        #expect(harness.coordinator.bridgePaneActivity(for: harness.bridgePane.id) == .closed)
        #expect(harness.coordinator.pendingBridgePaneRetirementCount == 1)

        harness.coordinator.undoCloseTab()

        let replacementAuthorityIdentity = try #require(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
        )
        #expect(replacementAuthorityIdentity != originalAuthorityIdentity)
        await harness.coordinator.drainBridgePaneRetirements()
        await expectBridgePaneActivity(
            .foreground,
            for: harness.bridgePane.id,
            in: harness.coordinator,
            because: "undo recreated the Bridge pane under its fresh authority"
        )
        let replacementController = try #require(
            harness.viewRegistry.allBridgeViews[harness.bridgePane.id]?.controller
        )
        #expect(replacementController !== originalController)
        #expect(
            harness.coordinator.bridgePaneActivityAuthorityIdentity(for: harness.bridgePane.id)
                == replacementAuthorityIdentity
        )

        await harness.finish()
    }

    private func apply(_ mutation: ActivityHidingMutation, to harness: BridgePaneActivityTestHarness) {
        switch mutation {
        case .applicationInactive:
            harness.appLifecycleStore.setActive(false)
        case .owningWindowHidden:
            harness.windowLifecycleStore.recordWindowVisibility(false, for: harness.owningWindowId)
        case .owningWindowMiniaturized:
            harness.windowLifecycleStore.recordWindowMiniaturization(true, for: harness.owningWindowId)
        case .owningWindowOccluded:
            harness.windowLifecycleStore.recordWindowOcclusion(true, for: harness.owningWindowId)
        case .inactiveTab:
            let backgroundPane = harness.store.createPane(
                content: .webview(
                    WebviewState(url: URL(string: "https://example.com/active-tab")!)
                ),
                metadata: PaneMetadata(title: "Active tab")
            )
            let activeTab = Tab(paneId: backgroundPane.id)
            harness.store.appendTab(activeTab)
            harness.store.setActiveTab(activeTab.id)
        case .inactiveArrangement:
            harness.store.tabLayoutAtom.switchArrangement(
                to: harness.alternateArrangementId,
                inTab: harness.tabId
            )
        case .minimized:
            #expect(
                harness.store.tabLayoutAtom.minimizePane(
                    harness.bridgePane.id,
                    inTab: harness.tabId
                )
            )
        case .zoomExcluded:
            harness.store.tabLayoutAtom.toggleZoom(
                paneId: harness.siblingPane.id,
                inTab: harness.tabId
            )
        case .backgroundedResidency:
            harness.store.paneAtom.setResidency(.backgrounded, for: harness.bridgePane.id)
        }
    }

}
