import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Workspace undo composition preparation")
struct WorkspaceUndoCompositionTests {
    private let time = WorkspaceUndoJournalTime(
        utc: Date(timeIntervalSince1970: 100), bootID: "boot-fixture", uptimeNanoseconds: 100_000_000_000
    )

    @Test("drawer-child close removes live ownership while preserving its parent", arguments: [true, false])
    func drawerChildClosePreservesParent(expanded: Bool) throws {
        var parent = makePane(id: UUIDv7.generate())
        var child = makePane(id: UUIDv7.generate())
        child.kind = .drawerChild(parentPaneId: parent.id)
        parent.withDrawer {
            $0.paneIds = [child.id]
            $0.isExpanded = expanded
        }
        let drawerID = try #require(parent.drawer?.drawerId)
        var tab = Tab(id: UUIDv7.generate(), paneId: parent.id)
        tab.arrangements[0].drawerViews[drawerID] = DrawerView(
            layout: DrawerGridLayout(topRow: Layout(paneId: child.id)), activeChildId: child.id
        )
        let original = WorkspaceSQLiteSnapshot(id: UUIDv7.generate(), panes: [parent, child], tabs: [tab])

        let proposal = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: original), tabID: tab.id, paneID: child.id, closeID: UUIDv7.generate(), time: time
        )

        #expect(proposal.removedPaneIDs == [child.id])
        #expect(proposal.bundle.workspace.panes.map(\.id) == [parent.id])
        #expect(proposal.bundle.workspace.panes.first?.drawer?.paneIds.isEmpty == true)
        #expect(proposal.bundle.workspace.tabs.first?.arrangements.first?.drawerViews[drawerID] == nil)
        #expect(proposal.snapshot.panes.map(\.id) == [child.id])
        #expect(original.panes.first?.drawer?.paneIds == [child.id])
    }

    @Test("closing a tab captures drawer children even when tab membership lists only the parent")
    func tabCloseCapturesDrawerChildren() throws {
        var parent = makePane(id: UUIDv7.generate())
        var child = makePane(id: UUIDv7.generate())
        child.kind = .drawerChild(parentPaneId: parent.id)
        parent.withDrawer { $0.paneIds = [child.id] }
        let tab = Tab(id: UUIDv7.generate(), paneId: parent.id)
        let original = WorkspaceSQLiteSnapshot(id: UUIDv7.generate(), panes: [parent, child], tabs: [tab])
        let proposal = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: original), tabID: tab.id, paneID: nil, closeID: UUIDv7.generate(), time: time
        )
        #expect(Set(proposal.snapshot.panes.map(\.id)) == [parent.id, child.id])
        #expect(proposal.bundle.workspace.panes.isEmpty)
    }

    @Test("tab close prepares durable ownership without mutating the input workspace")
    func tabCloseLeavesInputUntouched() throws {
        let first = makePane(id: UUIDv7.generate())
        let second = makePane(id: UUIDv7.generate())
        let firstTab = Tab(id: UUIDv7.generate(), paneId: first.id)
        let secondTab = Tab(id: UUIDv7.generate(), paneId: second.id)
        let original = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(), panes: [first, second], tabs: [firstTab, secondTab], activeTabId: firstTab.id
        )

        let proposal = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: original), tabID: firstTab.id, paneID: nil, closeID: UUIDv7.generate(), time: time
        )

        #expect(original.panes.map(\.id) == [first.id, second.id])
        #expect(proposal.bundle.workspace.panes.map(\.id) == [second.id])
        #expect(proposal.bundle.workspace.tabs.map(\.id) == [secondTab.id])
        #expect(proposal.bundle.workspace.activeTabId == secondTab.id)
        #expect(proposal.snapshot.panes.map(\.id) == [first.id])
        #expect(proposal.write.members == [.init(paneID: first.id, sessionID: first.terminalState?.zmxSessionID)])
        #expect(proposal.write.expiresAt == Date(timeIntervalSince1970: 400))
        #expect(proposal.write.deadlineUptimeNanoseconds == 400_000_000_000)
    }

    @Test("pane close preserves its sibling and original restore anchor")
    func paneClosePreservesSibling() throws {
        let first = makePane(id: UUIDv7.generate())
        let second = makePane(id: UUIDv7.generate())
        let tab = makeTab(paneIds: [first.id, second.id], activePaneId: first.id)
        let original = WorkspaceSQLiteSnapshot(id: UUIDv7.generate(), panes: [first, second], tabs: [tab])

        let proposal = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: original), tabID: tab.id, paneID: first.id, closeID: UUIDv7.generate(), time: time
        )

        #expect(proposal.bundle.workspace.panes.map(\.id) == [second.id])
        #expect(proposal.bundle.workspace.tabs.first?.activePaneIds == [second.id])
        guard case .pane(let snapshot) = proposal.snapshot else {
            Issue.record("Expected a pane close while its sibling remains")
            return
        }
        #expect(snapshot.anchorPaneID == second.id)
        #expect(snapshot.tabID == tab.id)
    }

    @Test("closing the last main pane produces one tab undo entry")
    func lastPaneCloseProducesTabUndo() throws {
        let pane = makePane(id: UUIDv7.generate())
        let tab = Tab(id: UUIDv7.generate(), paneId: pane.id)
        let original = WorkspaceSQLiteSnapshot(id: UUIDv7.generate(), panes: [pane], tabs: [tab])
        let proposal = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: original), tabID: tab.id, paneID: pane.id, closeID: UUIDv7.generate(), time: time
        )
        #expect(proposal.snapshot.kind == .tab)
        #expect(proposal.bundle.workspace.tabs.isEmpty)
        #expect(proposal.bundle.workspace.panes.isEmpty)
    }
}
