import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class NativeTransactionRecordingTarget: RepoExplorerNativeTableTransactionTarget {
    private(set) var operations: [String] = []

    func beginUpdates() { operations.append("begin") }
    func removeRows(_ indexes: IndexSet) { operations.append("remove:\(Array(indexes))") }
    func moveRow(from oldIndex: Int, to newIndex: Int) {
        operations.append("move:\(oldIndex)->\(newIndex)")
    }
    func insertRows(_ indexes: IndexSet) { operations.append("insert:\(Array(indexes))") }
    func reloadRows(_ indexes: IndexSet) { operations.append("reload:\(Array(indexes))") }
    func noteHeightChanges(_ indexes: IndexSet) { operations.append("height:\(Array(indexes))") }
    func endUpdates() { operations.append("end") }
}

@MainActor
private final class CellFreeNativeTableDataSource: NSObject, NSTableViewDataSource {
    var rowCount: Int

    init(rowCount: Int) {
        self.rowCount = rowCount
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }
}

@MainActor
@Suite("Repo Explorer native transaction applier", .serialized)
struct RepoExplorerNativeTransactionApplierTests {
    @Test("production applier emits one exact transaction in declared index spaces")
    func appliesExactMembershipTransaction() throws {
        let oldSnapshot = nativePlanSnapshot(["A", "B", "C", "D"])
        let newSnapshot = nativePlanSnapshot(["B", "E", "D", "A"], changedTitles: ["B"])
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: nativePlanBaseline(snapshot: oldSnapshot, revision: 1),
            candidate: nativePlanContent(newSnapshot),
            requestGeneration: 2
        ).get()
        let target = NativeTransactionRecordingTarget()

        #expect(RepoExplorerNativeTransactionApplier.apply(plan: plan, to: target))
        #expect(
            target.operations == [
                "begin",
                "remove:[2]",
                "move:0->3",
                "insert:[1]",
                "reload:[0]",
                "end",
            ])
    }

    @Test("equal plan performs zero table work")
    func equalPlanPerformsNoTableWork() throws {
        let snapshot = nativePlanSnapshot(["A"])
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: nativePlanBaseline(snapshot: snapshot, revision: 1),
            candidate: nativePlanContent(snapshot),
            requestGeneration: 2
        ).get()
        let target = NativeTransactionRecordingTarget()

        #expect(!RepoExplorerNativeTransactionApplier.apply(plan: plan, to: target))
        #expect(target.operations.isEmpty)
    }

    @Test("real NSTableView cell-free harness accepts the production transaction")
    func realTableViewAppliesMembershipPlan() throws {
        let oldSnapshot = nativePlanSnapshot(["A", "B", "C"])
        let newSnapshot = nativePlanSnapshot(["B", "D", "A"])
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: nativePlanBaseline(snapshot: oldSnapshot, revision: 1),
            candidate: nativePlanContent(newSnapshot),
            requestGeneration: 2
        ).get()
        let dataSource = CellFreeNativeTableDataSource(rowCount: oldSnapshot.rows.count)
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar")))
        tableView.dataSource = dataSource
        tableView.reloadData()
        #expect(tableView.numberOfRows == oldSnapshot.rows.count)

        dataSource.rowCount = newSnapshot.rows.count
        #expect(RepoExplorerNativeTransactionApplier.apply(plan: plan, to: tableView))
        #expect(tableView.numberOfRows == newSnapshot.rows.count)
    }
}
