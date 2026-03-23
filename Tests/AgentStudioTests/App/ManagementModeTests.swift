import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct ManagementModeTests {
    @Test("defaults to inactive")
    func test_managementMode_defaultsToInactive() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("toggles activate and deactivate")
    func test_managementMode_toggleActivatesAndDeactivates() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
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
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
            monitor.deactivate()
            monitor.toggle()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("deactivate clears active state immediately")
    func test_managementMode_deactivate_clearsStateSynchronously() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
            monitor.deactivate()
            monitor.toggle()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("toggle updates active state immediately")
    func test_managementMode_toggle_updatesStateSynchronously() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
            monitor.deactivate()
            monitor.toggle()
            #expect(monitor.isActive)
            monitor.toggle()
            #expect(!monitor.isActive)
        }
    }

    @Test("deactivate is no-op when already inactive")
    func test_managementMode_deactivateWhenAlreadyInactive() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
            monitor.deactivate()
            monitor.deactivate()
            #expect(!monitor.isActive)
        }
    }

    @Test("management mode key policy passes through command shortcuts")
    func test_managementMode_keyPolicy_commandShortcutPassesThrough() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
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
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
            let decision = monitor.keyDownDecision(
                keyCode: 0,
                modifierFlags: [],
                charactersIgnoringModifiers: "a"
            )
            #expect(decision == .consume)
        }
    }

    @Test("management mode key policy consumes control combinations")
    func test_managementMode_keyPolicy_controlCombinationConsumed() async {
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
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
        await withManagementModeTestLock {
            let monitor = ManagementModeMonitor.shared
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
        await withManagementModeTestLock {
            let definition = CommandDispatcher.shared.definition(for: .toggleManagementMode)
            #expect(definition != nil)
            #expect(definition?.keyBinding?.key == "e")
            #expect(definition?.keyBinding?.modifiers == [.command])
            #expect(definition?.icon == "rectangle.split.2x2")
        }
    }

    @Test("closePane command requires management mode")
    func test_closePane_requiresManagementMode() async {
        await withManagementModeTestLock {
            let definition = CommandDispatcher.shared.definition(for: .closePane)
            #expect(definition?.requiresManagementMode == true)
        }
    }

    @Test("closeTab does not require management mode")
    func test_closeTab_doesNotRequireManagementMode() async {
        await withManagementModeTestLock {
            let definition = CommandDispatcher.shared.definition(for: .closeTab)
            #expect(definition?.requiresManagementMode == false)
        }
    }

    @Test("splitRight does not require management mode")
    func test_splitRight_doesNotRequireManagementMode() async {
        await withManagementModeTestLock {
            let definition = CommandDispatcher.shared.definition(for: .splitRight)
            #expect(definition?.requiresManagementMode == false)
        }
    }

    @Test("addRepo does not require management mode")
    func test_addRepo_doesNotRequireManagementMode() async {
        await withManagementModeTestLock {
            let definition = CommandDispatcher.shared.definition(for: .addRepo)
            #expect(definition?.requiresManagementMode == false)
        }
    }
}
