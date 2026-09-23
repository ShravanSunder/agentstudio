import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerZoomDrawerSideCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct ZoomDrawerFixture {
        let harness: Harness
        let sourcePane: Pane
        let drawerChild: Pane
        let tab: Tab
    }

    private func makeZoomDrawerFixture(entersZoom: Bool = true) throws -> ZoomDrawerFixture {
        let harness = makeHarness()
        let sourcePane = harness.store.createPane()
        let tab = Tab(paneId: sourcePane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerChild = try #require(harness.store.addDrawerPane(to: sourcePane.id))
        if entersZoom {
            harness.store.panePresentationAtom.enterZoom(
                inTab: tab.id,
                sourcePaneId: sourcePane.id,
                viewerPresentation: .unavailableVisible
            )
        }
        return ZoomDrawerFixture(harness: harness, sourcePane: sourcePane, drawerChild: drawerChild, tab: tab)
    }

    private func zoomSide(_ fixture: ZoomDrawerFixture) -> DrawerZoomSide {
        fixture.harness.store.paneAtom.drawerPresentationPreference(forOwner: fixture.sourcePane.id).zoomSide
    }

    @Test("side command from the terminal targets the Zoom source drawer")
    func sideCommandFromTerminalFocus() async throws {
        let fixture = try makeZoomDrawerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
        atom(\.workspaceFocusOwner).focusMainPane(fixture.sourcePane.id)

        #expect(fixture.harness.controller.canExecute(.moveZoomDrawerToBridge))
        await fixture.harness.executeCommand(.moveZoomDrawerToBridge)

        #expect(zoomSide(fixture) == .bridge)
        await fixture.harness.executeCommand(.moveZoomDrawerToTerminal)
        #expect(zoomSide(fixture) == .terminal)
    }

    @Test("side command with a drawer child focused still targets the Zoom source")
    func sideCommandFromDrawerChildFocus() async throws {
        let fixture = try makeZoomDrawerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
        atom(\.workspaceFocusOwner).focusDrawerPane(
            parentPaneId: fixture.sourcePane.id,
            paneId: fixture.drawerChild.id
        )

        await fixture.harness.executeCommand(.moveZoomDrawerToBridge)

        #expect(zoomSide(fixture) == .bridge)
        #expect(
            fixture.harness.store.paneAtom.drawerPresentationPreference(forOwner: fixture.drawerChild.id)
                == .default
        )
    }

    @Test("side commands are unavailable and inert outside Pane Zoom")
    func sideCommandRejectedOutsideZoom() async throws {
        let fixture = try makeZoomDrawerFixture(entersZoom: false)
        defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
        atom(\.workspaceFocusOwner).focusMainPane(fixture.sourcePane.id)

        #expect(!fixture.harness.controller.canExecute(.moveZoomDrawerToBridge))
        #expect(
            !fixture.harness.controller.canExecute(
                .moveZoomDrawerToBridge,
                target: fixture.sourcePane.id,
                targetType: .pane
            )
        )
        await fixture.harness.executeCommand(.moveZoomDrawerToBridge)
        await fixture.harness.executeCommand(
            .moveZoomDrawerToBridge,
            target: fixture.sourcePane.id,
            targetType: .pane
        )

        #expect(zoomSide(fixture) == .terminal)
        #expect(fixture.harness.store.paneAtom.drawerCursorAtom.presentationPreferenceRevision == 0)
    }

    @Test("targeted side command and a repeated side are an equal write")
    func targetedSideCommandEqualWrite() async throws {
        let fixture = try makeZoomDrawerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }

        #expect(
            fixture.harness.controller.canExecute(
                .moveZoomDrawerToBridge,
                target: fixture.sourcePane.id,
                targetType: .pane
            )
        )
        await fixture.harness.executeCommand(
            .moveZoomDrawerToBridge,
            target: fixture.sourcePane.id,
            targetType: .pane
        )
        let revisionAfterMove = fixture.harness.store.paneAtom.drawerCursorAtom.presentationPreferenceRevision
        await fixture.harness.executeCommand(
            .moveZoomDrawerToBridge,
            target: fixture.sourcePane.id,
            targetType: .pane
        )

        #expect(zoomSide(fixture) == .bridge)
        #expect(revisionAfterMove == 1)
        #expect(fixture.harness.store.paneAtom.drawerCursorAtom.presentationPreferenceRevision == revisionAfterMove)
    }

    @Test("headless IPC side command applies in Zoom and is refused outside it")
    func headlessSideCommand() async throws {
        let zoomed = try makeZoomDrawerFixture()
        defer { try? FileManager.default.removeItem(at: zoomed.harness.tempDir) }
        let appliedOutcome = await zoomed.harness.controller.executeHeadlessIPC(
            try drawerParentRequest(.moveZoomDrawerToBridge, parentPaneId: zoomed.sourcePane.id)
        )
        #expect(appliedOutcome == .applied)
        #expect(zoomSide(zoomed) == .bridge)

        let normal = try makeZoomDrawerFixture(entersZoom: false)
        defer { try? FileManager.default.removeItem(at: normal.harness.tempDir) }
        let refusedOutcome = await normal.harness.controller.executeHeadlessIPC(
            try drawerParentRequest(.moveZoomDrawerToBridge, parentPaneId: normal.sourcePane.id)
        )
        #expect(refusedOutcome != .applied)
        #expect(zoomSide(normal) == .terminal)
    }

    @Test("side commands classify for IPC exactly like their drawer siblings")
    func sideCommandIPCClassificationMatchesToggleDrawer() {
        let sibling = AppCommand.toggleDrawer.ipcSpec
        for command in [AppCommand.moveZoomDrawerToTerminal, .moveZoomDrawerToBridge] {
            let spec = command.ipcSpec
            #expect(spec.exposure == .debugTesting)
            #expect(spec.exposure == sibling.exposure)
            #expect(spec.executionMode == sibling.executionMode)
            #expect(spec.argumentVariants == [.drawerParent])
            #expect(spec.requiredPrivilege == sibling.requiredPrivilege)
            #expect(spec.allowedTargetKinds == [.window, .pane])
            #expect(spec.resultVariants == sibling.resultVariants)
        }
    }

    @Test("move control appears only in Pane Zoom with the management layer active")
    func moveControlPresence() {
        #expect(
            DrawerPanelOverlay.moveControlCommand(mode: .zoom(effectiveSide: .terminal), isManagementLayerActive: true)
                == .moveZoomDrawerToBridge
        )
        #expect(
            DrawerPanelOverlay.moveControlCommand(mode: .zoom(effectiveSide: .bridge), isManagementLayerActive: true)
                == .moveZoomDrawerToTerminal
        )
        #expect(
            DrawerPanelOverlay.moveControlCommand(mode: .zoom(effectiveSide: .terminal), isManagementLayerActive: false)
                == nil
        )
        #expect(DrawerPanelOverlay.moveControlCommand(mode: .normal, isManagementLayerActive: true) == nil)
    }

    private func drawerParentRequest(
        _ command: AppCommand,
        parentPaneId: UUID
    ) throws -> AppCommandExecutionRequest {
        AppCommandExecutionRequest(
            command: command,
            arguments: .typedIPC(
                .drawerParent(
                    .init(
                        workspaceWindowId: UUIDv7.generate(),
                        parentPaneSelector: try IPCPaneSelector(rawValue: parentPaneId.uuidString)
                    )
                )
            ),
            executionContext: .headlessIPC(admitsDebugTestingCommands: true)
        )
    }
}
