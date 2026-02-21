import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct ManagementModeTests {

    // MARK: - ManagementModeMonitor

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
    @Test("toggleEditMode has expected command definition")
    func test_toggleEditMode_commandDefinition() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .toggleEditMode)

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
