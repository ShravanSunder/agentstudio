import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct ManagementModeTests {
    // MARK: - ManagementModeMonitor

    private func waitForFlag(
        _ flag: LockedFlag,
        timeout: Duration = .milliseconds(300)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !flag.value, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return flag.value
    }

    @MainActor
    @Test("defaults to inactive")
    func test_managementMode_defaultsToInactive() {
        // Assert
        let monitor = ManagementModeMonitor.shared
        #expect(!monitor.isActive)
    }

    @MainActor
    @Test("toggles activate and deactivate")
    func test_managementMode_toggleActivatesAndDeactivates() {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        #expect(!monitor.isActive)

        // Act — toggle on
        monitor.toggle()
        #expect(monitor.isActive)

        // Act — toggle off
        monitor.toggle()
        #expect(!monitor.isActive)
    }

    @MainActor
    @Test("deactivate disables mode")
    func test_managementMode_deactivate() {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        monitor.toggle()  // activate

        // Act
        monitor.deactivate()

        // Assert
        #expect(!monitor.isActive)
    }

    @MainActor
    @Test("deactivate posts refocus event when active")
    func test_managementMode_deactivate_postsRefocusEvent() async {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        monitor.deactivate()
        monitor.toggle()
        defer { monitor.deactivate() }

        let didPostRefocus = LockedFlag()
        let captureTask = Task {
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                guard case .refocusTerminalRequested = event else { continue }
                didPostRefocus.set()
                break
            }
        }
        defer { captureTask.cancel() }
        try? await Task.sleep(for: .milliseconds(50))

        // Act
        monitor.deactivate()
        let didReceiveRefocus = await waitForFlag(didPostRefocus)

        // Assert
        #expect(didReceiveRefocus)
        #expect(!monitor.isActive)
    }

    @MainActor
    @Test("toggle posts management-mode changed active event")
    func test_managementMode_toggle_postsActiveChangedEvent() async {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        monitor.deactivate()
        defer { monitor.deactivate() }

        let didPostActive = LockedFlag()
        let captureTask = Task {
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                guard case .managementModeChanged(let isActive) = event, isActive else { continue }
                didPostActive.set()
                break
            }
        }
        defer { captureTask.cancel() }
        try? await Task.sleep(for: .milliseconds(50))

        // Act
        monitor.toggle()
        let didReceiveActive = await waitForFlag(didPostActive)

        // Assert
        #expect(didReceiveActive)
        #expect(monitor.isActive)
    }

    @MainActor
    @Test("deactivate is no-op when already inactive")
    func test_managementMode_deactivateWhenAlreadyInactive() {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        monitor.deactivate()  // ensure inactive

        // Act — should be no-op
        monitor.deactivate()

        // Assert
        #expect(!monitor.isActive)
    }

    @MainActor
    @Test("management mode key policy passes through command shortcuts")
    func test_managementMode_keyPolicy_commandShortcutPassesThrough() {
        // Arrange
        let monitor = ManagementModeMonitor.shared

        // Act
        let decision = monitor.keyDownDecision(
            keyCode: 35,  // P
            modifierFlags: [.command],
            charactersIgnoringModifiers: "p"
        )

        // Assert
        #expect(decision == .passThrough)
    }

    @MainActor
    @Test("management mode key policy consumes plain typing")
    func test_managementMode_keyPolicy_plainTypingConsumed() {
        // Arrange
        let monitor = ManagementModeMonitor.shared

        // Act
        let decision = monitor.keyDownDecision(
            keyCode: 0,  // A
            modifierFlags: [],
            charactersIgnoringModifiers: "a"
        )

        // Assert
        #expect(decision == .consume)
    }

    @MainActor
    @Test("management mode key policy consumes control combinations")
    func test_managementMode_keyPolicy_controlCombinationConsumed() {
        // Arrange
        let monitor = ManagementModeMonitor.shared

        // Act
        let decision = monitor.keyDownDecision(
            keyCode: 8,  // C
            modifierFlags: [.control],
            charactersIgnoringModifiers: "c"
        )

        // Assert
        #expect(decision == .consume)
    }

    @MainActor
    @Test("management mode key policy deactivates on escape")
    func test_managementMode_keyPolicy_escapeDeactivates() {
        // Arrange
        let monitor = ManagementModeMonitor.shared

        // Act
        let decision = monitor.keyDownDecision(
            keyCode: 53,  // Escape
            modifierFlags: [],
            charactersIgnoringModifiers: nil
        )

        // Assert
        #expect(decision == .deactivateAndConsume)
    }

    @MainActor
    @Test("toggleManagementMode has expected command definition")
    func test_toggleManagementMode_commandDefinition() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .toggleManagementMode)

        // Assert
        #expect(def != nil)
        #expect(def?.keyBinding?.key == "e")
        #expect(def?.keyBinding?.modifiers == [.command])
        #expect(def?.icon == "rectangle.split.2x2")
    }

    // MARK: - CommandDefinition Management Mode Gating

    @MainActor
    @Test("closePane command requires management mode")
    func test_closePane_requiresManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closePane)

        // Assert
        #expect(def?.requiresManagementMode == true)
    }

    @MainActor
    @Test("closeTab does not require management mode")
    func test_closeTab_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(def?.requiresManagementMode == false)
    }

    @MainActor
    @Test("splitRight does not require management mode")
    func test_splitRight_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .splitRight)

        // Assert
        #expect(def?.requiresManagementMode == false)
    }

    @MainActor
    @Test("addRepo does not require management mode")
    func test_addRepo_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .addRepo)

        // Assert
        #expect(def?.requiresManagementMode == false)
    }
}
