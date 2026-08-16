import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer outline apply measurement")
struct RepoExplorerOutlineApplyMeasurementTests {
    @Test("reports changed rows and identical republish waste")
    func reportsChangedRowsAndIdenticalRepublishWaste() {
        var clockValues: [UInt64] = [1_000_000, 4_000_000, 8_000_000, 10_000_000]
        var applyCount = 0

        let changed = RepoExplorerView.measureOutlineApplyProxy(
            previousRowIDs: ["repo:a", "repo:b", "repo:c"],
            nextRowIDs: ["repo:a", "repo:c", "repo:d"],
            nowNanoseconds: { clockValues.removeFirst() },
            apply: { applyCount += 1 }
        )
        let equal = RepoExplorerView.measureOutlineApplyProxy(
            previousRowIDs: ["repo:a", "repo:c", "repo:d"],
            nextRowIDs: ["repo:a", "repo:c", "repo:d"],
            nowNanoseconds: { clockValues.removeFirst() },
            apply: { applyCount += 1 }
        )
        let suppressed = RepoExplorerView.measureSuppressedOutlineApplyProxy(rowCount: 3)

        #expect(applyCount == 2)
        #expect(
            changed
                == RepoExplorerOutlineApplyMeasurement(
                    duration: .milliseconds(3), totalRowCount: 3, changedRowCount: 3, equalPublishCount: 0,
                    outcome: .changed))
        #expect(
            equal
                == RepoExplorerOutlineApplyMeasurement(
                    duration: .milliseconds(2), totalRowCount: 3, changedRowCount: 0, equalPublishCount: 1,
                    outcome: .equal))
        #expect(
            suppressed
                == RepoExplorerOutlineApplyMeasurement(
                    duration: .zero, totalRowCount: 3, changedRowCount: 0, equalPublishCount: 1,
                    outcome: .suppressed))
    }
}
