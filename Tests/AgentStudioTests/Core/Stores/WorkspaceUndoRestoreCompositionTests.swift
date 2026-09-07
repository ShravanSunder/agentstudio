import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Workspace undo restore composition")
struct WorkspaceUndoRestoreCompositionTests {
    private let time = WorkspaceUndoJournalTime(
        utc: Date(timeIntervalSince1970: 100), bootID: "boot-fixture", uptimeNanoseconds: 100_000_000_000
    )

    @Test("tab and sibling-pane restore preserve original identities", arguments: [true, false])
    func restoreOriginalIdentities(closeWholeTab: Bool) throws {
        let first = makePane(id: UUIDv7.generate())
        let sibling = makePane(id: UUIDv7.generate())
        let tab = makeTab(paneIds: [first.id, sibling.id], activePaneId: first.id)
        let source = WorkspaceSQLiteSaveBundle(
            workspace: .init(id: UUIDv7.generate(), panes: [first, sibling], tabs: [tab])
        )
        let close = try WorkspaceUndoComposition.prepareClose(
            in: source, tabID: tab.id, paneID: closeWholeTab ? nil : first.id,
            closeID: UUIDv7.generate(), time: time
        )
        let restored = try WorkspaceUndoComposition.prepareRestore(
            in: close.bundle, close: record(close), time: time
        )
        #expect(Set(restored.bundle.workspace.panes.map(\.id)) == [first.id, sibling.id])
        #expect(restored.bundle.workspace.tabs.map(\.id) == [tab.id])
        #expect(Set(restored.bundle.workspace.tabs[0].allPaneIds) == [first.id, sibling.id])
        #expect(
            restored.bundle.workspace.panes.first { $0.id == first.id }?.terminalState?.zmxSessionID
                == first.terminalState?.zmxSessionID)
        guard case .prepared = WorkspaceCompositionPreparer.prepare(restored.bundle.workspace) else {
            Issue.record("Restore must produce a valid persistable composition")
            return
        }
    }

    @Test("drawer undo restores both parent membership and a usable drawer layout")
    func restoreDrawerMembershipAndLayout() throws {
        var parent = makePane(id: UUIDv7.generate())
        var child = makePane(id: UUIDv7.generate())
        child.kind = .drawerChild(parentPaneId: parent.id)
        parent.withDrawer { $0.paneIds = [child.id] }
        let drawerID = try #require(parent.drawer?.drawerId)
        let initialTab = Tab(paneId: parent.id)
        var arrangements = initialTab.arrangements
        arrangements[0].drawerViews[drawerID] = DrawerView(
            layout: DrawerGridLayout(topRow: Layout(paneId: child.id))
        )
        let tab = Tab(
            id: initialTab.id, allPaneIds: [parent.id, child.id],
            arrangements: arrangements, activeArrangementId: initialTab.activeArrangementId)
        let close = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: .init(id: UUIDv7.generate(), panes: [parent, child], tabs: [tab])),
            tabID: tab.id, paneID: child.id, closeID: UUIDv7.generate(), time: time
        )
        let restored = try WorkspaceUndoComposition.prepareRestore(in: close.bundle, close: record(close), time: time)
        #expect(restored.bundle.workspace.panes.first { $0.id == parent.id }?.drawer?.paneIds == [child.id])
        #expect(restored.bundle.workspace.tabs[0].arrangements[0].drawerViews[drawerID]?.layout.paneIds == [child.id])
        guard case .prepared = WorkspaceCompositionPreparer.prepare(restored.bundle.workspace) else {
            Issue.record("Drawer restore must produce a valid persistable composition")
            return
        }
    }

    @Test("missing restore anchor rejects without modifying the source")
    func missingAnchorRejects() throws {
        let first = makePane(id: UUIDv7.generate())
        let sibling = makePane(id: UUIDv7.generate())
        let tab = makeTab(paneIds: [first.id, sibling.id], activePaneId: first.id)
        let close = try WorkspaceUndoComposition.prepareClose(
            in: .init(workspace: .init(id: UUIDv7.generate(), panes: [first, sibling], tabs: [tab])),
            tabID: tab.id, paneID: first.id, closeID: UUIDv7.generate(), time: time
        )
        let empty = WorkspaceSQLiteSaveBundle(workspace: .init(id: close.write.workspaceID))
        #expect(throws: WorkspaceUndoCompositionFailure.missingTarget) {
            try WorkspaceUndoComposition.prepareRestore(in: empty, close: record(close), time: time)
        }
        #expect(empty.workspace.panes.isEmpty)
    }

    private func record(_ close: WorkspaceUndoCloseProposal) -> WorkspaceUndoCloseRecord {
        .init(
            closeID: close.write.closeID, workspaceID: close.write.workspaceID, sequence: 1,
            closedAt: close.write.closedAt, expiresAt: close.write.expiresAt,
            deadlineBootID: close.write.deadlineBootID,
            deadlineUptimeNanoseconds: close.write.deadlineUptimeNanoseconds, snapshot: close.snapshot)
    }
}
