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
            "AGENTSTUDIO_TRACE_TAGS": "eventbus, runtime"
        ])

        #expect(configuration.isEnabled(.eventbus))
        #expect(configuration.isEnabled(.runtime))
        #expect(!configuration.isEnabled(.atoms))
    }

    @Test
    func notificationObservabilityConsumerTagsParseFromSmokeSelector() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS":
                "app.focus,runtime,eventbus,terminal.activity,inbox,ui.surface,ui.interaction,paneInbox"
        ])

        #expect(configuration.unknownTagSelectors.isEmpty)
        #expect(configuration.isEnabled(.appFocus))
        #expect(configuration.isEnabled(.runtime))
        #expect(configuration.isEnabled(.eventbus))
        #expect(configuration.isEnabled(.terminalActivity))
        #expect(configuration.isEnabled(.inbox))
        #expect(configuration.isEnabled(.uiSurface))
        #expect(configuration.isEnabled(.uiInteraction))
        #expect(configuration.isEnabled(.paneInbox))
    }

    @Test
    func wildcardEnablesAllKnownTags() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "*"
        ])

        #expect(configuration.enabledTags == Set(AgentStudioTraceTag.allCases))
    }

    @Test
    func tagSelectionTreatsNilEmptyAndOffAsDisabled() {
        #expect(AgentStudioTraceTag.parseSelection(nil).tags.isEmpty)
        #expect(AgentStudioTraceTag.parseSelection("").tags.isEmpty)
        #expect(AgentStudioTraceTag.parseSelection("  off  ").tags.isEmpty)
        #expect(AgentStudioTraceTag.parseSelection(nil).unknownSelectors.isEmpty)
        #expect(AgentStudioTraceTag.parseSelection("").unknownSelectors.isEmpty)
        #expect(AgentStudioTraceTag.parseSelection("  off  ").unknownSelectors.isEmpty)
    }

    @Test
    func tagSelectionSupportsPrefixWildcards() {
        let selection = AgentStudioTraceTag.parseSelection("terminal.*")

        #expect(selection.tags == [.terminalActivity, .terminalStartup])
        #expect(selection.unknownSelectors.isEmpty)
    }

    @Test
    func startupTraceTagsParseAsAppAndTerminalLanes() {
        let appSelection = AgentStudioTraceTag.parseSelection("app.*")
        let terminalSelection = AgentStudioTraceTag.parseSelection("terminal.*")

        #expect(appSelection.tags.contains(.appStartup))
        #expect(appSelection.tags.contains(.appFocus))
        #expect(terminalSelection.tags.contains(.terminalStartup))
        #expect(terminalSelection.tags.contains(.terminalActivity))
        #expect(!terminalSelection.tags.contains(.persistenceOperation))
        #expect(appSelection.unknownSelectors.isEmpty)
        #expect(terminalSelection.unknownSelectors.isEmpty)
    }

    @Test
    func startupTraceTagsParseFromExplicitSmokeSelector() {
        let selection = AgentStudioTraceTag.parseSelection("app.startup,terminal.startup,persistence.*")

        #expect(
            selection.tags == [
                .appStartup,
                .terminalStartup,
                .persistenceOperation,
                .persistenceRecovery,
                .persistenceSnapshot,
            ])
        #expect(selection.unknownSelectors.isEmpty)
    }

    @Test
    func persistenceTraceTagsParseAsOperationAndRecoverySiblings() {
        let exactSelection = AgentStudioTraceTag.parseSelection(
            "persistence.operation,persistence.recovery,persistence.snapshot"
        )
        let wildcardSelection = AgentStudioTraceTag.parseSelection("persistence.*")

        #expect(exactSelection.tags == [.persistenceOperation, .persistenceRecovery, .persistenceSnapshot])
        #expect(exactSelection.unknownSelectors.isEmpty)
        #expect(wildcardSelection.tags == [.persistenceOperation, .persistenceRecovery, .persistenceSnapshot])
        #expect(wildcardSelection.unknownSelectors.isEmpty)
    }

    @Test
    func tagSelectionKeepsMixedKnownAndUnknownSelectors() {
        let selection = AgentStudioTraceTag.parseSelection(" Runtime, paneInbox, missing.tag ")

        #expect(selection.tags == [.runtime, .paneInbox])
        #expect(selection.unknownSelectors == ["missing.tag"])
    }

    @Test
    func traceNameAndDirectoryAreSanitizedForFileOutput() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "runtime",
            "AGENTSTUDIO_TRACE_NAME": "Drawer Target Smoke!",
            "AGENTSTUDIO_TRACE_DIR": "/tmp/agent studio traces",
        ])

        #expect(configuration.traceName == "Drawer-Target-Smoke")
        #expect(
            configuration.outputFileURL(processIdentifier: 42).path
                == "/tmp/agent studio traces/agentstudio-Drawer-Target-Smoke-42.jsonl")
    }

    @Test
    func immediateFlushModeIsOptIn() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_FLUSH": "immediate",
            "AGENTSTUDIO_TRACE_TAGS": "runtime",
        ])

        #expect(configuration.flushMode == .immediate)
    }

    @Test
    func jsonlBackendIsDefaultAndOnlyActiveBackend() {
        let defaultConfiguration = AgentStudioTraceConfiguration.from(environment: [:])
        let explicitConfiguration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_BACKEND": "jsonl"
        ])
        let reservedConfiguration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_BACKEND": "otlp"
        ])

        #expect(defaultConfiguration.backend == .jsonl)
        #expect(defaultConfiguration.unsupportedBackendSelector == nil)
        #expect(explicitConfiguration.backend == .jsonl)
        #expect(explicitConfiguration.unsupportedBackendSelector == nil)
        #expect(reservedConfiguration.backend == .jsonl)
        #expect(reservedConfiguration.unsupportedBackendSelector == "otlp")
    }

    @Test
    func unknownTagSelectorsAreReportedWithoutEnablingTracing() {
        let configuration = AgentStudioTraceConfiguration.from(environment: [
            "AGENTSTUDIO_TRACE_TAGS": "runtmie"
        ])

        #expect(!configuration.isEnabled)
        #expect(configuration.unknownTagSelectors == ["runtmie"])
    }
}
