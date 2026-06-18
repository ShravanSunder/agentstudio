import Foundation
import Testing

@Suite("Swift test helper sharding")
struct SwiftTestHelperShardingTests {
    @Test("class sharding bounds SwiftPM test discovery")
    func classShardingBoundsSwiftPMTestDiscovery() throws {
        let testHelperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)

        #expect(testHelperScript.contains("run_swift_standalone_test_filters \"$label\" || return $?"))
        #expect(testHelperScript.contains("run_swift_isolated_test_classes \"$label\" || return $?"))
        #expect(testHelperScript.contains("standalone_swift_test_filters()"))
        #expect(testHelperScript.contains("AgentStudioIPCTransportTests"))
        #expect(testHelperScript.contains("AgentStudioProgrammaticControlTests"))
        #expect(testHelperScript.contains("AgentStudioAppIPCTests.AgentStudioAppIPCServiceTests"))
        #expect(testHelperScript.contains("AgentStudioAppIPCTests.AgentStudioIPCPermissionBrokerTests"))
        #expect(testHelperScript.contains("AgentStudioIPCClientTests"))
        #expect(testHelperScript.contains("standalone $label filter $swift_filter"))
        #expect(testHelperScript.contains("isolated_swift_test_class_filters()"))
        #expect(testHelperScript.contains("AgentStudioTests.PaneTabViewControllerTabRetentionTests"))
        #expect(testHelperScript.contains("isolated $label class $test_class"))
        #expect(testHelperScript.contains("grep -Fvx -f <(isolated_swift_test_class_filters)"))
        #expect(testHelperScript.contains("\"list sharded $label classes\""))
        #expect(testHelperScript.contains("awk '/^AgentStudioTests\\./"))
        #expect(testHelperScript.contains("swift test list ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build"))
        #expect(testHelperScript.contains("return \"$list_status\""))
        #expect(testHelperScript.contains("rm -f \"$class_file\" \"$list_output_file\""))
    }
}
