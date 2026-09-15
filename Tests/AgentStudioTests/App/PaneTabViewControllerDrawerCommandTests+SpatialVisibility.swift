import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

extension PaneTabViewControllerDrawerCommandTests {
    @Test(
        "option-j/l skips hidden drawer children and stops at the row edge",
        arguments: [false, true], [false, true]
    )
    func horizontalDrawerNavigationSkipsHiddenChildren(movingLeft: Bool, backgrounded: Bool) async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            configureMainWindowKeyboardOwner(windowLifecycleStore: harness.windowLifecycleStore)
            let (parent, drawerPanes) = try makeDrawerOrdinalPaneSet(in: harness, paneCount: 3)
            let tabID = try #require(harness.store.activeTabId)
            let arrangementID = try #require(harness.store.createArrangement(name: "Spatial", inTab: tabID))
            let origin = drawerPanes[movingLeft ? 2 : 0]
            let destination = drawerPanes[movingLeft ? 0 : 2]
            let hiddenPane = drawerPanes[1]
            if backgrounded {
                harness.store.paneAtom.setResidency(.backgrounded, for: hiddenPane.id)
            } else {
                #expect(harness.store.minimizeDrawerPane(hiddenPane.id, in: parent.id))
            }
            harness.store.setActiveDrawerPane(origin.id, in: parent.id)
            atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parent.id, paneId: origin.id)
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let originHost = try attachPaneHost(paneId: origin.id, in: harness, to: window)
            let destinationHost = try attachPaneHost(paneId: destination.id, in: harness, to: window)
            #expect(window.makeFirstResponder(originHost))
            let expandedBefore = harness.store.pane(parent.id)?.drawer?.isExpanded
            let minimizedBefore = harness.store.drawerView(forParent: parent.id)?.minimizedPaneIds
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil,
                    characters: movingLeft ? "j" : "l", charactersIgnoringModifiers: movingLeft ? "j" : "l",
                    isARepeat: false, keyCode: movingLeft ? 38 : 37
                )
            )

            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))

            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == destination.id)
            #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: destination.id))
            #expect(window.firstResponder === destinationHost)
            #expect(harness.store.tab(tabID)?.activePaneId == parent.id)
            #expect(harness.store.tab(tabID)?.activeArrangementId == arrangementID)
            #expect(harness.store.pane(parent.id)?.drawer?.isExpanded == expandedBefore)
            #expect(harness.store.drawerView(forParent: parent.id)?.minimizedPaneIds == minimizedBefore)
            #expect(harness.store.pane(hiddenPane.id)?.residency == (backgrounded ? .backgrounded : .active))

            // A reserved key at the edge is consumed without changing scope or focus.
            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))
            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == destination.id)
            #expect(window.firstResponder === destinationHost)
        }
    }
}
