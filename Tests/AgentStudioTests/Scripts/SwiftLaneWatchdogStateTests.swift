import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Swift lane watchdog-state cleanup")
struct SwiftLaneWatchdogStateTests {
    @Test("watchdog-state failure reaps its child before publishing the timing sidecar")
    func watchdogStateFailureReapsBeforeSidecar() async throws {
        let evidenceDirectory = NSTemporaryDirectory() + "agentstudio-watchdog-state-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: evidenceDirectory) }
        let childPIDFile = evidenceDirectory + "/child.pid"
        let blockedFIFO = evidenceDirectory + "/blocked.fifo"
        let command = #"""
            mkdir -p '__EVIDENCE__'
            mkfifo '__FIFO__'
            LOG_PREFIX=watchdog-state
            LANE_EVENT_STREAM_DIR='__EVIDENCE__'
            source scripts/swift-test-helpers.sh
            swift_test_watchdog_state() { return 1; }
            status=0
            run_swift_with_timeout 'watchdog state probe' 60 /bin/bash -c \
              'echo "$$" > "$1"; read -r blocked < "$2"' \
              bash '__PID__' '__FIFO__' || status=$?
            echo STATUS=$status
            if read -r child_pid < '__PID__' && ! kill -0 "$child_pid" 2>/dev/null; then
              echo CHILD_REAPED
            else
              echo CHILD_SURVIVED
              kill -KILL "$child_pid" 2>/dev/null || true
              for job_pid in $(jobs -pr); do
                terminate_lane_child_tree KILL "$job_pid"
                wait "$job_pid" 2>/dev/null || true
              done
            fi
            """#
            .replacingOccurrences(of: "__EVIDENCE__", with: evidenceDirectory)
            .replacingOccurrences(of: "__PID__", with: childPIDFile)
            .replacingOccurrences(of: "__FIFO__", with: blockedFIFO)
        let result = try await runLaneScriptBash(command)
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("STATUS=1"))
        #expect(result.output.contains("CHILD_REAPED"))

        let files = try FileManager.default.contentsOfDirectory(atPath: evidenceDirectory)
        let sidecarName = try #require(files.first { $0.hasSuffix(".timing.json") })
        let sidecarURL = URL(fileURLWithPath: evidenceDirectory + "/" + sidecarName)
        let data = try Data(contentsOf: sidecarURL)
        let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wrapperComplete = try #require(record["wrapper_complete_ms"] as? Int)
        if let commandExit = record["command_exit_ms"] as? Int {
            #expect(wrapperComplete >= commandExit)
        } else {
            #expect(record["command_exit_ms"] is NSNull)
        }
    }
}
