import Foundation
import Testing

@Suite("CI fast lane workflow")
struct CIFastLaneWorkflowTests {
    @Test("fast lane keeps cached parallel default")
    func fastLaneKeepsCachedParallelDefault() throws {
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let testHelperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)

        #expect(ciWorkflow.contains("path: .build-ci"))
        #expect(ciWorkflow.contains("SWIFT_TEST_WORKERS: \"4\""))
        #expect(ciWorkflow.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(!ciWorkflow.contains("SWIFT_BUILD_DIR: .build-ci-fast"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_SHARD_BY_CLASS"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_SHARD_CLASS_COUNT"))
        #expect(!ciWorkflow.contains("SWIFT_TEST_PARALLEL: \"0\""))
        #expect(!ciWorkflow.contains("SWIFT_TEST_RUNNER_WARMUP_TIMEOUT_SECONDS"))
        #expect(!testHelperScript.contains("run_swift_class_shards"))
        #expect(!testHelperScript.contains("standalone_swift_test_filters"))
        #expect(!testHelperScript.contains("isolated_swift_test_class_filters"))
        #expect(!testHelperScript.contains("swift test list ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build"))
    }
}
