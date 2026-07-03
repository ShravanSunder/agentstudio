import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct GlobalPreferencesBootstrapTests {
    @Test
    func missingPreferencesFileReturnsMissing() throws {
        let rootURL = try makeTemporaryRoot()

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .missing)
    }

    @Test
    func validPreferencesFileReturnsObservabilityPreferences() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": true,
                    "traceTags": "app.startup,performance",
                    "traceBackend": "both",
                    "traceFlush": "immediate",
                    "otlpEndpoint": "http://127.0.0.1:4318"
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(
            result.status
                == .loaded(
                    GlobalObservabilityPreferences(
                        enabled: true,
                        traceTags: "app.startup,performance",
                        traceBackend: "both",
                        traceFlush: "immediate",
                        otlpEndpoint: "http://127.0.0.1:4318"
                    )))
    }

    @Test
    func disabledPreferencesFileReturnsLoadedDisabled() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": false,
                    "traceTags": "*",
                    "traceBackend": "otlp",
                    "traceFlush": "immediate",
                    "otlpEndpoint": null
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(
            result.status
                == .loaded(
                    GlobalObservabilityPreferences(
                        enabled: false,
                        traceTags: "*",
                        traceBackend: "otlp",
                        traceFlush: "immediate",
                        otlpEndpoint: nil
                    )))
    }

    @Test
    func malformedJSONReturnsInvalidMalformedJSON() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(rootURL: rootURL, json: "{ nope")

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidMalformedJSON)
    }

    @Test
    func unsupportedSchemaReturnsInvalidUnsupportedSchema() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 2,
                  "observability": { "enabled": true }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidUnsupportedSchema(schemaVersion: 2))
    }

    @Test
    func oversizedFileReturnsInvalidOversizedWithoutDecoding() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(rootURL: rootURL, json: String(repeating: " ", count: 33))

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false,
            maximumFileSizeBytes: 32
        )

        #expect(result.status == .invalidOversized(byteCount: 33, maximumBytes: 32))
    }

    @Test
    func remoteEndpointReturnsInvalidEndpoint() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": true,
                    "otlpEndpoint": "https://collector.example.com:4318"
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidEndpoint("https://collector.example.com:4318"))
    }

    @Test
    func invalidBackendReturnsInvalidField() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": true,
                    "traceBackend": "otlpp"
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidField("observability.traceBackend"))
        #expect(result.tracePreferenceLayer == nil)
    }

    @Test
    func invalidFlushReturnsInvalidField() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": true,
                    "traceFlush": "right-now"
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidField("observability.traceFlush"))
        #expect(result.tracePreferenceLayer == nil)
    }

    @Test
    func unknownTraceTagReturnsInvalidField() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": true,
                    "traceTags": "runtmie"
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidField("observability.traceTags"))
        #expect(result.tracePreferenceLayer == nil)
    }

    @Test
    func persistedOTLPProtocolReturnsInvalidField() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(
            rootURL: rootURL,
            json: """
                {
                  "schemaVersion": 1,
                  "observability": {
                    "enabled": true,
                    "traceTags": "*",
                    "otlpProtocol": "grpc"
                  }
                }
                """
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidField("observability.otlpProtocol"))
        #expect(result.tracePreferenceLayer == nil)
    }

    @Test
    func symlinkedPreferencesFileIsLoaded() throws {
        let rootURL = try makeTemporaryRoot()
        let targetURL = rootURL.appending(path: "target-preferences.json")
        try """
        {
          "schemaVersion": 1,
          "observability": { "enabled": true, "traceTags": "runtime" }
        }
        """.write(to: targetURL, atomically: true, encoding: .utf8)

        let preferencesURL = AppDataPaths.globalPreferencesURL(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )
        try FileManager.default.createSymbolicLink(
            atPath: preferencesURL.path,
            withDestinationPath: "target-preferences.json"
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(
            result.status
                == .loaded(
                    GlobalObservabilityPreferences(
                        enabled: true,
                        traceTags: "runtime",
                        traceBackend: nil,
                        traceFlush: nil,
                        otlpEndpoint: nil
                    )))
    }

    @Test
    func symlinkedOversizedTargetReturnsInvalidOversizedWithoutUnboundedRead() throws {
        let rootURL = try makeTemporaryRoot()
        let targetURL = rootURL.appending(path: "oversized-target-preferences.json")
        try String(repeating: " ", count: 200_002).write(to: targetURL, atomically: true, encoding: .utf8)

        let preferencesURL = AppDataPaths.globalPreferencesURL(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )
        try FileManager.default.createSymbolicLink(
            atPath: preferencesURL.path,
            withDestinationPath: "oversized-target-preferences.json"
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false,
            maximumFileSizeBytes: 32
        )

        #expect(result.status == .invalidOversized(byteCount: 33, maximumBytes: 32))
    }

    @Test
    func danglingSymlinkReturnsReadFailed() throws {
        let rootURL = try makeTemporaryRoot()
        let preferencesURL = AppDataPaths.globalPreferencesURL(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )
        try FileManager.default.createSymbolicLink(
            at: preferencesURL,
            withDestinationURL: rootURL.appending(path: "missing-target.json")
        )

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .readFailed)
    }

    @Test
    func invalidPreferencesAreAbsentAndEnvironmentOverridesStillApply() throws {
        let rootURL = try makeTemporaryRoot()
        try writePreferences(rootURL: rootURL, json: "{ nope")

        let result = GlobalPreferencesBootstrap.load(
            environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
            releaseChannel: .stable,
            isDebugBuild: false
        )
        let configuration = AgentStudioTraceConfiguration.from(
            environment: [
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
                "AGENTSTUDIO_TRACE_BACKEND": "otlp",
                "OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:4318",
            ],
            preferenceLayer: result.tracePreferenceLayer,
            releaseChannel: .stable,
            isDebugBuild: false
        )

        #expect(result.status == .invalidMalformedJSON)
        #expect(result.tracePreferenceLayer == nil)
        #expect(configuration.enabledTags == [.runtime])
        #expect(configuration.backend == .otlp)
        #expect(configuration.otlpEndpoint?.absoluteString == "http://127.0.0.1:4318")
    }

    private func makeTemporaryRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-global-preferences-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func writePreferences(rootURL: URL, json: String) throws {
        try json.write(
            to: AppDataPaths.globalPreferencesURL(
                environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
                releaseChannel: .stable,
                isDebugBuild: false
            ),
            atomically: true,
            encoding: .utf8
        )
    }
}
