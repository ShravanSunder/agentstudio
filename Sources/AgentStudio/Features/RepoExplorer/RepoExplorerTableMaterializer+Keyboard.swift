import AgentStudioCore
import AgentStudioInfrastructure
import AppKit

// Native selection and row chrome stay owned by the materializer.
extension RepoExplorerTableMaterializer {
    func applySelection(
        rowID: RepoExplorerRowID?,
        scrollIntoView: Bool
    ) -> Bool {
        guard !isDetached, let snapshot else { return rowID == nil }
        let targetRowIndex: Int?
        if let rowID {
            guard snapshot.navigationIndex.containsSelectableRow(rowID),
                let rowIndex = snapshot.rowIndexByID[rowID]
            else { return false }
            targetRowIndex = rowIndex
        } else {
            targetRowIndex = nil
        }

        let previousRowIndex = tableView.selectedRow
        isApplyingProgrammaticSelection = true
        defer {
            isApplyingProgrammaticSelection = false
            refreshKeyboardPresentation(at: previousRowIndex)
            if tableView.selectedRow != previousRowIndex {
                refreshKeyboardPresentation(at: tableView.selectedRow)
            }
        }
        if let targetRowIndex {
            tableView.selectRowIndexes(IndexSet(integer: targetRowIndex), byExtendingSelection: false)
            if scrollIntoView {
                tableView.scrollRowToVisible(targetRowIndex)
                scheduleViewportPublication()
            }
            return tableView.selectedRow == targetRowIndex
        }
        tableView.deselectAll(nil)
        return tableView.selectedRow == -1
    }

    func performListKeyboardEffect(_ effect: RepoExplorerListKeyboardEffect) {
        switch effect {
        case .commandRequest(let request):
            interactions.onCommandRequest(request)
        case .toggleGroup(let groupID):
            interactions.onToggleGroup(groupID)
        case .setGroupExpanded(let groupID, let isExpanded):
            interactions.onSetGroupExpanded(groupID, isExpanded)
        case .focusPane(let paneID):
            interactions.onFocusPane(paneID)
        }
    }

    func setShowsKeyboardHints(_ showsHints: Bool) {
        guard showsKeyboardHints != showsHints else { return }
        showsKeyboardHints = showsHints
        for rowIndex in representedRowIndexes() {
            refreshKeyboardPresentation(at: rowIndex)
        }
    }

    func keyboardPresentation(for rowID: RepoExplorerRowID) -> RepoExplorerRowKeyboardPresentation {
        let isSelected = tableView.selectedRow >= 0 && snapshot?.rowIndexByID[rowID] == tableView.selectedRow
        let shortcutDisplay: ShortcutDisplayText?
        if showsKeyboardHints, let digit = snapshot?.navigationIndex.digit(for: rowID) {
            shortcutDisplay = RepoExplorerListKeyboardAction.activateNumberedDestination(digit).trigger.displayText
        } else {
            shortcutDisplay = nil
        }
        return RepoExplorerRowKeyboardPresentation(isSelected: isSelected, shortcutDisplay: shortcutDisplay)
    }

    private func refreshKeyboardPresentation(at rowIndex: Int) {
        guard let snapshot, snapshot.rows.indices.contains(rowIndex),
            let cell = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? RepoExplorerTableRowCell
        else { return }
        cell.applyKeyboardPresentation(keyboardPresentation(for: snapshot.rows[rowIndex].id))
    }
}
