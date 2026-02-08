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
    func test_managementMode_requiredModifiers_isOptionCommand() {
        // Assert — Opt+Cmd (not Ctrl, because Ctrl+click = right-click on macOS)
        XCTAssertTrue(ManagementModeMonitor.requiredModifiers.contains(.option))
        XCTAssertTrue(ManagementModeMonitor.requiredModifiers.contains(.command))
        XCTAssertFalse(ManagementModeMonitor.requiredModifiers.contains(.control))
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
