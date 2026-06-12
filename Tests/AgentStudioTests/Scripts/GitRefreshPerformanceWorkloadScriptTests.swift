import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct GitRefreshPerformanceWorkloadScriptTests {
    @Test("workload proof script has stable safety contract and bash syntax")
    func workloadProofScriptHasStableSafetyContractAndBashSyntax() throws {
        let syntax = try runScript(arguments: ["-n", scriptPath])
        #expect(syntax.exitCode == 0)

        let source = try String(contentsOf: URL(fileURLWithPath: scriptPath), encoding: .utf8)
        #expect(source.contains("AGENTSTUDIO_DATA_DIR=\"$APP_DATA_DIR\""))
        #expect(source.contains("AGENTSTUDIO_PERF_TRACE_BACKEND    jsonl|both"))
        #expect(source.contains("Set >=255 when this script is used to cover"))
        #expect(source.contains("AGENTSTUDIO_PERF_TRACE_BACKEND=otlp is not accepted"))
        #expect(source.contains("AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR"))
        #expect(source.contains("DEFAULT_UI_PROOF_ROOT=\"/tmp/asperf\""))
        #expect(source.contains("validate_trace_name()"))
        #expect(source.contains("safe path component"))
        #expect(source.contains("elif [ \"$DRIVE_COMMAND_BAR\" = \"1\" ]; then"))
        #expect(source.contains("TRACE_NAME=\"$(validate_trace_name \"perf-$(date +%H%M%S)-$$\")\""))
        #expect(source.contains("log_command mise run build >/dev/null"))
        #expect(source.contains("$PROJECT_ROOT/.build-agent-*/*/debug/AgentStudio"))
        #expect(source.contains("AgentStudio build product not found under .build-agent-*"))
        #expect(source.contains("materialize_app_bundle_for_ui_smoke"))
        #expect(source.contains("temporary app bundle path already exists"))
        #expect(source.contains("reject_live_app_binary_override"))
        #expect(
            source.contains("AGENTSTUDIO_PERF_APP_BINARY must not target a live /Applications AgentStudio executable"))
        #expect(source.contains("/Applications/AgentStudio.app/Contents/MacOS/AgentStudio"))
        #expect(source.contains("/Applications/AgentStudio Beta.app/Contents/MacOS/AgentStudio"))
        #expect(source.contains("reject_live_app_bundle_override"))
        #expect(source.contains("/Applications/AgentStudio.app"))
        #expect(source.contains("proof_app_pid_candidates"))
        #expect(source.contains("ps -axo pid=,command="))
        #expect(source.contains("trace_pid_confirmed=true"))
        #expect(source.contains("/usr/bin/open -n \"$APP_LAUNCH_BUNDLE\""))
        #expect(source.contains("--env \"AGENTSTUDIO_DATA_DIR=$APP_DATA_DIR\""))
        #expect(source.contains("--env \"AGENTSTUDIO_RESTORE_TRACE=1\""))
        #expect(source.contains("--env \"AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=command-bar-repo-filter\""))
        #expect(
            source.contains("--env \"PATH=${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}\""))
        #expect(!source.contains("pgrep -f \"$app_binary\""))
        #expect(source.contains("capture_restore_trace"))
        #expect(source.contains("grep \"pid=$APP_PID \" \"$restore_trace_source\""))
        #expect(
            source.contains("did not observe performance.coordinator.write within startup timeout\" >&2\n  sample_app"))
        #expect(source.contains("startup diagnostic command-bar repo filter smoke for PID"))
        #expect(source.contains("driver=startup-diagnostic"))
        #expect(source.contains("action=command-bar-repo-filter"))
        #expect(source.contains("startup command-bar repo filter smoke"))
        #expect(source.contains("wait_for_command_bar_repo_filter_event"))
        #expect(source.contains("agentstudio.performance.commandbar.query_character.count\\\":[1-9][0-9]*"))
        #expect(source.contains("osascript") == false)
        #expect(source.contains("key code 35") == false)
        #expect(source.contains("cmd-P smoke") == false)
        #expect(source.contains("performance.commandbar.filter"))
        #expect(source.contains("git init \"$repo_dir\""))
        #expect(source.contains("git -C \"$repo_dir\" config user.email"))
        #expect(source.contains("commit.gpgsign false"))
        #expect(source.contains("tag.gpgsign false"))
        #expect(source.contains("stop_pid \"$APP_PID\""))
        #expect(source.contains("pkill") == false)
        #expect(source.contains("AGENTSTUDIO_PERF_ACTIVE_PANES"))
    }

    @Test("workload fixture JSON shape decodes as persisted workspace state")
    func workloadFixtureJSONShapeDecodesAsPersistedWorkspaceState() throws {
        let data = Data(workloadFixtureJSON.utf8)

        let state = try JSONDecoder().decode(WorkspacePersistor.PersistableState.self, from: data)

        #expect(state.repos.count == 1)
        #expect(state.worktrees.count == 1)
        #expect(state.panes.count == 1)
        #expect(state.tabs.count == 1)
        #expect(state.panes[0].worktreeId == state.worktrees[0].id)
    }

    private let scriptPath = "scripts/verify-git-refresh-performance-workload.sh"

    private func runScript(
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ScriptRunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private let workloadFixtureJSON = """
    {
      "schemaVersion": 1,
      "id": "00000000-0000-0000-0000-000000000101",
      "name": "Git Refresh Performance Fixture",
      "repos": [
        {
          "id": "00000000-0000-0000-0000-000000000201",
          "name": "repo-000",
          "repoPath": "file:///tmp/agentstudio-perf/repo-000",
          "createdAt": 0
        }
      ],
      "worktrees": [
        {
          "id": "00000000-0000-0000-0000-000000000301",
          "repoId": "00000000-0000-0000-0000-000000000201",
          "name": "main",
          "path": "file:///tmp/agentstudio-perf/repo-000",
          "isMainWorktree": true
        }
      ],
      "unavailableRepoIds": [],
      "panes": [
        {
          "id": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
          "content": {"version": 2, "type": "terminal", "state": {"provider": "zmx", "lifetime": "persistent"}},
          "metadata": {
            "paneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
            "contentType": {"terminal": {}},
            "source": {
              "worktree": {
                "worktreeId": "00000000-0000-0000-0000-000000000301",
                "repoId": "00000000-0000-0000-0000-000000000201",
                "launchDirectory": "file:///tmp/agentstudio-perf/repo-000"
              }
            },
            "executionBackend": {"local": {}},
            "createdAt": 0,
            "title": "repo-pane-0",
            "facets": {
              "repoId": "00000000-0000-0000-0000-000000000201",
              "worktreeId": "00000000-0000-0000-0000-000000000301",
              "cwd": "file:///tmp/agentstudio-perf/repo-000",
              "tags": []
            },
            "checkoutRef": null,
            "note": null
          },
          "residency": {"active": {}},
          "kind": {
            "layout": {
              "drawer": {
                "drawerId": "00000000-0000-0000-0000-000000000401",
                "parentPaneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
                "paneIds": [],
                "isExpanded": false
              }
            }
          }
        }
      ],
      "tabs": [
        {
          "id": "00000000-0000-0000-0000-000000000501",
          "name": "Performance",
          "panes": ["019eb9e5-2de8-7c5f-83b1-cc9782b2efb6"],
          "arrangements": [
            {
              "id": "00000000-0000-0000-0000-000000000601",
              "name": "Default",
              "isDefault": true,
              "layout": {
                "panes": [
                  {
                    "paneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
                    "ratio": 1.0
                  }
                ],
                "dividerIds": []
              },
              "minimizedPaneIds": [],
              "showsMinimizedPanes": true,
              "activePaneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
              "drawerViews": []
            }
          ],
          "activeArrangementId": "00000000-0000-0000-0000-000000000601"
        }
      ],
      "activeTabId": "00000000-0000-0000-0000-000000000501",
      "sidebarWidth": 250,
      "windowFrame": null,
      "watchedPaths": [],
      "createdAt": 0,
      "updatedAt": 0
    }
    """

private struct ScriptRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
