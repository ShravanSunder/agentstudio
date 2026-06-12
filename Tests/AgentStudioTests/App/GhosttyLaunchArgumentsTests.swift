import Testing

@testable import AgentStudio

@Suite("Ghostty launch arguments")
struct GhosttyLaunchArgumentsTests {
    @Test("LaunchServices process serial number is removed")
    func launchServicesProcessSerialNumberIsRemoved() {
        let executablePath = "/Applications/AgentStudio Beta.app/Contents/MacOS/AgentStudio"

        let arguments = GhosttyLaunchArguments.sanitized([
            executablePath,
            "-psn_0_123456",
        ])

        #expect(arguments == [executablePath])
    }

    @Test("Only LaunchServices process serial number arguments are removed")
    func onlyLaunchServicesProcessSerialNumberArgumentsAreRemoved() {
        let arguments = GhosttyLaunchArguments.sanitized([
            "AgentStudio",
            "--trace",
            "-psn_0_123456",
            "+list-fonts",
        ])

        #expect(
            arguments == [
                "AgentStudio",
                "--trace",
                "+list-fonts",
            ])
    }
}
