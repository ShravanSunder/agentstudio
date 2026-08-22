import AppKit

@MainActor
protocol RepoExplorerNativeTableTransactionTarget: AnyObject {
    func beginUpdates()
    func removeRows(_ indexes: IndexSet)
    func moveRow(from oldIndex: Int, to newIndex: Int)
    func insertRows(_ indexes: IndexSet)
    func reloadRows(_ indexes: IndexSet)
    func noteHeightChanges(_ indexes: IndexSet)
    func endUpdates()
}

@MainActor
enum RepoExplorerNativeTransactionApplier {
    @discardableResult
    static func apply(
        plan: RepoExplorerNativeUpdatePlan,
        to target: RepoExplorerNativeTableTransactionTarget
    ) -> Bool {
        guard let tablePlan = tableUpdatePlan(from: plan) else { return false }

        return apply(tablePlan: tablePlan, to: target)
    }

    @discardableResult
    static func apply(
        tablePlan: RepoExplorerNativeTableUpdatePlan,
        to target: RepoExplorerNativeTableTransactionTarget
    ) -> Bool {

        target.beginUpdates()
        switch tablePlan {
        case .content(let content):
            applyContent(content, to: target)
        case .membership(let membership):
            if !membership.removeRowsInOldSpace.isEmpty {
                target.removeRows(membership.removeRowsInOldSpace)
            }
            for move in membership.movesFromOldToNewSpace {
                target.moveRow(from: move.oldIndex, to: move.newIndex)
            }
            if !membership.insertRowsInNewSpace.isEmpty {
                target.insertRows(membership.insertRowsInNewSpace)
            }
            if !membership.reloadRowsInNewSpace.isEmpty {
                target.reloadRows(membership.reloadRowsInNewSpace)
            }
            if !membership.heightReloadRowsInNewSpace.isEmpty {
                target.noteHeightChanges(membership.heightReloadRowsInNewSpace)
            }
        }
        target.endUpdates()
        return true
    }

    @discardableResult
    static func apply(plan: RepoExplorerNativeUpdatePlan, to tableView: NSTableView) -> Bool {
        apply(plan: plan, to: RepoExplorerNativeTableViewTransactionTarget(tableView: tableView))
    }

    private static func tableUpdatePlan(
        from plan: RepoExplorerNativeUpdatePlan
    ) -> RepoExplorerNativeTableUpdatePlan? {
        guard case .changed(let changed) = plan.kind else { return nil }
        switch changed.presentation {
        case .emptyToContent(let tablePlan), .contentToContent(let tablePlan):
            return tablePlan
        case .changedEmptyToEmpty, .contentToEmpty:
            return nil
        }
    }

    private static func applyContent(
        _ content: RepoExplorerNativeContentUpdatePlan,
        to target: RepoExplorerNativeTableTransactionTarget
    ) {
        if !content.reloadRowsInNewSpace.isEmpty {
            target.reloadRows(content.reloadRowsInNewSpace)
        }
        if !content.heightReloadRowsInNewSpace.isEmpty {
            target.noteHeightChanges(content.heightReloadRowsInNewSpace)
        }
    }
}

@MainActor
private final class RepoExplorerNativeTableViewTransactionTarget:
    RepoExplorerNativeTableTransactionTarget
{
    private let tableView: NSTableView

    init(tableView: NSTableView) {
        self.tableView = tableView
    }

    func beginUpdates() {
        tableView.beginUpdates()
    }

    func removeRows(_ indexes: IndexSet) {
        tableView.removeRows(at: indexes, withAnimation: [])
    }

    func moveRow(from oldIndex: Int, to newIndex: Int) {
        tableView.moveRow(at: oldIndex, to: newIndex)
    }

    func insertRows(_ indexes: IndexSet) {
        tableView.insertRows(at: indexes, withAnimation: [])
    }

    func reloadRows(_ indexes: IndexSet) {
        tableView.reloadData(
            forRowIndexes: indexes,
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
    }

    func noteHeightChanges(_ indexes: IndexSet) {
        tableView.noteHeightOfRows(withIndexesChanged: indexes)
    }

    func endUpdates() {
        tableView.endUpdates()
    }
}
