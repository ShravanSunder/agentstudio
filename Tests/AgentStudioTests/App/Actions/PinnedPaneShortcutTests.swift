import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Pinned pane shortcut ownership", .serialized)
struct PinnedPaneShortcutTests {
    @Test("pinned shortcuts focus panes across tabs in displayed activity order")
    func pinnedShortcutsFocusDisplayedOrder() async throws {
        await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator,
                startsObserving: false
            )
            let harness = makeHarness(store: store, windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let noActivity = harness.store.createPane(title: "No activity")
            let older = harness.store.createPane(title: "Older")
            let recent = harness.store.createPane(title: "Recent")
            let tabs = [noActivity, older, recent].map { pane in
                let tab = Tab(paneId: pane.id)
                harness.store.appendTab(tab)
                return tab
            }
            for pane in [noActivity, older, recent] {
                #expect(atoms.workspaceMutationCoordinator.setPanePinned(pane.id, isPinned: true))
            }
            let referenceInstant = ContinuousClock.now
            atoms.paneActivityTime.apply([
                .set(
                    older.id,
                    PaneActivityTime(
                        orderingInstant: referenceInstant.advanced(by: .seconds(-120)),
                        wallTime: Date(timeIntervalSince1970: 1), source: .terminal
                    )),
                .set(
                    recent.id,
                    PaneActivityTime(
                        orderingInstant: referenceInstant.advanced(by: .seconds(-10)),
                        wallTime: Date(timeIntervalSince1970: 2), source: .hook
                    )),
            ])
            harness.store.setActiveTab(tabs[0].id)
            harness.store.setActivePane(noActivity.id, inTab: tabs[0].id)

            await harness.executeCommand(.focusNextPinnedPane)
            #expect(harness.store.activeTabId == tabs[2].id)
            #expect(harness.store.tab(tabs[2].id)?.activePaneId == recent.id)

            await harness.executeCommand(.focusNextPinnedPane)
            #expect(harness.store.activeTabId == tabs[1].id)
            #expect(harness.store.tab(tabs[1].id)?.activePaneId == older.id)

            await harness.executeCommand(.focusPreviousPinnedPane)
            #expect(harness.store.activeTabId == tabs[2].id)
            #expect(harness.store.tab(tabs[2].id)?.activePaneId == recent.id)
        }
    }

    @Test("pinned arrows share terminal and global routes with stable workspace ownership")
    func pinnedArrowContextsAndOwnership() {
        for shortcut in [AppShortcut.focusPreviousPinnedPane, .focusNextPinnedPane] {
            let arrow: ShortcutArrowKey = shortcut == .focusPreviousPinnedPane ? .up : .down
            let trigger = ShortcutTrigger(key: .arrow(arrow), modifiers: [.option, .shift])
            #expect(ShortcutDecoder.shortcut(for: trigger, in: .global) == shortcut)
            #expect(ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned) == shortcut)
            #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .mainWindowChain))
            #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .managementLayer))
            #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .sidebar(.panes)))
            #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .otherWindow))
            #expect(shortcut.command.definition.shortcut == shortcut)
            #expect(!AppShortcutDispatchPolicy.isTerminalRuntimeCommand(shortcut.command))
        }
    }
}
