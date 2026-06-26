import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioTraceConfigurationPreferencesTests {
    @Test
    func stableAbsentPreferencesRemainDisabled() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [:],
            preferenceLayer: nil,
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(!configuration.isEnabled)
        #expect(configuration.backend == .jsonl)
        #expect(configuration.otlpEndpoint == nil)
    }

    @Test
    func enabledPreferencesCanEnableFullOTLPForStable() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [:],
            preferenceLayer: AgentStudioTracePreferenceLayer(
                enabled: true,
                traceTags: "*",
                traceBackend: "both",
                traceFlush: "immediate",
                otlpEndpoint: "http://127.0.0.1:4318"
            ),
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(configuration.enabledTags == Set(AgentStudioTraceTag.allCases))
        #expect(configuration.backend == .both)
        #expect(configuration.flushMode == .immediate)
        #expect(configuration.otlpEndpoint?.absoluteString == "http://127.0.0.1:4318")
    }

    @Test
    func disabledPreferencesDisableDebugAndBetaDefaults() {
        let preferenceLayer = AgentStudioTracePreferenceLayer(
            enabled: false,
            traceTags: "*",
            traceBackend: "both",
            traceFlush: "immediate",
            otlpEndpoint: "http://127.0.0.1:4318"
        )

        let debugConfiguration = AgentStudioTraceConfiguration.from(
            environment: [:],
            preferenceLayer: preferenceLayer,
            releaseChannel: .stable,
            isDebugBuild: true
        )
        let betaConfiguration = AgentStudioTraceConfiguration.from(
            environment: [:],
            preferenceLayer: preferenceLayer,
            releaseChannel: .beta,
            isDebugBuild: false
        )

        #expect(!debugConfiguration.isEnabled)
        #expect(!betaConfiguration.isEnabled)
        #expect(debugConfiguration.backend == .jsonl)
        #expect(betaConfiguration.backend == .jsonl)
        #expect(debugConfiguration.otlpEndpoint == nil)
        #expect(betaConfiguration.otlpEndpoint == nil)
    }

    @Test
    func environmentTagsOverridePreferenceTagsAndEnabledFlag() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [
                "AGENTSTUDIO_TRACE_TAGS": "runtime"
            ],
            preferenceLayer: AgentStudioTracePreferenceLayer(
                enabled: false,
                traceTags: "*",
                traceBackend: "both",
                traceFlush: "immediate",
                otlpEndpoint: "http://127.0.0.1:4318"
            ),
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(configuration.enabledTags == [.runtime])
        #expect(configuration.backend == .both)
        #expect(configuration.otlpEndpoint?.absoluteString == "http://127.0.0.1:4318")
    }

    @Test
    func environmentOffOverridesEnabledPreferences() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [
                "AGENTSTUDIO_TRACE_TAGS": "off"
            ],
            preferenceLayer: AgentStudioTracePreferenceLayer(
                enabled: true,
                traceTags: "*",
                traceBackend: "both",
                traceFlush: "immediate",
                otlpEndpoint: "http://127.0.0.1:4318"
            ),
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(!configuration.isEnabled)
        #expect(configuration.backend == .jsonl)
        #expect(configuration.otlpEndpoint == nil)
    }

    @Test
    func environmentSinkFieldsOverridePreferenceSinkFields() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_FLUSH": "buffered",
                "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4319",
                "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
            ],
            preferenceLayer: AgentStudioTracePreferenceLayer(
                enabled: true,
                traceTags: "runtime",
                traceBackend: "both",
                traceFlush: "immediate",
                otlpEndpoint: "http://127.0.0.1:4318"
            ),
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(configuration.enabledTags == [.runtime])
        #expect(configuration.backend == .jsonl)
        #expect(configuration.flushMode == .buffered)
        #expect(configuration.otlpEndpoint == nil)
        #expect(configuration.otlpProtocol == .httpProtobuf)
    }

    @Test
    func unsupportedProtocolEnvironmentBeatsPreferenceEndpointFailingOpenToJSONL() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [
                "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc"
            ],
            preferenceLayer: AgentStudioTracePreferenceLayer(
                enabled: true,
                traceTags: "runtime",
                traceBackend: "both",
                traceFlush: "immediate",
                otlpEndpoint: "http://127.0.0.1:4318"
            ),
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(configuration.enabledTags == [.runtime])
        #expect(configuration.backend == .jsonl)
        #expect(configuration.otlpEndpoint == nil)
        #expect(configuration.unsupportedOTLPProtocolSelector == "grpc")
    }

    @Test
    func rejectedPreferenceEndpointFallsBackToJSONL() {
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [:],
            preferenceLayer: AgentStudioTracePreferenceLayer(
                enabled: true,
                traceTags: "runtime",
                traceBackend: "both",
                traceFlush: nil,
                otlpEndpoint: "https://collector.example.com:4318"
            ),
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(configuration.enabledTags == [.runtime])
        #expect(configuration.backend == .jsonl)
        #expect(configuration.otlpEndpoint == nil)
        #expect(configuration.rejectedOTLPEndpointSelector == "https://collector.example.com:4318")
    }
}
