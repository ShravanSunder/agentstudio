import Foundation
import Testing

@Suite("CI fast lane workflow")
struct CIFastLaneWorkflowTests {
    @Test("top-level test task owns every routine local test and pull-request gate")
    func topLevelTestTaskOwnsEveryRoutineLocalTestAndPullRequestGate() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let testTask = try miseTask(named: "test", in: miseConfig)

        #expect(testTask.contains("mise run lint"))
        #expect(testTask.contains("mise run test:architecture"))
        #expect(testTask.contains("mise run test:bridge-web"))
        #expect(testTask.contains("mise run bridge-web-build"))
        #expect(testTask.contains("test -f Sources/AgentStudio/Resources/BridgeWeb/app/index.html"))
        #expect(testTask.contains("SWIFT_TEST_TIMEOUT_SECONDS=\"${SWIFT_TEST_TIMEOUT_SECONDS:-300}\""))
        #expect(
            testTask.contains(
                "SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=\"${SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-900}\""
            )
        )
        #expect(testTask.contains("SWIFT_TEST_INCLUDE_E2E=1"))
        #expect(testTask.contains("mise run test:swift"))
        #expect(testTask.contains("git diff --check"))
    }

    @Test("macOS workflows select the supported Xcode before toolchain setup")
    func macOSWorkflowsSelectSupportedXcodeBeforeToolchainSetup() throws {
        let workflowPaths = [
            ".github/workflows/ci.yml",
            ".github/workflows/benchmarks.yml",
            ".github/workflows/release.yml",
        ]

        for workflowPath in workflowPaths {
            let workflow = try String(contentsOfFile: workflowPath, encoding: .utf8)
            let xcodeStep = try workflowStep(named: "Select Xcode 26.3", in: workflow)
            let xcodeStepRange = try #require(workflow.range(of: xcodeStep))
            let miseStepRange = try #require(workflow.range(of: "      - name: Setup mise"))

            #expect(xcodeStep.contains("uses: maxim-lobanov/setup-xcode@v1"))
            #expect(xcodeStep.contains("xcode-version: \"26.3\""))
            #expect(xcodeStepRange.lowerBound < miseStepRange.lowerBound)
        }
    }

    @Test("CI jobs use descriptive check names")
    func ciJobsUseDescriptiveCheckNames() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)

        #expect(workflow.contains("  code-quality:\n    name: Code quality"))
        #expect(workflow.contains("  bridge-web-validation:\n    name: BridgeWeb validation"))
        #expect(workflow.contains("  swift-test-suite:\n    name: Swift test suite"))
        #expect(!workflow.contains("  static:"))
        #expect(!workflow.contains("  test:"))
    }

    @Test("CI checkouts do not persist workflow credentials")
    func ciCheckoutsDoNotPersistWorkflowCredentials() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)

        for jobName in ["code-quality", "bridge-web-validation", "swift-test-suite"] {
            let job = try workflowJob(named: jobName, in: workflow)
            let checkoutStep = try workflowStep(named: "Checkout", in: job)

            #expect(checkoutStep.contains("persist-credentials: false"))
        }
    }

    @Test("Swift build cache is content addressed and skips exact-hit prebuilds")
    func swiftBuildCacheIsContentAddressedAndSkipsExactHitPrebuilds() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let restoreCacheStep = try workflowStep(named: "Restore Swift build cache", in: ciWorkflow)
        let saveCacheStep = try workflowStep(named: "Save Swift build cache", in: ciWorkflow)
        let prebuildStep = try workflowStep(named: "Prebuild Swift test bundles", in: ciWorkflow)

        #expect(restoreCacheStep.contains("path: .build-ci"))
        #expect(
            restoreCacheStep.contains(
                "key: swift-${{ runner.os }}-${{ runner.arch }}-xcode-26.3-debug-ghostty-${{ steps.submodules.outputs.ghostty_sha }}-zmx-${{ steps.submodules.outputs.zmx_sha }}-${{ hashFiles("
            )
        )
        #expect(restoreCacheStep.contains("'Package.swift'"))
        #expect(restoreCacheStep.contains("'Package.resolved'"))
        #expect(restoreCacheStep.contains("'Sources/**/*.swift'"))
        #expect(restoreCacheStep.contains("'Sources/**/Resources/**'"))
        #expect(restoreCacheStep.contains("'Tests/**/*.swift'"))
        #expect(restoreCacheStep.contains("'BridgeWeb/src/**'"))
        #expect(restoreCacheStep.contains("'BridgeWeb/scripts/**'"))
        #expect(restoreCacheStep.contains("'BridgeWeb/pnpm-lock.yaml'"))
        #expect(restoreCacheStep.contains("'BridgeWeb/pnpm-workspace.yaml'"))
        #expect(restoreCacheStep.contains("'BridgeWeb/tsconfig*.json'"))
        #expect(restoreCacheStep.contains("'BridgeWeb/components.json'"))
        #expect(restoreCacheStep.contains("'.mise.toml'"))
        #expect(
            !restoreCacheStep.contains(
                "github.sha"
            )
        )
        #expect(
            restoreCacheStep.contains(
                "swift-${{ runner.os }}-${{ runner.arch }}-xcode-26.3-debug-ghostty-${{ steps.submodules.outputs.ghostty_sha }}-zmx-${{ steps.submodules.outputs.zmx_sha }}-"
            )
        )
        #expect(restoreCacheStep.contains("actions/cache/restore@v4"))
        #expect(prebuildStep.contains("if: steps.swift-build-cache-restore.outputs.cache-hit != 'true'"))
        #expect(saveCacheStep.contains("path: .build-ci"))
        #expect(saveCacheStep.contains("if: steps.swift-build-cache-restore.outputs.cache-hit != 'true'"))
        #expect(saveCacheStep.contains("actions/cache/save@v4"))
        #expect(saveCacheStep.contains("steps.swift-build-cache-restore.outputs.cache-primary-key"))
    }

    @Test("benchmark workflow uses the canonical CI Swift build directory")
    func benchmarkWorkflowUsesCanonicalCISwiftBuildDirectory() throws {
        let benchmarkWorkflow = try String(
            contentsOfFile: ".github/workflows/benchmarks.yml",
            encoding: .utf8
        )
        let benchmarksJob = try workflowJob(named: "benchmarks", in: benchmarkWorkflow)
        let cacheStep = try workflowStep(
            named: "Cache Swift benchmark build",
            in: benchmarksJob
        )

        #expect(benchmarksJob.contains("SWIFT_BUILD_DIR: .build-ci"))
        #expect(cacheStep.contains("path: .build-ci"))
        #expect(
            cacheStep.contains(
                "key: benchmark-swift-build-ci-${{ runner.os }}-${{ hashFiles('Package.swift', 'Package.resolved') }}"
            )
        )
        #expect(cacheStep.contains("restore-keys: |\n            benchmark-swift-build-ci-${{ runner.os }}-"))
        #expect(!cacheStep.contains("swift-benchmark-"))
        #expect(!benchmarksJob.contains(".build-benchmark"))
    }

    @Test("benchmark lane executes a current Swift benchmark and rejects empty output")
    func benchmarkLaneExecutesCurrentSwiftBenchmark() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let benchmarkTask = try miseTask(named: "test:swift:benchmark", in: miseConfig)
        let benchmarkWorkflow = try String(
            contentsOfFile: ".github/workflows/benchmarks.yml",
            encoding: .utf8
        )
        let benchmarkStep = try workflowStep(named: "Swift benchmark tests", in: benchmarkWorkflow)

        #expect(benchmarkTask.contains("--filter \"GlobalPreferencesBootstrapPerformanceTests\""))
        #expect(benchmarkTask.contains("set -euo pipefail"))
        #expect(benchmarkTask.contains("export _XCB_BYPASS=1"))
        #expect(!benchmarkTask.contains("PushBenchmarkSupportTests"))
        #expect(!benchmarkTask.contains("PushPerformanceBenchmarkTests"))
        #expect(benchmarkStep.contains("grep -oE \"global-preferences-loader (missing|valid)"))
        #expect(benchmarkStep.contains("grep -c \"global-preferences-loader missing \""))
        #expect(benchmarkStep.contains("grep -c \"global-preferences-loader valid \""))
        #expect(!benchmarkStep.contains("No benchmark threshold lines emitted"))
    }

    @Test("fast lane keeps cached parallel default")
    func fastLaneKeepsCachedParallelDefault() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let benchmarkWorkflow = try String(
            contentsOfFile: ".github/workflows/benchmarks.yml",
            encoding: .utf8
        )
        let swiftTestTaskScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let testHelperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let fastLaneStep = try workflowStep(named: "Test fast lane", in: ciWorkflow)
        let webKitLaneStep = try workflowStep(named: "Test WebKit lane", in: ciWorkflow)
        let largeLaneStep = try workflowStep(
            named: "Test large non-WebKit lane",
            in: benchmarkWorkflow
        )
        let prebuildStep = try workflowStep(named: "Prebuild Swift test bundles", in: ciWorkflow)
        let fastLaneMode = try shellCase(named: "test-fast", in: swiftTestTaskScript)
        let largeLaneMode = try shellCase(named: "test-large", in: swiftTestTaskScript)
        let nonSerializedRunner = try shellFunction(named: "run_non_serialized_swift_tests", in: testHelperScript)
        let fastRunner = try shellFunction(named: "run_fast_non_webkit_swift_tests", in: testHelperScript)
        let largeRunner = try shellFunction(named: "run_large_non_webkit_swift_tests", in: testHelperScript)
        let largeSerialFilter = try shellFunction(
            named: "large_serial_non_webkit_filter_pattern",
            in: testHelperScript
        )

        #expect(ciWorkflow.contains("SWIFT_BUILD_DIR: .build-ci"))
        #expect(!ciWorkflow.contains("Test large non-WebKit lane"))
        #expect(benchmarkWorkflow.contains("push:\n    branches: [main]"))
        #expect(benchmarkWorkflow.contains("workflow_dispatch:"))
        #expect(ciWorkflow.contains("path: .build-ci"))
        #expect(prebuildStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(prebuildStep.contains("SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS: \"900\""))
        #expect(prebuildStep.contains("run: mise run --skip-deps test:swift:prebuild"))
        #expect(!fastLaneStep.contains("SWIFT_TEST_WORKERS"))
        #expect(fastLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(fastLaneStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"300\""))
        #expect(fastLaneStep.contains("SWIFT_TEST_NUM_WORKERS: \"4\""))
        #expect(fastLaneStep.contains("_XCB_BYPASS: \"1\""))
        #expect(!fastLaneStep.contains("XCB_EXTRA_ARGS"))
        #expect(fastLaneStep.contains("run: mise run --raw test:swift:fast"))
        #expect(webKitLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(webKitLaneStep.contains("run: mise run test:swift:webkit"))
        #expect(!largeLaneStep.contains("SWIFT_TEST_WORKERS"))
        #expect(!largeLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD"))
        #expect(largeLaneStep.contains("SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS: \"900\""))
        #expect(largeLaneStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(largeLaneStep.contains("_XCB_BYPASS: \"1\""))
        #expect(largeLaneStep.contains("run: mise run test:swift:large"))
        #expect(swiftTestTaskScript.contains("test|test-fast|test-large|test-prebuild|test-webkit)"))
        #expect(swiftTestTaskScript.contains("if [ \"$mode\" = \"test-prebuild\" ]; then\n  prebuild_swift_tests"))
        #expect(swiftTestTaskScript.contains("AGENTSTUDIO_TRACE_BACKEND=\"${SWIFT_TEST_TRACE_BACKEND:-jsonl}\""))
        #expect(testHelperScript.contains("AGENTSTUDIO_TRACE_BACKEND=\"${SWIFT_TEST_TRACE_BACKEND:-jsonl}\""))
        #expect(testHelperScript.contains("print_timeout_process_diagnostics \"$label\" \"$command_pid\""))
        #expect(testHelperScript.contains("process tree for timed out"))
        #expect(testHelperScript.contains("sampled stuck Swift test process"))
        #expect(testHelperScript.contains("large_non_webkit_filter_pattern()"))
        #expect(testHelperScript.contains("SourceScan"))
        #expect(testHelperScript.contains("large_serial_non_webkit_filter_pattern()"))
        #expect(testHelperScript.contains("AgentStudioIPCBridgeServiceTests"))
        #expect(testHelperScript.contains("AgentStudioAppIPCServiceCommandTests"))
        #expect(testHelperScript.contains("AgentStudioAppIPCServiceContributionTests"))
        #expect(testHelperScript.contains("PaneAgentLaunchOwnerTests"))
        #expect(fastLaneMode.contains("run_fast_non_webkit_swift_tests"))
        #expect(largeLaneMode.contains("run_large_non_webkit_swift_tests"))
        #expect(nonSerializedRunner.contains("--parallel"))
        #expect(!nonSerializedRunner.contains("--num-workers"))
        #expect(nonSerializedRunner.contains("--skip WebKitSerializedTests"))
        #expect(nonSerializedRunner.contains("--skip E2ESerializedTests"))
        #expect(nonSerializedRunner.contains("--skip ZmxE2ETests"))
        #expect(fastRunner.contains("--parallel"))
        #expect(fastRunner.contains("--num-workers \"$SWIFT_TEST_NUM_WORKERS\""))
        #expect(
            fastRunner.contains(
                "--skip \"Benchmark|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)\""
            )
        )
        #expect(!testHelperScript.contains("app_ipc_live_socket_suite_filters"))
        #expect(!fastRunner.contains("serial App IPC service live socket suites"))
        #expect(!fastRunner.contains("app_ipc_live_socket_suite_filter"))
        #expect(largeRunner.contains("--parallel"))
        #expect(!largeRunner.contains("--num-workers"))
        #expect(largeRunner.contains("--filter \"$(large_non_webkit_filter_pattern)\""))
        #expect(largeRunner.contains("serial large process suites"))
        #expect(largeRunner.contains("--filter \"$(large_serial_non_webkit_filter_pattern)\""))
        #expect(!largeSerialFilter.contains("AgentStudioAppIPCServiceCommandTests"))
        #expect(largeRunner.contains("--skip WebKitSerializedTests"))
        #expect(largeRunner.contains("--skip E2ESerializedTests"))
        #expect(largeRunner.contains("--skip ZmxE2ETests"))
        #expect(!ciWorkflow.contains("SWIFT_BUILD_DIR: .build-ci-fast"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_SHARD_BY_CLASS"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_SHARD_CLASS_COUNT"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_PARALLEL: \"0\""))
        #expect(!ciWorkflow.contains("SWIFT_TEST_WORKERS"))
        #expect(!testHelperScript.contains("SWIFT_TEST_WORKERS"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_RUNNER_WARMUP_TIMEOUT_SECONDS"))
        #expect(!swiftTestTaskScript.contains("run_swift_class_shards"))
        #expect(!testHelperScript.contains("run_swift_class_shards"))
        #expect(!testHelperScript.contains("standalone_swift_test_filters"))
        #expect(!testHelperScript.contains("isolated_swift_test_class_filters"))
        #expect(!testHelperScript.contains("swift test list ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build"))
    }

    @Test("real zmx lifecycle proof stays in its dedicated E2E lane")
    func realZmxLifecycleProofStaysInDedicatedE2ELane() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let swiftTestTaskScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let defaultTestCase = try shellCase(named: "test", in: swiftTestTaskScript)
        let forwardedArgumentsBlock = try namedBlock(
            startingWith: "if [ \"$#\" -gt 0 ]; then",
            endingBefore: "\nfi\n",
            in: swiftTestTaskScript
        )
        let coverageTask = try miseTask(named: "test:swift:coverage", in: miseConfig)
        let generalE2ETask = try miseTask(named: "test:swift:e2e", in: miseConfig)
        let zmxE2ETask = try miseTask(named: "test:swift:zmx-e2e", in: miseConfig)

        #expect(
            forwardedArgumentsBlock.contains(
                "requested_filter_mentions_suite ZmxE2ETests \"$@\""
            )
        )
        #expect(forwardedArgumentsBlock.contains("requested_filter_mentions_suite WebKitSerializedTests \"$@\""))
        #expect(forwardedArgumentsBlock.contains("requested_filter_mentions_suite E2ESerializedTests \"$@\""))
        #expect(
            forwardedArgumentsBlock.contains(
                "if ! requested_filter_mentions_suite WebKitSerializedTests \"$@\"; then\n"
                    + "    swift_test_args+=(--skip WebKitSerializedTests)"
            )
        )
        #expect(
            forwardedArgumentsBlock.contains(
                "if ! requested_filter_mentions_suite E2ESerializedTests \"$@\" &&\n"
                    + "    ! requested_filter_mentions_suite ZmxE2ETests \"$@\""
            )
        )
        #expect(
            forwardedArgumentsBlock.contains(
                "if ! requested_filter_mentions_suite ZmxE2ETests \"$@\"; then\n"
                    + "    swift_test_args+=(--skip ZmxE2ETests)"
            )
        )
        #expect(forwardedArgumentsBlock.contains("swift test --skip-build \"${swift_test_args[@]}\""))
        #expect(!forwardedArgumentsBlock.contains("swift test --skip-build \"$@\" --skip ZmxE2ETests"))
        #expect(defaultTestCase.contains("--filter E2ESerializedTests --skip ZmxE2ETests"))
        #expect(!defaultTestCase.contains("SWIFT_TEST_INCLUDE_ZMX_E2E"))
        #expect(coverageTask.contains("--filter E2ESerializedTests --skip ZmxE2ETests"))
        #expect(!coverageTask.contains("SWIFT_TEST_INCLUDE_ZMX_E2E"))
        #expect(generalE2ETask.contains("--filter E2ESerializedTests --skip ZmxE2ETests"))
        #expect(zmxE2ETask.contains("--filter ZmxE2ETests"))
        #expect(!zmxE2ETask.contains("--skip ZmxE2ETests"))
    }

    private func workflowStep(named stepName: String, in workflow: String) throws -> String {
        try namedBlock(
            startingWith: "      - name: \(stepName)",
            endingBefore: "\n      - name: ",
            in: workflow
        )
    }

    private func workflowJob(named jobName: String, in workflow: String) throws -> String {
        let workflowLines = workflow.split(separator: "\n", omittingEmptySubsequences: false)
        guard let startIndex = workflowLines.firstIndex(where: { $0 == "  \(jobName):" }) else {
            throw CIFastLaneWorkflowError.missingBlock("  \(jobName):")
        }

        var endIndex = workflowLines.index(after: startIndex)
        while endIndex < workflowLines.endIndex {
            let line = workflowLines[endIndex]
            if line.hasPrefix("  "), !line.hasPrefix("    "), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            endIndex = workflowLines.index(after: endIndex)
        }

        return workflowLines[startIndex..<endIndex].joined(separator: "\n")
    }

    private func shellCase(named caseName: String, in script: String) throws -> String {
        try namedBlock(
            startingWith: "  \(caseName))",
            endingBefore: "\n    ;;",
            in: script
        )
    }

    private func shellFunction(named functionName: String, in script: String) throws -> String {
        try namedBlock(
            startingWith: "\(functionName)() {",
            endingBefore: "\n}\n",
            in: script
        )
    }

    private func miseTask(named taskName: String, in config: String) throws -> String {
        let quotedMarker = "[tasks.\"\(taskName)\"]"
        let bareMarker = "[tasks.\(taskName)]"
        let marker = config.contains(quotedMarker) ? quotedMarker : bareMarker
        return try namedBlock(startingWith: marker, endingBefore: "\n[tasks.", in: config)
    }

    private func namedBlock(startingWith marker: String, endingBefore terminator: String, in text: String) throws
        -> String
    {
        guard let startRange = text.range(of: marker) else {
            throw CIFastLaneWorkflowError.missingBlock(marker)
        }
        let tail = text[startRange.lowerBound...]
        guard let endRange = tail.range(of: terminator, range: tail.index(after: startRange.lowerBound)..<tail.endIndex)
        else {
            return String(tail)
        }
        return String(tail[..<endRange.lowerBound])
    }
}

private enum CIFastLaneWorkflowError: Error {
    case missingBlock(String)
}
