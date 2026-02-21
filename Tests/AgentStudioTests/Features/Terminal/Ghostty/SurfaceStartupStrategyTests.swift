import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)

final class SurfaceStartupStrategyTests {

    @Test
    func test_surfaceCommandStrategy_setsStartupCommandAndNoDeferredCommand() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.surfaceCommand("/bin/zsh -i -l")

        // Assert
        #expect(strategy.startupCommandForSurface == "/bin/zsh -i -l")
        #expect(strategy.deferredStartupCommand == nil)
    }

    @Test
    func test_deferredStrategy_setsDeferredCommandAndNoStartupCommand() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.deferredInShell(command: "zmx attach my-session")

        // Assert
        #expect(strategy.startupCommandForSurface == nil)
        #expect(strategy.deferredStartupCommand == "zmx attach my-session")
    }

    @Test
    func test_surfaceConfiguration_capturesStartupStrategy() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.deferredInShell(command: "zmx attach abc")

        // Act
        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: "/tmp",
            startupStrategy: strategy
        )

        // Assert
        #expect(config.startupStrategy == strategy)
    }
}
