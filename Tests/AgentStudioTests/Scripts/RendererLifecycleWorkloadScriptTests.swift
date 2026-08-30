import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite("Renderer lifecycle workload verifier")
struct RendererLifecycleWorkloadScriptTests {
    @Test("continuity verifier is isolated, PID-bound, and conservation-gated")
    func continuityVerifierContractAndSyntax() async throws {
        let syntax = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: ["-n", scriptPath],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))
        #expect(source.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=renderer-lifecycle-continuity"))
        #expect(source.contains("AGENTSTUDIO_STARTUP_WATCH_FOLDER=\"$PROJECT_ROOT\""))
        #expect(source.contains("AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE=\"$phase\""))
        #expect(source.contains("AGENTSTUDIO_RENDERER_LIFECYCLE_RESTART_MANIFEST=\"$RESTART_MANIFEST\""))
        #expect(source.contains("mktemp -d /tmp/agentstudio-renderer-lifecycle.XXXXXX"))
        #expect(source.contains("AGENTSTUDIO_DEBUG_DATA_DIR=\"$DATA_ROOT\""))
        #expect(source.contains("decode_state AGENTSTUDIO_OBSERVABILITY_MARKER"))
        #expect(source.contains("APP_PID=\"$(decode_state AGENTSTUDIO_OBSERVABILITY_PID)\""))
        #expect(source.contains("process.pid=\"'\"$APP_PID\"'\""))
        #expect(source.contains("kill -0 \"$APP_PID\""))
        #expect(source.contains("kill \"$APP_PID\""))
        #expect(source.contains("required renderer lifecycle metric is missing"))
        #expect(source.contains("launch_phase initial"))
        #expect(source.contains("launch_phase restart"))
        #expect(source.contains("wait_for_diagnostic_completion initial 420"))
        #expect(source.contains("return value is True or (isinstance(value, str) and value.lower() == \"true\")"))
        #expect(source.contains("wait_for_exact_process_exit"))
        #expect(source.contains("initial) expected_created=41; expected_released=21; expected_freed=21"))
        #expect(source.contains("restart) expected_created=20; expected_released=0; expected_freed=0"))
        #expect(source.contains("active + hidden + close_undo != manager_owned"))
        #expect(source.contains("close_undo != 0 or orphan != 0 or valid != 1 or sequence <= 0"))
        for metric in [
            "agentstudio_performance_renderer_active_current",
            "agentstudio_performance_renderer_hidden_current",
            "agentstudio_performance_renderer_created_total",
            "agentstudio_performance_renderer_release_total",
            "agentstudio_performance_renderer_free_total",
            "agentstudio_performance_renderer_live_current",
            "agentstudio_performance_renderer_manager_owned_current",
            "agentstudio_performance_renderer_close_undo_current",
            "agentstudio_performance_renderer_orphan_candidate_current",
            "agentstudio_performance_renderer_lifecycle_valid",
            "agentstudio_performance_renderer_sample_sequence",
            "agentstudio_performance_renderer_visibility_delivery_total",
            "agentstudio_performance_renderer_visibility_equal_suppressed_total",
            "agentstudio_performance_renderer_projection_evaluation_total",
        ] {
            #expect(source.contains(metric))
        }
        #expect(!source.contains("pgrep"))
        #expect(!source.contains("pkill"))
        #expect(!source.contains("/Applications/AgentStudio.app"))
        #expect(!source.contains("$HOME/.agentstudio"))
        #expect(miseConfig.contains("[tasks.verify-renderer-lifecycle-continuity]"))
        #expect(miseConfig.contains("[tasks.verify-renderer-lifecycle-native-ui]"))
    }

    @Test("soak verifier is isolated, PID-bound, exact-count, and analyzer-gated")
    func soakVerifierContractAndSyntax() async throws {
        let syntax = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: ["-n", soakScriptPath],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )
        let source = try String(contentsOfFile: soakScriptPath, encoding: .utf8)
        let analyzer = try String(contentsOfFile: "scripts/analyze-renderer-lifecycle-soak.py", encoding: .utf8)
        let soakDriver = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+RendererLifecycleSoakDiagnostics.swift",
            encoding: .utf8
        )
        let transitionDriver = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+RendererLifecycleTransitionDiagnostics.swift",
            encoding: .utf8
        )
        let retentionDriver = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AppDelegate+RendererLifecycleRetentionDiagnostics.swift",
            encoding: .utf8
        )
        let actionSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/AgentStudioStartupDiagnosticAction.swift",
            encoding: .utf8
        )
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))
        #expect(source.contains("mktemp -d /tmp/agentstudio-renderer-soak.XXXXXX"))
        #expect(source.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=renderer-lifecycle-continuity"))
        #expect(source.contains("AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE=soak"))
        #expect(source.contains("AGENTSTUDIO_DEBUG_DATA_DIR=\"$DATA_ROOT\""))
        #expect(source.contains("APP_PID=\"$(decode_state AGENTSTUDIO_OBSERVABILITY_PID)\""))
        #expect(source.contains("WINDOWSERVER_PID=\"$(discover_windowserver_pid)\""))
        #expect(source.contains("kill \"$APP_PID\""))
        #expect(source.contains("sample_fixed_window warmup 60"))
        #expect(source.contains("sample_fixed_window final 180"))
        #expect(source.contains("--format bytes --wide"))
        #expect(source.contains("/usr/bin/vm_stat"))
        #expect(source.contains("/usr/sbin/sysctl vm.swapusage"))
        #expect(source.contains("parse_footprint \"$prefix-app-footprint.txt\" categories"))
        #expect(source.contains("WindowServer PID changed during renderer lifecycle soak"))
        #expect(source.contains("fetch_progress_record"))
        #expect(source.contains("progress record missing emitted completed/expected counts"))
        #expect(source.contains("read -r observed_completed observed_expected"))
        #expect(
            source.contains(
                "append_progress \"$stage\" \"$scenario\" \"$observed_completed\" \"$observed_expected\""
            ))
        #expect(!source.contains("append_progress \"$stage\" \"$scenario\" \"$completed\" \"$expected\""))
        #expect(source.contains("wait_for_progress equal_reconciliation_verified none 20 20"))
        #expect(source.contains("wait_for_progress changed_delivery_verified none 40 40"))
        for metric in [
            "agentstudio_performance_renderer_created_total",
            "agentstudio_performance_renderer_active_current",
            "agentstudio_performance_renderer_hidden_current",
            "agentstudio_performance_renderer_close_undo_current",
            "agentstudio_performance_renderer_release_total",
            "agentstudio_performance_renderer_free_total",
            "agentstudio_performance_renderer_live_current",
            "agentstudio_performance_renderer_manager_owned_current",
            "agentstudio_performance_renderer_orphan_candidate_current",
            "agentstudio_performance_renderer_visibility_delivery_total",
            "agentstudio_performance_renderer_visibility_equal_suppressed_total",
            "agentstudio_performance_renderer_projection_evaluation_total",
            "agentstudio_performance_renderer_projection_changed_surface_total",
            "agentstudio_performance_renderer_projection_equal_surface_total",
            "agentstudio_performance_renderer_lifecycle_valid",
            "agentstudio_performance_renderer_sample_sequence",
        ] {
            #expect(source.contains(metric))
        }
        #expect(!source.contains("pgrep"))
        #expect(!source.contains("pkill"))
        #expect(!source.contains("sudo"))
        #expect(!source.contains("/Applications/AgentStudio.app"))
        #expect(analyzer.contains("FINAL_SAMPLE_COUNT = 180"))
        #expect(analyzer.contains("T_CRITICAL_95_DF_178 = 1.973381"))
        #expect(analyzer.contains("free_memory_pressure_bytes"))
        #expect(analyzer.contains("result[\"lower_95\"] > 0"))
        #expect(soakDriver.contains("warmupDuration = Duration.seconds(610)"))
        #expect(soakDriver.contains("finalWindowDuration = Duration.seconds(1815)"))
        try assertTransitionDriverContract(transitionDriver)
        #expect(retentionDriver.contains("advanced(by: .seconds(299))"))
        #expect(retentionDriver.contains("postDeadlineTarget"))
        #expect(actionSource.components(separatedBy: "renderer-lifecycle-continuity").count == 2)
        #expect(miseConfig.contains("[tasks.verify-renderer-lifecycle-soak]"))
    }

    private func assertTransitionDriverContract(_ transitionDriver: String) throws {
        #expect(transitionDriver.contains("equal_reconciliation_verified"))
        #expect(transitionDriver.contains("changed_delivery_verified"))
        #expect(transitionDriver.contains("transitionCycleCount"))
        #expect(transitionDriver.contains("coverWindow.orderFrontRegardless()"))
        let transitionStart = try #require(
            transitionDriver.range(of: "private func exerciseRendererLifecycleSoakTransition(")
        )
        let repairStart = try #require(
            transitionDriver.range(
                of: "func exerciseRendererLifecycleRepairs(",
                range: transitionStart.upperBound..<transitionDriver.endIndex
            )
        )
        let transitionSection = String(transitionDriver[transitionStart.lowerBound..<repairStart.lowerBound])
        #expect(transitionSection.contains("waitForExactRendererLifecycleDelivery"))
        #expect(transitionDriver.contains("equalResult.applied == 0"))
        #expect(transitionDriver.contains("equalResult.equal == RendererLifecycleSoakSchedule.surfaceCount"))
        #expect(
            transitionDriver.contains(
                "visibilityDeliveryTotal - baseline.visibilityDeliveryTotal == expectedChangedCount"
            ))
        #expect(
            transitionDriver.contains(
                "projectionChangedSurfaceTotal - baseline.projectionChangedSurfaceTotal"
            ))
    }

    @Test("renderer verifier roots reject paths outside their dedicated tmp namespaces before writes")
    func rendererVerifierRootsFailClosed() async throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let invalidContinuityRoot = projectRoot.appending(path: ".renderer-continuity-\(UUIDv7.generate())")
        let invalidSoakRoot = projectRoot.appending(path: ".renderer-soak-\(UUIDv7.generate())")
        let continuitySymlink = URL(
            fileURLWithPath: "/tmp/agentstudio-renderer-lifecycle.\(UUIDv7.generate())"
        )
        let soakSymlink = URL(
            fileURLWithPath: "/tmp/agentstudio-renderer-soak.\(UUIDv7.generate())"
        )
        try FileManager.default.createSymbolicLink(at: continuitySymlink, withDestinationURL: invalidContinuityRoot)
        try FileManager.default.createSymbolicLink(at: soakSymlink, withDestinationURL: invalidSoakRoot)
        defer {
            try? FileManager.default.removeItem(at: continuitySymlink)
            try? FileManager.default.removeItem(at: soakSymlink)
        }
        let executor = DefaultProcessExecutor(timeout: 10)

        let continuity = try await executor.execute(
            command: "/bin/bash",
            args: [scriptPath],
            cwd: projectRoot,
            environment: ["AGENTSTUDIO_RENDERER_LIFECYCLE_PROOF_ROOT": invalidContinuityRoot.path]
        )
        let soak = try await executor.execute(
            command: "/bin/bash",
            args: [soakScriptPath],
            cwd: projectRoot,
            environment: ["AGENTSTUDIO_RENDERER_LIFECYCLE_SOAK_ROOT": invalidSoakRoot.path]
        )
        let continuitySymlinkEscape = try await executor.execute(
            command: "/bin/bash",
            args: [scriptPath],
            cwd: projectRoot,
            environment: ["AGENTSTUDIO_RENDERER_LIFECYCLE_PROOF_ROOT": continuitySymlink.path]
        )
        let soakSymlinkEscape = try await executor.execute(
            command: "/bin/bash",
            args: [soakScriptPath],
            cwd: projectRoot,
            environment: ["AGENTSTUDIO_RENDERER_LIFECYCLE_SOAK_ROOT": soakSymlink.path]
        )
        let continuitySource = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let soakSource = try String(contentsOfFile: soakScriptPath, encoding: .utf8)

        #expect(continuity.exitCode != 0)
        #expect(continuity.stderr.contains("dedicated /tmp namespace"))
        #expect(soak.exitCode != 0)
        #expect(soak.stderr.contains("dedicated /tmp namespace"))
        #expect(continuitySymlinkEscape.exitCode != 0)
        #expect(continuitySymlinkEscape.stderr.contains("dedicated /tmp namespace"))
        #expect(soakSymlinkEscape.exitCode != 0)
        #expect(soakSymlinkEscape.stderr.contains("dedicated /tmp namespace"))
        #expect(!FileManager.default.fileExists(atPath: invalidContinuityRoot.path))
        #expect(!FileManager.default.fileExists(atPath: invalidSoakRoot.path))
        #expect(continuitySource.contains("os.path.realpath"))
        #expect(soakSource.contains("os.path.realpath"))
    }

    private var scriptPath: String {
        "scripts/verify-renderer-lifecycle-continuity.sh"
    }

    private var soakScriptPath: String {
        "scripts/verify-renderer-lifecycle-soak.sh"
    }
}
