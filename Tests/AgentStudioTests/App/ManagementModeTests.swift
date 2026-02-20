import XCTest

@testable import AgentStudio

final class ManagementModeTests: XCTestCase {

    // MARK: - ManagementModeMonitor

    @MainActor
    func test_managementMode_defaultsToInactive() {
        // Assert
        let monitor = ManagementModeMonitor.shared
        XCTAssertFalse(monitor.isActive)
    }

    @MainActor
    func test_managementMode_toggleActivatesAndDeactivates() {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        XCTAssertFalse(monitor.isActive)

        // Act — toggle on
        monitor.toggle()
        XCTAssertTrue(monitor.isActive)

        // Act — toggle off
        monitor.toggle()
        XCTAssertFalse(monitor.isActive)
    }

    @MainActor
    func test_managementMode_deactivate() {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        monitor.toggle()  // activate

        // Act
        monitor.deactivate()

        // Assert
        XCTAssertFalse(monitor.isActive)
    }

    @MainActor
    func test_managementMode_deactivateWhenAlreadyInactive() {
        // Arrange
        let monitor = ManagementModeMonitor.shared
        monitor.deactivate()  // ensure inactive

        // Act — should be no-op
        monitor.deactivate()

        // Assert
        XCTAssertFalse(monitor.isActive)
    }

    @MainActor
    func test_toggleEditMode_commandDefinition() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .toggleEditMode)

        // Assert
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.keyBinding?.key, "e")
        XCTAssertEqual(def?.keyBinding?.modifiers, [.command])
        XCTAssertEqual(def?.icon, "rectangle.split.2x2")
    }

    // MARK: - CommandDefinition Management Mode Gating

    @MainActor
    func test_closePane_requiresManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closePane)

        // Assert
        XCTAssertTrue(def?.requiresManagementMode ?? false)
    }

    @MainActor
    func test_closeTab_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        XCTAssertFalse(def?.requiresManagementMode ?? true)
    }

    @MainActor
    func test_splitRight_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .splitRight)

        // Assert
        XCTAssertFalse(def?.requiresManagementMode ?? true)
    }

    @MainActor
    func test_addRepo_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .addRepo)

        // Assert
        XCTAssertFalse(def?.requiresManagementMode ?? true)
    }
}
