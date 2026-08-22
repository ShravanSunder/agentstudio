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
