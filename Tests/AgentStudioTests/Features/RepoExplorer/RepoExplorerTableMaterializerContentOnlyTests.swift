import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer table materializer content-only application policy", .serialized)
struct RepoExplorerTableMaterializerContentOnlyTests {
    @Test("content-only update keeps anchor and performs no geometry work")
    func contentOnlyUpdateKeepsAnchorAndPerformsNoGeometryWork() throws {
        let identities = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let initialSnapshot = nativePlanSnapshot(identities)
        let materializer = RepoExplorerTableMaterializer(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            onVisibleWorktreeSnapshotChange: { _ in }
        )
        let window = makeMaterializerWindow(materializer, height: 40)
        defer {
            materializer.detach()
            window.close()
        }

        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: initialSnapshot,
                requestGeneration: 1
            )
        ) { _ in }
        let tableView = try #require((materializer.view as? NSScrollView)?.documentView as? NSTableView)
        materializer.scroll(to: .group(groupID: "C"), offset: 3)
        materializeVisibleCells(in: tableView, visibleRect: tableView.visibleRect)

        let representedRange = tableView.rows(in: tableView.visibleRect)
        try #require(representedRange.location != NSNotFound)
        let changedRowIndex = try #require(initialSnapshot.rowIndexByID[.group(groupID: "C")])
        try #require(
            changedRowIndex >= representedRange.location
                && changedRowIndex < NSMaxRange(representedRange)
        )
        let unchangedRowIndex = try #require(
            (representedRange.location..<NSMaxRange(representedRange))
                .first { $0 != changedRowIndex }
        )

        let anchorBeforeContentOnlyUpdate = materializer.currentTopVisibleAnchor
        let tableFrameUpdateCountBeforeContentOnlyUpdate = materializer.tableFrameUpdateCount
        let forcedLayoutPassCountBeforeContentOnlyUpdate = materializer.forcedLayoutPassCount
        let explicitScrollRestorationCountBeforeContentOnlyUpdate =
            materializer.explicitScrollRestorationCount
        let changedRowIdentityBeforeUpdate =
            (tableView.view(atColumn: 0, row: changedRowIndex, makeIfNecessary: false)
            as? RepoExplorerTableRowCell)?.currentBindingIdentity
        let unchangedRowIdentityBeforeUpdate =
            (tableView.view(atColumn: 0, row: unchangedRowIndex, makeIfNecessary: false)
            as? RepoExplorerTableRowCell)?.currentBindingIdentity
        #expect(changedRowIdentityBeforeUpdate != nil)
        #expect(unchangedRowIdentityBeforeUpdate != nil)

        var disposition: RepoExplorerMaterializationChildDisposition?
        materializer.apply(
            try tableCandidate(
                baseline: nativePlanBaseline(
                    snapshot: initialSnapshot,
                    revision: 1,
                    visibleGeneration: 1
                ),
                snapshot: nativePlanSnapshot(identities, changedTitles: ["C"]),
                requestGeneration: 2
            )
        ) { disposition = $0 }

        #expect(disposition == .accepted)
        #expect(materializer.currentTopVisibleAnchor == anchorBeforeContentOnlyUpdate)
        #expect(materializer.tableFrameUpdateCount == tableFrameUpdateCountBeforeContentOnlyUpdate)
        #expect(materializer.forcedLayoutPassCount == forcedLayoutPassCountBeforeContentOnlyUpdate)
        #expect(
            materializer.explicitScrollRestorationCount
                == explicitScrollRestorationCountBeforeContentOnlyUpdate
        )

        let changedRowIdentityAfterUpdate =
            (tableView.view(atColumn: 0, row: changedRowIndex, makeIfNecessary: false)
            as? RepoExplorerTableRowCell)?.currentBindingIdentity
        let unchangedRowIdentityAfterUpdate =
            (tableView.view(atColumn: 0, row: unchangedRowIndex, makeIfNecessary: false)
            as? RepoExplorerTableRowCell)?.currentBindingIdentity
        #expect(changedRowIdentityAfterUpdate != changedRowIdentityBeforeUpdate)
        #expect(unchangedRowIdentityAfterUpdate == unchangedRowIdentityBeforeUpdate)
    }

    @Test("height-changing update restores anchor")
    func heightChangingUpdateRestoresAnchor() throws {
        let identities = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let initialSnapshot = nativePlanSnapshot(identities)
        let materializer = RepoExplorerTableMaterializer(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            onVisibleWorktreeSnapshotChange: { _ in }
        )
        let window = makeMaterializerWindow(materializer, height: 40)
        defer {
            materializer.detach()
            window.close()
        }

        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: initialSnapshot,
                requestGeneration: 1
            )
        ) { _ in }
        let tableView = try #require((materializer.view as? NSScrollView)?.documentView as? NSTableView)
        materializer.scroll(to: .group(groupID: "C"), offset: 3)
        materializeVisibleCells(in: tableView, visibleRect: tableView.visibleRect)

        let forcedLayoutPassCountBeforeHeightChange = materializer.forcedLayoutPassCount
        let explicitScrollRestorationCountBeforeHeightChange =
            materializer.explicitScrollRestorationCount

        var disposition: RepoExplorerMaterializationChildDisposition?
        materializer.apply(
            try tableCandidate(
                baseline: nativePlanBaseline(
                    snapshot: initialSnapshot,
                    revision: 1,
                    visibleGeneration: 1
                ),
                snapshot: nativePlanSnapshot(identities, changedLayouts: ["C"]),
                requestGeneration: 2
            )
        ) { disposition = $0 }

        #expect(disposition == .accepted)
        #expect(materializer.currentTopVisibleAnchor?.rowID == .group(groupID: "C"))
        #expect(materializer.forcedLayoutPassCount > forcedLayoutPassCountBeforeHeightChange)
        #expect(
            materializer.explicitScrollRestorationCount
                == explicitScrollRestorationCountBeforeHeightChange + 1
        )
    }

    @Test("width-measured changed row is treated as height-affecting")
    func widthMeasuredChangedRowIsTreatedAsHeightAffecting() throws {
        let identities = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let initialSnapshot = widthMeasuredSnapshot(identities)
        let materializer = RepoExplorerTableMaterializer(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            onVisibleWorktreeSnapshotChange: { _ in }
        )
        let window = makeMaterializerWindow(materializer, height: 40)
        defer {
            materializer.detach()
            window.close()
        }

        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: initialSnapshot,
                requestGeneration: 1
            )
        ) { _ in }
        let tableView = try #require((materializer.view as? NSScrollView)?.documentView as? NSTableView)
        materializeVisibleCells(in: tableView, visibleRect: tableView.visibleRect)

        let forcedLayoutPassCountBeforeWidthMeasuredChange = materializer.forcedLayoutPassCount

        var disposition: RepoExplorerMaterializationChildDisposition?
        materializer.apply(
            try tableCandidate(
                baseline: nativePlanBaseline(
                    snapshot: initialSnapshot,
                    revision: 1,
                    visibleGeneration: 1
                ),
                snapshot: widthMeasuredSnapshot(identities, changedTitles: ["C"]),
                requestGeneration: 2
            )
        ) { disposition = $0 }

        #expect(disposition == .accepted)
        #expect(materializer.forcedLayoutPassCount > forcedLayoutPassCountBeforeWidthMeasuredChange)
    }

    private func widthMeasuredSnapshot(
        _ identities: [String],
        changedTitles: Set<String> = []
    ) -> RepoExplorerMaterializationSnapshot {
        let source = nativePlanSnapshot(identities, changedTitles: changedTitles)
        return RepoExplorerMaterializationSnapshot(
            rows: source.rows.map { row in
                RepoExplorerMaterializedRow(
                    id: row.id,
                    contentRevision: row.contentRevision,
                    layout: RepoExplorerRowLayout(
                        rowClass: row.layout.rowClass,
                        metrics: row.layout.metrics,
                        requiresVisibleWidthMeasurement: true
                    ),
                    representedRepoID: nil,
                    representedWorktreeID: nil
                )
            }
        )
    }

    private func makeMaterializerWindow(
        _ materializer: RepoExplorerTableMaterializer,
        height: CGFloat = 36
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = materializer.view
        window.layoutIfNeeded()
        return window
    }

    private func tableCandidate(
        baseline: RepoExplorerMaterializationBaseline,
        snapshot: RepoExplorerMaterializationSnapshot,
        requestGeneration: UInt64
    ) throws -> RepoExplorerMaterializationContentCandidate {
        let presentation = nativePlanContent(snapshot)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: presentation,
            requestGeneration: requestGeneration
        ).get()
        let tablePlan = try #require(plan.tableUpdatePlan())
        return RepoExplorerMaterializationContentCandidate(
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: requestGeneration),
            requestGeneration: requestGeneration,
            visibleGeneration: requestGeneration,
            snapshot: snapshot,
            tableUpdatePlan: tablePlan
        )
    }
}

@MainActor
private func materializeVisibleCells(in tableView: NSTableView, visibleRect: NSRect) {
    let visibleRows = tableView.rows(in: visibleRect)
    guard visibleRows.location != NSNotFound else { return }
    for rowIndex in visibleRows.location..<NSMaxRange(visibleRows) {
        _ = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: true)
    }
}
