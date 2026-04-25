import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioTraceConfigurationTests {
    @Test
    func missingTagsDisablesTracing() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [:])

        #expect(!configuration.isEnabled)
        #expect(configuration.enabledTags.isEmpty)
    }

    @Test
    func offTagsDisableTracing() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "off"
        ])

        #expect(!configuration.isEnabled)
    }

    @Test
    func commaSeparatedTagsEnableSelectedTags() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "drag, runtime"
        ])

        #expect(configuration.isEnabled(.drag))
        #expect(configuration.isEnabled(.runtime))
        #expect(!configuration.isEnabled(.eventbus))
    }

    @Test
    func wildcardEnablesAllKnownTags() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "*"
        ])

        #expect(configuration.enabledTags == Set(AgentStudioTraceTag.allCases))
    }

    @Test
    func traceNameAndDirectoryAreSanitizedForFileOutput() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "drag",
            "AGENTSTUDIO_TRACE_NAME": "Drawer Target Smoke!",
            "AGENTSTUDIO_TRACE_DIR": "/tmp/agent studio traces",
        ])

        #expect(configuration.traceName == "Drawer-Target-Smoke")
        #expect(
            configuration.outputFileURL(processIdentifier: 42).path
                == "/tmp/agent studio traces/agentstudio-Drawer-Target-Smoke-42.jsonl")
    }
}
