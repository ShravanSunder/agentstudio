import Foundation
import Testing

@Suite("CI fast lane workflow")
struct CIFastLaneWorkflowTests {
    @Test("fast lane keeps cached parallel default")
    func fastLaneKeepsCachedParallelDefault() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let swiftTestTaskScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let testHelperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let fastLaneStep = try workflowStep(named: "Test fast lane", in: ciWorkflow)
        let largeLaneStep = try workflowStep(named: "Test large non-WebKit lane", in: ciWorkflow)
        let prebuildStep = try workflowStep(named: "Prebuild Swift test bundles", in: ciWorkflow)
        let fastLaneMode = try shellCase(named: "test-fast", in: swiftTestTaskScript)
        let largeLaneMode = try shellCase(named: "test-large", in: swiftTestTaskScript)
        let nonSerializedRunner = try shellFunction(named: "run_non_serialized_swift_tests", in: testHelperScript)
        let fastRunner = try shellFunction(named: "run_fast_non_webkit_swift_tests", in: testHelperScript)
        let largeRunner = try shellFunction(named: "run_large_non_webkit_swift_tests", in: testHelperScript)

        #expect(ciWorkflow.contains("SWIFT_BUILD_DIR: .build-ci"))
        #expect(ciWorkflow.contains("path: .build-ci"))
        #expect(prebuildStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(prebuildStep.contains("run: mise run test-prebuild"))
        #expect(fastLaneStep.contains("SWIFT_TEST_WORKERS: \"4\""))
        #expect(fastLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(fastLaneStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"300\""))
        #expect(fastLaneStep.contains("_XCB_BYPASS: \"1\""))
        #expect(!fastLaneStep.contains("XCB_EXTRA_ARGS"))
        #expect(fastLaneStep.contains("run: mise run test-fast"))
        #expect(largeLaneStep.contains("SWIFT_TEST_WORKERS: \"4\""))
        #expect(largeLaneStep.contains("SWIFT_TEST_SKIP_PREBUILD: \"1\""))
        #expect(largeLaneStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(largeLaneStep.contains("_XCB_BYPASS: \"1\""))
        #expect(largeLaneStep.contains("run: mise run test-large"))
        #expect(swiftTestTaskScript.contains("test|test-fast|test-large|test-prebuild|test-webkit)"))
        #expect(swiftTestTaskScript.contains("if [ \"$mode\" = \"test-prebuild\" ]; then\n  prebuild_swift_tests"))
        #expect(swiftTestTaskScript.contains("AGENTSTUDIO_TRACE_BACKEND=\"${SWIFT_TEST_TRACE_BACKEND:-jsonl}\""))
        #expect(testHelperScript.contains("AGENTSTUDIO_TRACE_BACKEND=\"${SWIFT_TEST_TRACE_BACKEND:-jsonl}\""))
        #expect(fastLaneMode.contains("run_fast_non_webkit_swift_tests"))
        #expect(largeLaneMode.contains("run_large_non_webkit_swift_tests"))
        #expect(nonSerializedRunner.contains("--parallel --num-workers \"$SWIFT_TEST_WORKERS\""))
        #expect(nonSerializedRunner.contains("--skip WebKitSerializedTests"))
        #expect(nonSerializedRunner.contains("--skip E2ESerializedTests"))
        #expect(nonSerializedRunner.contains("--skip ZmxE2ETests"))
        #expect(fastRunner.contains("--parallel --num-workers \"$SWIFT_TEST_WORKERS\""))
        #expect(
            fastRunner.contains(
                "--skip 'Script|Smoke|Integration|Benchmark|ZmxStartupTraceAnalyzerTests|WorkspaceSurfaceCoordinatorFilesystemSourceTests|TerminalActivityAgentSettledHeuristicTests|MainWindowControllerInboxToolbarButtonTests|ProcessExecutorTests'"
            )
        )
        #expect(largeRunner.contains("--parallel --num-workers \"$SWIFT_TEST_WORKERS\""))
        #expect(
            largeRunner.contains(
                "--filter 'Script|Smoke|Integration|ZmxStartupTraceAnalyzerTests|WorkspaceSurfaceCoordinatorFilesystemSourceTests|TerminalActivityAgentSettledHeuristicTests|MainWindowControllerInboxToolbarButtonTests|ProcessExecutorTests'"
            )
        )
        #expect(largeRunner.contains("--skip WebKitSerializedTests"))
        #expect(largeRunner.contains("--skip E2ESerializedTests"))
        #expect(largeRunner.contains("--skip ZmxE2ETests"))
        #expect(!ciWorkflow.contains("SWIFT_BUILD_DIR: .build-ci-fast"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_SHARD_BY_CLASS"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_SHARD_CLASS_COUNT"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_PARALLEL: \"0\""))
        #expect(!ciWorkflow.contains("SWIFT_TEST_RUNNER_WARMUP_TIMEOUT_SECONDS"))
        #expect(!swiftTestTaskScript.contains("run_swift_class_shards"))
        #expect(!testHelperScript.contains("run_swift_class_shards"))
        #expect(!testHelperScript.contains("standalone_swift_test_filters"))
        #expect(!testHelperScript.contains("isolated_swift_test_class_filters"))
        #expect(!testHelperScript.contains("swift test list ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build"))
    }

    private func workflowStep(named stepName: String, in workflow: String) throws -> String {
        try namedBlock(
            startingWith: "      - name: \(stepName)",
            endingBefore: "\n      - name: ",
            in: workflow
        )
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
