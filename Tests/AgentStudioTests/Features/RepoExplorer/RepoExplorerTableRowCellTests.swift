import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer hosted table row cell", .serialized)
struct RepoExplorerTableRowCellTests {
    @Test("persistent hosting root resets A to B to A identity and rejects stale callbacks")
    func persistentRootResetsIdentityAndRejectsStaleCallbacks() throws {
        let cell = RepoExplorerTableRowCell(
            octiconLoader: makeRepoExplorerTestOcticonLoader()
        )
        let hostingViewIdentity = ObjectIdentifier(cell.hostingView)
        let firstRow = hostedCellRow(id: "A", title: "First A")
        let secondRow = hostedCellRow(id: "B", title: "B")

        let firstBinding = cell.bind(row: firstRow, visibleGeneration: 7)
        let equalBinding = cell.bind(row: firstRow, visibleGeneration: 7)
        var executedIdentities: [RepoExplorerRowID] = []
        let delayedFirstAction = {
            cell.performIfCurrent(firstBinding) {
                executedIdentities.append(firstBinding.rowID)
            }
        }

        #expect(equalBinding == firstBinding)
        let secondBinding = cell.bind(row: secondRow, visibleGeneration: 7)
        #expect(!delayedFirstAction())
        #expect(executedIdentities.isEmpty)
        #expect(secondBinding.rowID == secondRow.id)
        #expect(secondBinding.reuseToken != firstBinding.reuseToken)
        #expect(ObjectIdentifier(cell.hostingView) == hostingViewIdentity)

        let reboundFirst = cell.bind(row: firstRow, visibleGeneration: 8)
        #expect(reboundFirst.rowID == firstRow.id)
        #expect(reboundFirst.reuseToken != firstBinding.reuseToken)
        #expect(reboundFirst.visibleGeneration == 8)
        #expect(!delayedFirstAction())
        #expect(
            cell.performIfCurrent(reboundFirst) {
                executedIdentities.append(reboundFirst.rowID)
            }
        )
        #expect(executedIdentities == [firstRow.id])
        #expect(ObjectIdentifier(cell.hostingView) == hostingViewIdentity)
    }

    @Test("clear invalidates binding and accessibility before the next row installs")
    func clearInvalidatesBindingAndAccessibility() {
        let cell = RepoExplorerTableRowCell(
            octiconLoader: makeRepoExplorerTestOcticonLoader()
        )
        let row = hostedCellRow(id: "A", title: "Accessible A")
        let binding = cell.bind(row: row, visibleGeneration: 1)

        #expect(cell.currentBindingIdentity == binding)
        #expect(cell.accessibilityLabel() == "Accessible A")

        cell.clearBindingForReuse()

        #expect(cell.currentBindingIdentity == nil)
        #expect(cell.accessibilityLabel() == nil)
        #expect(!cell.performIfCurrent(binding) {})
    }

    @Test("same row command update preserves reuse identity and rejects the prior command generation")
    func sameRowCommandUpdatePreservesIdentityAndRejectsPriorGeneration() {
        let cell = RepoExplorerTableRowCell(
            octiconLoader: makeRepoExplorerTestOcticonLoader()
        )
        let row = hostedCellRow(id: "A", title: "A")
        let firstSnapshot = RepoExplorerCommandPresentationSnapshot(generation: 3, results: [:])
        let nextSnapshot = RepoExplorerCommandPresentationSnapshot(generation: 4, results: [:])
        let binding = cell.bind(
            row: row,
            visibleGeneration: 7,
            commandPresentationSnapshot: firstSnapshot
        )
        var executionCount = 0

        let rebound = cell.bind(
            row: row,
            visibleGeneration: 7,
            commandPresentationSnapshot: nextSnapshot
        )

        #expect(rebound == binding)
        #expect(cell.currentCommandGeneration == 4)
        #expect(
            !cell.performCommandIfCurrent(binding, commandGeneration: 3) {
                executionCount += 1
            }
        )
        #expect(
            cell.performCommandIfCurrent(binding, commandGeneration: 4) {
                executionCount += 1
            }
        )
        #expect(executionCount == 1)
    }

    @Test("materialized section group and worktree rows expose current native labels")
    func materializedRowsExposeCurrentNativeLabels() throws {
        let result = try RepoExplorerProjectionWorker.project(
            makeProjectionIntentRequest(generation: 1)
        )
        let cell = RepoExplorerTableRowCell(
            octiconLoader: makeRepoExplorerTestOcticonLoader()
        )

        for row in result.materializationSnapshot.rows {
            _ = cell.bind(row: row, visibleGeneration: 1)
            #expect(cell.accessibilityRole() == .row)
            #expect(cell.accessibilityLabel()?.isEmpty == false)
            #expect(cell.currentBindingIdentity?.rowID == row.id)
        }
    }

    @Test("group and pane interactions validate the represented row before reaching existing owners")
    func groupAndPaneInteractionsValidateRepresentedRowIdentity() {
        var toggledGroupIDs: [String] = []
        var focusedPaneIDs: [UUID] = []
        let slot = RepoExplorerTableRowSlot(
            interactions: RepoExplorerTableInteractions(
                onCommandRequest: { _ in },
                onToggleGroup: { toggledGroupIDs.append($0) },
                onFocusPane: { focusedPaneIDs.append($0) }
            )
        )
        let currentIdentity = RepoExplorerTableRowBindingIdentity(
            visibleGeneration: 4,
            rowID: .group(groupID: "current"),
            reuseToken: RepoExplorerTableRowReuseToken(rawValue: 1)
        )
        let staleIdentity = RepoExplorerTableRowBindingIdentity(
            visibleGeneration: 3,
            rowID: .group(groupID: "stale"),
            reuseToken: RepoExplorerTableRowReuseToken(rawValue: 0)
        )
        slot.install(
            RepoExplorerTableRowBinding(
                identity: currentIdentity,
                row: hostedCellRow(id: "current", title: "Current"),
                commandPresentationSnapshot: .empty
            )
        )
        let paneID = UUIDv7.generate()

        slot.toggleGroup("stale", identity: staleIdentity)
        slot.focusPane(UUIDv7.generate(), identity: staleIdentity)
        slot.toggleGroup("current", identity: currentIdentity)
        slot.focusPane(paneID, identity: currentIdentity)

        #expect(toggledGroupIDs == ["current"])
        #expect(focusedPaneIDs == [paneID])
    }
}

private func hostedCellRow(id: String, title: String) -> RepoExplorerMaterializedRow {
    let presentation = RepoExplorerMaterializedRowPresentation.groupHeader(
        RepoExplorerMaterializedGroupHeaderPresentation(
            groupID: id,
            icon: .repo,
            title: title,
            organizationName: nil,
            colorHex: nil,
            isExpanded: true,
            repoIDs: [],
            semanticRepoPath: nil,
            paneDestinations: []
        )
    )
    return RepoExplorerMaterializedRow(
        id: .group(groupID: id),
        contentRevision: RepoExplorerRowContentRevision(presentation: presentation),
        layout: RepoExplorerRowLayout.make(for: presentation),
        representedRepoID: nil,
        representedWorktreeID: nil
    )
}
