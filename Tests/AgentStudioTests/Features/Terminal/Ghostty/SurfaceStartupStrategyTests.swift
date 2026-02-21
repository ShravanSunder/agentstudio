import XCTest

@testable import AgentStudio

final class SurfaceStartupStrategyTests: XCTestCase {

    func test_surfaceCommandStrategy_setsStartupCommandAndNoDeferredCommand() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.surfaceCommand("/bin/zsh -i -l")

        // Assert
        XCTAssertEqual(strategy.startupCommandForSurface, "/bin/zsh -i -l")
        XCTAssertNil(strategy.deferredStartupCommand)
    }

    func test_deferredStrategy_setsDeferredCommandAndNoStartupCommand() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.deferredInShell(command: "zmx attach my-session")

        // Assert
        XCTAssertNil(strategy.startupCommandForSurface)
        XCTAssertEqual(strategy.deferredStartupCommand, "zmx attach my-session")
    }

    func test_surfaceConfiguration_capturesStartupStrategy() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.deferredInShell(command: "zmx attach abc")

        // Act
        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: "/tmp",
            startupStrategy: strategy
        )

        // Assert
        XCTAssertEqual(config.startupStrategy, strategy)
    }
}
