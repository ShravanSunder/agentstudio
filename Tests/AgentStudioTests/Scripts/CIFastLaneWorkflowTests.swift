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
                "SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=\"${SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-1200}\""
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
        #expect(workflow.contains("  bridge-web-swift-backend:\n    name: BridgeWeb Swift backend"))
        #expect(workflow.contains("  swift-test-suite:\n    name: Swift test suite"))
        #expect(!workflow.contains("  static:"))
        #expect(!workflow.contains("  test:"))
    }

    @Test("CI jobs start independently without cross-job dependencies")
    func ciJobsStartIndependentlyWithoutCrossJobDependencies() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)

        for jobName in [
            "code-quality",
            "bridge-web-validation",
            "bridge-web-swift-backend",
            "swift-test-suite",
        ] {
            let job = try workflowJob(named: jobName, in: workflow)
            #expect(!job.contains("\n    needs:"))
        }
    }

    @Test("CI checkouts do not persist workflow credentials")
    func ciCheckoutsDoNotPersistWorkflowCredentials() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)

        for jobName in [
            "code-quality",
            "bridge-web-validation",
            "bridge-web-swift-backend",
            "swift-test-suite",
        ] {
            let job = try workflowJob(named: jobName, in: workflow)
            let checkoutStep = try workflowStep(named: "Checkout", in: job)

            #expect(checkoutStep.contains("persist-credentials: false"))
        }
    }

    @Test("BridgeWeb Swift-backend lanes run in their isolated job")
    func bridgeWebSwiftBackendLanesRunInTheirIsolatedJob() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let bridgeWebJob = try workflowJob(named: "bridge-web-validation", in: workflow)
        let backendJob = try workflowJob(named: "bridge-web-swift-backend", in: workflow)
        let swiftJob = try workflowJob(named: "swift-test-suite", in: workflow)
        let bridgeWebLaneStep = try workflowStep(named: "Run BridgeWeb lanes", in: bridgeWebJob)
        let resourceParallelRange = try #require(
            backendJob.range(of: "      - parallel:\n          - name: Copy XCFramework")
        )
        let packagedBuildRange = try #require(
            backendJob.range(of: "          - name: BridgeWeb packaged build")
        )
        let backendBuildRange = try #require(
            backendJob.range(of: "      - name: Build BridgeWeb Swift development backend")
        )
        let integrationRange = try #require(
            backendJob.range(of: "      - name: Test BridgeWeb Swift integration")
        )
        let e2eRange = try #require(
            backendJob.range(of: "      - name: Test BridgeWeb Swift E2E")
        )

        #expect(bridgeWebLaneStep.contains("pnpm --dir BridgeWeb run check"))
        #expect(bridgeWebLaneStep.contains("pnpm --dir BridgeWeb run test:unit"))
        #expect(bridgeWebLaneStep.contains("pnpm --dir BridgeWeb run test:browser:integration"))
        #expect(!bridgeWebLaneStep.contains("pnpm --dir BridgeWeb run test:integration\n"))
        #expect(!bridgeWebLaneStep.contains("pnpm --dir BridgeWeb run test:e2e"))
        #expect(backendJob.contains("pnpm --dir BridgeWeb run test:integration:node:prepared"))
        #expect(backendJob.contains("pnpm --dir BridgeWeb run test:e2e:prepared"))
        #expect(!backendJob.contains("pnpm --dir BridgeWeb run test:integration:node\n"))
        #expect(!backendJob.contains("pnpm --dir BridgeWeb run test:e2e\n"))
        #expect(!swiftJob.contains("test:integration:node"))
        #expect(!swiftJob.contains("test:e2e"))
        #expect(packagedBuildRange.upperBound < backendBuildRange.lowerBound)
        #expect(resourceParallelRange.upperBound < backendBuildRange.lowerBound)
        #expect(backendBuildRange.upperBound < integrationRange.lowerBound)
        #expect(integrationRange.upperBound < e2eRange.lowerBound)
    }

    @Test("backend job restores vendor caches without owning shared cache saves")
    func backendJobRestoresVendorCachesWithoutOwningSharedCacheSaves() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let backendJob = try workflowJob(named: "bridge-web-swift-backend", in: workflow)
        let swiftJob = try workflowJob(named: "swift-test-suite", in: workflow)
        let setupMiseStep = try workflowStep(named: "Setup mise", in: backendJob)
        let setupNodeStep = try workflowStep(named: "Setup Node for BridgeWeb", in: backendJob)

        #expect(setupMiseStep.contains("cache_save: false"))
        #expect(!setupNodeStep.contains("cache: pnpm"))
        #expect(!setupNodeStep.contains("cache-dependency-path:"))
        #expect(backendJob.contains("actions/cache/restore@v4"))
        #expect(backendJob.contains("Cache Ghostty artifacts"))
        #expect(backendJob.contains("Cache zmx artifacts"))
        #expect(backendJob.contains("Cache Zig compilation"))
        #expect(!backendJob.contains("Restore backend Swift cache seed"))
        #expect(!backendJob.contains("swift-test-v2-"))
        #expect(!backendJob.contains("uses: actions/cache@v4"))
        #expect(!backendJob.contains("actions/cache/save@v4"))
        #expect(swiftJob.contains("uses: actions/cache@v4"))
    }

    @Test("Swift jobs always build cold without caching build outputs")
    func swiftJobsAlwaysBuildColdWithoutCachingBuildOutputs() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let backendJob = try workflowJob(named: "bridge-web-swift-backend", in: ciWorkflow)
        let swiftJob = try workflowJob(named: "swift-test-suite", in: ciWorkflow)
        let prebuildStep = try workflowStep(named: "Prebuild Swift test bundles", in: swiftJob)

        #expect(!backendJob.contains("Compute Swift build input fingerprint"))
        #expect(!backendJob.contains("Restore backend Swift cache seed"))
        #expect(!backendJob.contains("swift-test-v2-"))
        #expect(!swiftJob.contains("Compute Swift build input fingerprint"))
        #expect(!swiftJob.contains("Restore Swift build cache"))
        #expect(!swiftJob.contains("Save Swift build cache"))
        #expect(!swiftJob.contains("swift-test-v2-"))
        #expect(!prebuildStep.contains("if:"))
        #expect(prebuildStep.contains("SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS: \"1200\""))
        #expect(prebuildStep.contains("run: mise run --skip-deps test:swift:prebuild"))
    }

    @Test("Swift preparation preserves independent parallel phases")
    func swiftPreparationPreservesIndependentParallelPhases() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let swiftJob = try workflowJob(named: "swift-test-suite", in: ciWorkflow)
        let restoreParallelBlock = try namedBlock(
            startingWith: "      - parallel:\n",
            endingBefore: "\n      - parallel:\n",
            in: swiftJob
        )
        let buildParallelBlock = try namedBlock(
            startingWith: "      - parallel:\n          - name: BridgeWeb packaged build\n",
            endingBefore: "\n      - parallel:\n          - name: Copy XCFramework",
            in: swiftJob
        )

        let restoreParallelRange = try #require(swiftJob.range(of: restoreParallelBlock))
        let buildParallelRange = try #require(swiftJob.range(of: buildParallelBlock))
        let copyResourcesRange = try #require(
            swiftJob.range(of: "      - parallel:\n          - name: Copy XCFramework")
        )

        #expect(restoreParallelRange.lowerBound < buildParallelRange.lowerBound)
        #expect(buildParallelRange.upperBound < copyResourcesRange.lowerBound)
        #expect(restoreParallelBlock.contains("Install BridgeWeb dependencies"))
        #expect(restoreParallelBlock.contains("Cache Zig compilation"))
        #expect(restoreParallelBlock.contains("Cache Ghostty artifacts"))
        #expect(restoreParallelBlock.contains("Cache zmx artifacts"))
        #expect(buildParallelBlock.contains("run: pnpm --dir BridgeWeb run build"))
        #expect(buildParallelBlock.contains("Build Ghostty XCFramework"))
        #expect(buildParallelBlock.contains("if: steps.cache-ghostty.outputs.cache-hit != 'true'"))
        #expect(buildParallelBlock.contains("Build zmx"))
        #expect(buildParallelBlock.contains("if: steps.cache-zmx.outputs.cache-hit != 'true'"))
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
        let globalPreferencesBenchmark = try String(
            contentsOfFile: "Tests/AgentStudioTests/App/Boot/GlobalPreferencesBootstrapPerformanceTests.swift",
            encoding: .utf8
        )
        let benchmarkWorkflow = try String(
            contentsOfFile: ".github/workflows/benchmarks.yml",
            encoding: .utf8
        )
        let benchmarkStep = try workflowStep(named: "Swift benchmark tests", in: benchmarkWorkflow)

        #expect(benchmarkTask.contains("--filter \"GlobalPreferencesBootstrapBenchmarkTests\""))
        #expect(benchmarkTask.contains("set -euo pipefail"))
        #expect(benchmarkTask.contains("export _XCB_BYPASS=1"))
        #expect(!benchmarkTask.contains("PushBenchmarkSupportTests"))
        #expect(!benchmarkTask.contains("PushPerformanceBenchmarkTests"))
        #expect(globalPreferencesBenchmark.contains("struct GlobalPreferencesBootstrapBenchmarkTests"))
        #expect(benchmarkStep.contains("grep -oE \"global-preferences-loader (missing|valid)"))
        #expect(benchmarkStep.contains("grep -c \"global-preferences-loader missing \""))
        #expect(benchmarkStep.contains("grep -c \"global-preferences-loader valid \""))
        #expect(!benchmarkStep.contains("No benchmark threshold lines emitted"))
    }

    @Test("fast lane keeps parallel defaults after cold prebuild")
    func fastLaneKeepsParallelDefaultsAfterColdPrebuild() throws {
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
        #expect(benchmarkWorkflow.contains("push:\n    branches: [main]"))
        #expect(benchmarkWorkflow.contains("workflow_dispatch:"))
        #expect(prebuildStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(prebuildStep.contains("SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS: \"1200\""))
        #expect(prebuildStep.contains("run: mise run --skip-deps test:swift:prebuild"))
        #expect(!fastLaneStep.contains("SWIFT_TEST_WORKERS"))
        #expect(fastLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(fastLaneStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(fastLaneStep.contains("SWIFT_TEST_NUM_WORKERS: \"4\""))
        #expect(fastLaneStep.contains("_XCB_BYPASS: \"1\""))
        #expect(!fastLaneStep.contains("XCB_EXTRA_ARGS"))
        #expect(fastLaneStep.contains("run: mise run --skip-deps --raw test:swift:fast"))
        #expect(webKitLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(webKitLaneStep.contains("run: mise run --skip-deps test:swift:webkit"))
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
                "--skip \"GlobalPreferencesBootstrapBenchmarkTests|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)|$(aggregate_serial_non_webkit_filter_pattern)\""
            )
        )
        #expect(fastRunner.contains("run_aggregate_serial_non_webkit_swift_tests"))
        #expect(!testHelperScript.contains("app_ipc_live_socket_suite_filters"))
        #expect(!fastRunner.contains("serial App IPC service live socket suites"))
        #expect(!fastRunner.contains("app_ipc_live_socket_suite_filter"))
        #expect(largeRunner.contains("--parallel"))
        #expect(largeRunner.contains("--num-workers \"$SWIFT_TEST_NUM_WORKERS\""))
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

    @Test("routine Swift proof uses bounded fast and large lanes")
    func routineSwiftProofUsesBoundedFastAndLargeLanes() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let swiftTestTaskScript = try String(
            contentsOfFile: "scripts/run-swift-test-task.sh",
            encoding: .utf8
        )
        let ciLargeLaneStep = try workflowStep(named: "Test large lane", in: ciWorkflow)
        let aggregateLaneMode = try shellCase(named: "test", in: swiftTestTaskScript)

        #expect(ciLargeLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(ciLargeLaneStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(ciLargeLaneStep.contains("SWIFT_TEST_NUM_WORKERS: \"4\""))
        #expect(ciLargeLaneStep.contains("_XCB_BYPASS: \"1\""))
        #expect(ciLargeLaneStep.contains("run: mise run --skip-deps --raw test:swift:large"))
        #expect(aggregateLaneMode.contains("SWIFT_TEST_NUM_WORKERS=\"${SWIFT_TEST_NUM_WORKERS:-4}\""))
        #expect(aggregateLaneMode.contains("run_fast_non_webkit_swift_tests"))
        #expect(aggregateLaneMode.contains("run_large_non_webkit_swift_tests"))
        #expect(!aggregateLaneMode.contains("run_non_serialized_swift_tests"))
    }

    @Test("aggregate lane isolates executor-sensitive and AppKit-global tests")
    func aggregateLaneIsolatesExecutorSensitiveAndAppKitGlobalTests() throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let aggregateFilter = try shellFunction(
            named: "aggregate_serial_non_webkit_filter_pattern",
            in: helperScript
        )
        let aggregateRunner = try shellFunction(
            named: "run_aggregate_serial_non_webkit_swift_tests",
            in: helperScript
        )
        let fullRunner = try shellFunction(named: "run_non_serialized_swift_tests", in: helperScript)
        let fastRunner = try shellFunction(named: "run_fast_non_webkit_swift_tests", in: helperScript)

        for suiteName in [
            "EagerDerivedAtomTests",
            "EagerDerivedAtomFamilyTests",
            "TabBarAdapterTests",
            "TabBarAdapterMaterializationTests",
            "TabBarAffectedItemTelemetryTests",
            "MainSplitViewControllerSidebarStateTests",
            "FlatTabStripContainerAllMinimizedTests",
        ] {
            #expect(aggregateFilter.contains(suiteName))
        }
        #expect(fullRunner.contains("--skip \"$(aggregate_serial_non_webkit_filter_pattern)\""))
        #expect(fullRunner.contains("run_aggregate_serial_non_webkit_swift_tests"))
        #expect(aggregateRunner.contains("serial aggregate-only non-WebKit suites"))
        #expect(aggregateRunner.contains("--filter \"$(aggregate_serial_non_webkit_filter_pattern)\""))
        #expect(
            fastRunner.contains(
                "--skip \"GlobalPreferencesBootstrapBenchmarkTests|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)|$(aggregate_serial_non_webkit_filter_pattern)\""
            )
        )
        #expect(fastRunner.contains("run_aggregate_serial_non_webkit_swift_tests"))
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
