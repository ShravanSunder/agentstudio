import XCTest

final class ZmxTestHarnessTests: XCTestCase {
    func testExtractSessionNameFromKeyValueListLine() {
        let line = "session_name=agentstudio--repo--wt--pane\tattached=false"
        let name = ZmxTestHarness.extractSessionName(from: line)
        XCTAssertEqual(name, "agentstudio--repo--wt--pane")
    }

    func testExtractSessionNameFromShortListLine() {
        let line = "agentstudio--repo--wt--pane running"
        let name = ZmxTestHarness.extractSessionName(from: line)
        XCTAssertEqual(name, "agentstudio--repo--wt--pane")
    }

    func testExtractSessionNameReturnsNilForNonSessionLine() {
        let line = "attached=true\tcreated_at=123"
        let name = ZmxTestHarness.extractSessionName(from: line)
        XCTAssertNil(name)
    }

    func testExtractSessionNameFromRealZmxListFormat() {
        // Exact format: session_name=<name>\tpid=<pid>\tclients=<n>
        let line =
            "session_name=agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344\tpid=12345\tclients=0"
        let name = ZmxTestHarness.extractSessionName(from: line)
        XCTAssertEqual(name, "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
    }

    func testExtractSessionNameReturnsNilForEmptyLine() {
        XCTAssertNil(ZmxTestHarness.extractSessionName(from: ""))
        XCTAssertNil(ZmxTestHarness.extractSessionName(from: "  \t  "))
    }

    func testExtractSessionNameFromStaleSessionLine() {
        // Stale/error format: session_name=<name>\tstatus=<error>\t(cleaning up)
        let line = "session_name=agentstudio--abc--def--ghi\tstatus=connection_refused\t(cleaning up)"
        let name = ZmxTestHarness.extractSessionName(from: line)
        XCTAssertEqual(name, "agentstudio--abc--def--ghi")
    }
}
