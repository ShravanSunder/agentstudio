import AppKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Pinned navigation ordered focus", .serialized)
struct PaneTabViewControllerPinnedNavigationTests {
    init() { installTestAtomRegistryIfNeeded() }

    @Test("rapid pinned presses resolve from the preceding successful destination and wrap")
    func successiveNavigationUsesCommittedOrigin() async throws {
        let harness = makePaneTabViewControllerCommandHarness()
        let alignedAtoms = CoreAtoms(
            workspaceIdentity: harness.store.identityAtom,
            workspaceWindowMemory: harness.store.windowMemoryAtom,
            workspaceRepositoryTopology: harness.store.repositoryTopologyAtom,
            workspacePane: harness.store.paneAtom,
            workspaceTabShell: harness.store.tabLayoutAtom.shellAtom,
            workspaceTabArrangement: harness.store.tabArrangementAtom,
            workspaceMutationCoordinator: harness.store.mutationCoordinator
        )
        try await withAsyncTestCoreAtoms(using: alignedAtoms) { atoms in
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let paneIDs = (0..<3).map { index in
                let pane = harness.store.createPane()
                harness.store.paneAtom.updatePaneTitle(pane.id, title: ["Alpha", "Bravo", "Charlie"][index])
                _ = atoms.workspaceMutationCoordinator.setPanePinned(pane.id, isPinned: true)
                harness.store.appendTab(Tab(paneId: pane.id))
                return pane.id
            }
            let firstTabID = try #require(harness.store.tabLayoutAtom.tabID(containingPane: paneIDs[0]))
            harness.store.setActiveTab(firstTabID)
            atoms.workspaceFocusOwner.focusMainPane(paneIDs[0])
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            for paneID in paneIDs { try attachPaneHost(paneId: paneID, in: harness, to: window) }

            // Fixed Panes organization sorts equal-activity titles descending:
            // Charlie, Bravo, Alpha. Starting at Alpha, next wraps to Charlie.
            let firstMove = harness.controller.submitPinnedPaneNavigation(previous: false)
            let secondMove = harness.controller.submitPinnedPaneNavigation(previous: false)
            #expect(await firstMove.value)
            #expect(await secondMove.value)
            #expect(atoms.workspaceFocusOwner.owner == .mainPane(paneId: paneIDs[1]))
            #expect(await harness.controller.submitPinnedPaneNavigation(previous: false).value)
            #expect(atoms.workspaceFocusOwner.owner == .mainPane(paneId: paneIDs[0]))
            #expect(await harness.controller.submitPinnedPaneNavigation(previous: true).value)
            #expect(atoms.workspaceFocusOwner.owner == .mainPane(paneId: paneIDs[1]))
        }
    }

    @Test("fresh validation rejects unpinned, backgrounded and removed targets")
    func freshTargetValidationRejectsInvalidatedCandidate() {
        let harness = makePaneTabViewControllerCommandHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        harness.store.appendTab(Tab(paneId: pane.id))
        #expect(harness.store.mutationCoordinator.setPanePinned(pane.id, isPinned: true))
        #expect(harness.controller.canApplyPinnedNavigationTarget(pane.id))
        #expect(harness.store.mutationCoordinator.setPanePinned(pane.id, isPinned: false))
        #expect(!harness.controller.canApplyPinnedNavigationTarget(pane.id))
        #expect(harness.store.mutationCoordinator.setPanePinned(pane.id, isPinned: true))
        #expect(harness.store.mutationCoordinator.backgroundPane(pane.id))
        #expect(!harness.controller.canApplyPinnedNavigationTarget(pane.id))
        harness.store.removePane(pane.id)
        #expect(!harness.controller.canApplyPinnedNavigationTarget(pane.id))
    }

    @Test("pinned global arrows preserve native editable responders")
    func nativeTextResponderKeepsItsArrow() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let harness = makePaneTabViewControllerCommandHarness(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let textView = NSTextView()
            let neutralView = FocusablePaneTabCommandMountedContentView()
            window.contentView?.addSubview(textView)
            window.contentView?.addSubview(neutralView)
            let handler = MockCommandHandler()
            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.option, .shift], characters: "\u{F700}",
                    charactersIgnoringModifiers: "\u{F700}", keyCode: 126,
                    windowNumber: window.windowNumber
                ))
            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(window.makeFirstResponder(textView))
                    #expect(!harness.controller.handleAppOwnedKeyEvent(event))
                    #expect(handler.executedCommands.isEmpty)
                    #expect(window.firstResponder === textView)
                    #expect(window.makeFirstResponder(neutralView))
                    #expect(harness.controller.handleAppOwnedKeyEvent(event))
                    #expect(handler.executedCommands.map { $0.0 } == [.focusPreviousPinnedPane])
                }
            )
        }
    }

    @Test("empty pinned set retains the current pane and arrangement")
    func emptyPinnedSetIsNoOp() async throws {
        let harness = makePaneTabViewControllerCommandHarness()
        let alignedAtoms = CoreAtoms(
            workspaceIdentity: harness.store.identityAtom,
            workspaceWindowMemory: harness.store.windowMemoryAtom,
            workspaceRepositoryTopology: harness.store.repositoryTopologyAtom,
            workspacePane: harness.store.paneAtom,
            workspaceTabShell: harness.store.tabLayoutAtom.shellAtom,
            workspaceTabArrangement: harness.store.tabArrangementAtom,
            workspaceMutationCoordinator: harness.store.mutationCoordinator
        )
        try await withAsyncTestCoreAtoms(using: alignedAtoms) { atoms in
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let pane = harness.store.createPane()
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            atoms.workspaceFocusOwner.focusMainPane(pane.id)
            let arrangementID = harness.store.tab(tab.id)?.activeArrangementId
            #expect(await harness.controller.submitPinnedPaneNavigation(previous: false).value == false)
            #expect(harness.store.activeTabId == tab.id)
            #expect(harness.store.tab(tab.id)?.activeArrangementId == arrangementID)
            #expect(atoms.workspaceFocusOwner.owner == .mainPane(paneId: pane.id))
        }
    }
}
