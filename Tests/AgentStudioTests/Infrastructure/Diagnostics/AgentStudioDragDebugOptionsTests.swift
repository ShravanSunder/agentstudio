import Testing

@testable import AgentStudio

@Suite
struct AgentStudioDragDebugOptionsTests {
    @Test
    func missingEnvironmentDisablesDragDestinations() {
        let options = AgentStudioDragDebugOptions.fromEnvironment([:])

        #expect(!options.showsDestinations)
    }

    @Test
    func truthyEnvironmentEnablesDragDestinations() {
        for value in ["1", "true", "yes", "on"] {
            let options = AgentStudioDragDebugOptions.fromEnvironment([
                "AGENTSTUDIO_DEBUG_DRAG_DESTINATIONS": value
            ])

            #expect(options.showsDestinations, "\(value) should enable drag destinations")
        }
    }
}
