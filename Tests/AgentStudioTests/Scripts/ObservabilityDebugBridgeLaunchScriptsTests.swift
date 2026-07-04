import Foundation
import Testing

@Suite("Observability debug Bridge launch scripts")
struct ObservabilityDebugBridgeLaunchScriptsTests {
    @Test("debug launcher narrows default trace tags for Bridge observability smoke")
    func debugLauncherNarrowsDefaultTraceTagsForBridgeObservabilitySmoke() throws {
        let script = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("startup_diagnostic_action=\"${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-}\""))
        #expect(script.contains("if [ -n \"${AGENTSTUDIO_TRACE_TAGS:-}\" ]; then"))
        #expect(script.contains("trace_tags=\"$AGENTSTUDIO_TRACE_TAGS\""))
        #expect(
            script.contains(
                "elif [ \"$startup_diagnostic_action\" = \"bridge-review-observability-smoke\" ] ||"))
        #expect(
            script.contains(
                "[ \"$startup_diagnostic_action\" = \"bridge-file-view-observability-smoke\" ] ||"))
        #expect(
            script.contains(
                "[ \"$startup_diagnostic_action\" = \"bridge-file-view-command-route-observability-smoke\" ] ||"))
        #expect(
            script.contains(
                "[ \"$startup_diagnostic_action\" = \"bridge-file-view-targeted-route-observability-smoke\" ] ||"))
        #expect(
            script.contains(
                "[ \"$startup_diagnostic_action\" = \"bridge-review-to-file-view-observability-smoke\" ] ||"))
        #expect(
            script.contains(
                "[ \"$startup_diagnostic_action\" = \"bridge-worker-fetch-scheme-smoke\" ]; then"))
        #expect(script.contains("trace_tags=\"app.startup,bridge.performance.*\""))
        #expect(script.contains("--env \"AGENTSTUDIO_TRACE_TAGS=$trace_tags\""))
    }

    @Test("debug launcher allows bridge worker fetch scheme smoke trace tags")
    func debugLauncherAllowsBridgeWorkerFetchSchemeSmokeTraceTags() throws {
        let script = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("bridge-worker-fetch-scheme-smoke"))
        #expect(script.contains("trace_tags=\"app.startup,bridge.performance.*\""))
        #expect(script.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=$startup_diagnostic_action"))
    }
}
