import Foundation
import Testing

@testable import AgentStudio

@MainActor
struct ManagementModeTests {
    private func makeMonitor() -> ManagementModeMonitor {
        ManagementModeMonitor(startKeyboardMonitoring: false)
    }

    @Test("defaults to inactive")
    func test_managementMode_defaultsToInactive() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("toggles activate and deactivate")
    func test_managementMode_toggleActivatesAndDeactivates() async {
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
    func test_managementMode_deactivate() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.toggle()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("deactivate clears active state immediately")
    func test_managementMode_deactivate_clearsStateSynchronously() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.toggle()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("toggle updates active state immediately")
    func test_managementMode_toggle_updatesStateSynchronously() async {
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
    func test_managementMode_deactivateWhenAlreadyInactive() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            monitor.deactivate()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("management mode key policy passes through command shortcuts")
    func test_managementMode_keyPolicy_commandShortcutPassesThrough() async {
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

    @Test("management mode key policy consumes plain typing")
    func test_managementMode_keyPolicy_plainTypingConsumed() async {
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

    @Test("management mode key policy dispatches P to create terminal")
    func test_managementMode_keyPolicy_dispatchesCreateTerminal() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 35,
                modifierFlags: [],
                charactersIgnoringModifiers: "p"
            )
            #expect(decision == .dispatch(.managementCreateTerminal))
        }
    }

    @Test("management mode key policy dispatches B to create browser")
    func test_managementMode_keyPolicy_dispatchesCreateBrowser() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 11,
                modifierFlags: [],
                charactersIgnoringModifiers: "b"
            )
            #expect(decision == .dispatch(.managementCreateBrowser))
        }
    }

    @Test("management mode key policy dispatches D to open drawer")
    func test_managementMode_keyPolicy_dispatchesDrawerOpenShortcut() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 2,
                modifierFlags: [],
                charactersIgnoringModifiers: "d"
            )
            #expect(decision == .dispatch(.managementOpenDrawer))
        }
    }

    @Test("management mode key policy dispatches R to exit mode")
    func test_managementMode_keyPolicy_dispatchesExitModeShortcut() async {
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

    @Test("management mode key policy dispatches arrow keys")
    func test_managementMode_keyPolicy_dispatchesArrowKeys() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()

            #expect(
                monitor.keyDownDecision(
                    keyCode: 123,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementFocusLeft)
            )
            #expect(
                monitor.keyDownDecision(
                    keyCode: 124,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementFocusRight)
            )
            #expect(
                monitor.keyDownDecision(
                    keyCode: 125,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementEnterDrawer)
            )
            #expect(
                monitor.keyDownDecision(
                    keyCode: 126,
                    modifierFlags: [],
                    charactersIgnoringModifiers: nil
                ) == .dispatch(.managementExitDrawer)
            )
        }
    }

    @Test("management mode key policy ignores numeric pad modifier on arrow keys")
    func test_managementMode_keyPolicy_ignoresNumericPadModifierForArrowKeys() async {
        withTestAtomRegistry { _ in
            let monitor = makeMonitor()
            let decision = monitor.keyDownDecision(
                keyCode: 123,
                modifierFlags: [.numericPad],
                charactersIgnoringModifiers: nil
            )
            #expect(decision == .dispatch(.managementFocusLeft))
        }
    }

    @Test("management mode key policy consumes shifted arrow keys")
    func test_managementMode_keyPolicy_shiftedArrowConsumed() async {
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

    @Test("management mode key policy consumes control combinations")
    func test_managementMode_keyPolicy_controlCombinationConsumed() async {
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

    @Test("management mode key policy deactivates on escape")
    func test_managementMode_keyPolicy_escapeDeactivates() async {
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

    @Test("toggleManagementMode has expected command definition")
    func test_toggleManagementMode_commandDefinition() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .toggleManagementMode)
            #expect(definition.keyBinding?.key == "r")
            #expect(definition.keyBinding?.modifiers == [.command])
            #expect(definition.icon == "rectangle.split.2x2")
        }
    }

    @Test("managementExitMode uses active management icon")
    func test_managementExitMode_commandDefinition() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .managementExitMode)
            #expect(definition.icon == "rectangle.split.2x2.fill")
        }
    }

    @Test("closePane command requires management mode")
    func test_closePane_requiresManagementMode() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .closePane)
            #expect(definition.requiresManagementMode == true)
        }
    }

    @Test("closeTab does not require management mode")
    func test_closeTab_doesNotRequireManagementMode() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .closeTab)
            #expect(definition.requiresManagementMode == false)
        }
    }

    @Test("splitRight does not require management mode")
    func test_splitRight_doesNotRequireManagementMode() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .splitRight)
            #expect(definition.requiresManagementMode == false)
        }
    }

    @Test("addRepo does not require management mode")
    func test_addRepo_doesNotRequireManagementMode() async {
        withTestAtomRegistry { _ in
            let definition = CommandDispatcher.shared.definition(for: .addRepo)
            #expect(definition.requiresManagementMode == false)
        }
    }
}
