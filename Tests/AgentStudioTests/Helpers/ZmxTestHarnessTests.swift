import Foundation
import Testing

@Suite(.serialized)
struct ZmxTestHarnessTests {

    @Test
    func testExtractSessionNameFromKeyValueListLine() {
        let line = "session_name=as-repo-wt-pane\tattached=false"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "as-repo-wt-pane")
    }

    @Test
    func testExtractSessionNameFromShortListLine() {
        let line = "as-repo-wt-pane running"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "as-repo-wt-pane")
    }

    @Test
    func testExtractSessionNameReturnsNilForNonSessionLine() {
        let line = "attached=true\tcreated_at=123"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == nil)
    }

    @Test
    func testExtractSessionNameFromRealZmxListFormat() {
        // Exact format: session_name=<name>\tpid=<pid>\tclients=<n>
        let line =
            "session_name=as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344\tpid=12345\tclients=0"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
    }

    @Test
    func testExtractSessionNameFromZmx042ListFormat() {
        let line =
            "name=as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344\tpid=12345\tclients=0\tcreated=1774059493\tstart_dir=/tmp\tcmd=/bin/sleep 300"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
    }

    @Test
    func testExtractSessionNameReturnsNilForEmptyLine() {
        #expect(ZmxTestHarness.extractSessionName(from: "") == nil)
        #expect(ZmxTestHarness.extractSessionName(from: "  \t  ") == nil)
    }

    @Test
    func testExtractSessionNameFromStaleSessionLine() {
        // Stale/error format: session_name=<name>\tstatus=<error>\t(cleaning up)
        let line = "session_name=as-abc-def-ghi\tstatus=connection_refused\t(cleaning up)"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "as-abc-def-ghi")
    }
}
