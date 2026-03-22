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
    }

    @Test
    func test_surfaceConfiguration_capturesStartupStrategy() {
        // Arrange
        let strategy = Ghostty.SurfaceStartupStrategy.surfaceCommand("/usr/local/bin/zmx attach abc /bin/zsh -i -l")

        // Act
        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: "/tmp",
            startupStrategy: strategy
        )

        // Assert
        #expect(config.startupStrategy == strategy)
    }
}
