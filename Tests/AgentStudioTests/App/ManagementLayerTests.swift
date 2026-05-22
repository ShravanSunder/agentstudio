import Foundation
import Testing

@testable import AgentStudio

@MainActor
struct ManagementLayerTests {
    private func makeMonitor() -> ManagementLayerMonitor {
        ManagementLayerMonitor(startKeyboardMonitoring: false)
    }

    @Test("defaults to inactive")
    func test_managementLayer_defaultsToInactive() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("toggles activate and deactivate")
    func test_managementLayer_toggleActivatesAndDeactivates() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            #expect(!monitor.isActive)
            monitor.toggle()
            #expect(monitor.isActive)
            monitor.toggle()
            #expect(!monitor.isActive)
        }
    }

    @Test("deactivate disables mode")
    func test_managementLayer_deactivate() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.toggle()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("deactivate clears active state immediately")
    func test_managementLayer_deactivate_clearsStateSynchronously() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.toggle()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("toggle updates active state immediately")
    func test_managementLayer_toggle_updatesStateSynchronously() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.toggle()
            #expect(monitor.isActive)
            monitor.toggle()
            #expect(!monitor.isActive)
        }
    }

    @Test("deactivate is no-op when already inactive")
    func test_managementLayer_deactivateWhenAlreadyInactive() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("management layer key policy passes through command shortcuts")
    func test_managementLayer_keyPolicy_commandShortcutPassesThrough() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 35,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "p"
            )
            #expect(decision == .passThrough)
        }
    }

    @Test("management layer passes option-ijkl through")
    func test_managementLayer_keyPolicy_optionIJKLPassThrough() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 34,
                modifierFlags: [.option],
                charactersIgnoringModifiers: "i"
            )
            #expect(decision == .passThrough)
        }
    }

    @Test("management layer key policy consumes plain typing")
    func test_managementLayer_keyPolicy_plainTypingConsumed() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 0,
                modifierFlags: [],
                charactersIgnoringModifiers: "a"
            )
            #expect(decision == .consume)
        }
    }

    @Test("management layer key policy dispatches P to create terminal")
    func test_managementLayer_keyPolicy_dispatchesCreateTerminal() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 35,
                modifierFlags: [],
                charactersIgnoringModifiers: "p"
            )
            #expect(decision == .dispatch(.managementLayerCreateTerminal))
        }
    }

    @Test("transient surface suppresses management layer plain command dispatch")
    func test_managementLayer_keyPolicy_transientSurfaceSuppressesPlainCommandDispatch() async {
        withTestAtomRegistry { atoms in
            let monitor = makeMonitor()
            let workspaceWindowId = UUID()
            atoms.windowLifecycle.recordWindowRegistered(workspaceWindowId)
            atoms.windowLifecycle.recordWindowBecameKey(workspaceWindowId)
            _ = atoms.transientKeyboardSurface.present(
                .tabRename(tabId: UUID()),
                workspaceWindowId: workspaceWindowId
            )

            let decision = monitor.keyDownDecision(
                keyCode: 35,
                modifierFlags: [],
                charactersIgnoringModifiers: "p"
            )

            #expect(decision == .passThrough)
        }
    }

    @Test("management layer key policy dispatches B to create browser")
    func test_managementLayer_keyPolicy_dispatchesCreateBrowser() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 11,
                modifierFlags: [],
                charactersIgnoringModifiers: "b"
            )
            #expect(decision == .dispatch(.managementLayerCreateBrowser))
        }
    }

    @Test("management layer key policy dispatches D to open drawer")
    func test_managementLayer_keyPolicy_dispatchesDrawerOpenShortcut() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 2,
                modifierFlags: [],
                charactersIgnoringModifiers: "d"
            )
            #expect(decision == .dispatch(.managementLayerOpenDrawer))
        }
    }

    @Test("management layer key policy dispatches R to exit mode")
    func test_managementLayer_keyPolicy_dispatchesExitModeShortcut() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 15,
                modifierFlags: [],
                charactersIgnoringModifiers: "r"
            )
            #expect(decision == .deactivateAndConsume)
        }
    }

    @Test("management layer key policy dispatches arrow keys")
    func test_managementLayer_keyPolicy_dispatchesArrowKeys() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()

            #expect(
                monitor.keyDownDecision(
                    keyCode: 123,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementLayerFocusLeft)
            )
            #expect(
                monitor.keyDownDecision(
                    keyCode: 124,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementLayerFocusRight)
            )
            #expect(
                monitor.keyDownDecision(
                    keyCode: 125,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementLayerOpenDrawer)
            )
            #expect(
                monitor.keyDownDecision(
                    keyCode: 126,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementLayerExitDrawer)
            )
        }
    }

    @Test("management layer key policy ignores numeric pad modifier on arrow keys")
    func test_managementLayer_keyPolicy_ignoresNumericPadModifierForArrowKeys() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 123,
                modifierFlags: [.numericPad],
                charactersIgnoringModifiers: nil
            )
            #expect(decision == .dispatch(.managementLayerFocusLeft))
        }
    }

    @Test("management layer key policy consumes shifted arrow keys")
    func test_managementLayer_keyPolicy_shiftedArrowConsumed() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 123,
                modifierFlags: [.shift],
                charactersIgnoringModifiers: nil
            )
            #expect(decision == .consume)
        }
    }

    @Test("management layer key policy consumes control combinations")
    func test_managementLayer_keyPolicy_controlCombinationConsumed() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 8,
                modifierFlags: [.control],
                charactersIgnoringModifiers: "c"
            )
            #expect(decision == .consume)
        }
    }

    @Test("management layer key policy deactivates on escape")
    func test_managementLayer_keyPolicy_escapeDeactivates() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 53,
                modifierFlags: [],
                charactersIgnoringModifiers: nil
            )
            #expect(decision == .deactivateAndConsume)
        }
    }

    @Test("toggleManagementLayer has expected command definition")
    func test_toggleManagementLayer_commandDefinition() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .toggleManagementLayer)
            #expect(definition.keyBinding?.key == "r")
            #expect(definition.keyBinding?.modifiers == [.command])
            #expect(definition.icon == .system(.rectangleSplit2x2))
        }
    }

    @Test("managementLayerExit uses active management icon")
    func test_managementLayerExit_commandDefinition() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .managementLayerExit)
            #expect(definition.icon == .system(.rectangleSplit2x2Fill))
        }
    }

    @Test("closePane command requires management layer")
    func test_closePane_requiresManagementLayer() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .closePane)
            #expect(definition.requiresManagementLayer == true)
        }
    }

    @Test("closeTab does not require management layer")
    func test_closeTab_doesNotRequireManagementLayer() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .closeTab)
            #expect(definition.requiresManagementLayer == false)
        }
    }

    @Test("splitRight does not require management layer")
    func test_splitRight_doesNotRequireManagementLayer() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .splitRight)
            #expect(definition.requiresManagementLayer == false)
        }
    }

    @Test("watchFolder does not require management layer")
    func test_watchFolder_doesNotRequireManagementLayer() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .watchFolder)
            #expect(definition.requiresManagementLayer == false)
        }
    }
}
