import Testing
import Foundation

@Suite(.serialized)
struct ZmxTestHarnessTests {

    @Test
    func testExtractSessionNameFromKeyValueListLine() {
        let line = "session_name=agentstudio--repo--wt--pane\tattached=false"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "agentstudio--repo--wt--pane")
    }

    @Test
    func testExtractSessionNameFromShortListLine() {
        let line = "agentstudio--repo--wt--pane running"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "agentstudio--repo--wt--pane")
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
            "session_name=agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344\tpid=12345\tclients=0"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
    }

    @Test
    func testExtractSessionNameReturnsNilForEmptyLine() {
        #expect(ZmxTestHarness.extractSessionName(from: "") == nil)
        #expect(ZmxTestHarness.extractSessionName(from: "  \t  ") == nil)
    }

    @Test
    func testExtractSessionNameFromStaleSessionLine() {
        // Stale/error format: session_name=<name>\tstatus=<error>\t(cleaning up)
        let line = "session_name=agentstudio--abc--def--ghi\tstatus=connection_refused\t(cleaning up)"
        let name = ZmxTestHarness.extractSessionName(from: line)
        #expect(name == "agentstudio--abc--def--ghi")
    }
}
