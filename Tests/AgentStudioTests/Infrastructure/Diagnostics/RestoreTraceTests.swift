import Foundation
import Testing

@testable import AgentStudio

@Suite("RestoreTrace")
struct RestoreTraceTests {
    @Test("duration metric line renders stable millisecond fields")
    func durationMetricLineRendersStableMillisecondFields() {
        let line = RestoreTrace.durationMetricLine(
            "pane_restore",
            duration: .nanoseconds(123_456_789),
            fields: [
                ("pane", "pane-1"),
                ("tier", "p0Visible"),
            ]
        )

        #expect(line == "metric=pane_restore durationMs=123.457 pane=pane-1 tier=p0Visible")
    }

    @Test("workspace save duration line includes graph counts")
    func workspaceSaveDurationLineIncludesGraphCounts() {
        let workspaceId = UUID(uuidString: "00000000-0000-7000-8000-000000000001")!

        let line = RestoreTrace.workspaceSaveDurationLine(
            workspaceId: workspaceId,
            paneCount: 30,
            tabCount: 4,
            duration: .milliseconds(9)
        )

        #expect(
            line
                == "metric=workspace_save durationMs=9.000 workspace=00000000-0000-7000-8000-000000000001 panes=30 tabs=4"
        )
    }
}
