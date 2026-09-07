import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Workspace undo snapshot encoding")
struct WorkspaceUndoCloseSnapshotTests {
    @Test("tab undo payload preserves pane, session and arrangement identities")
    func tabPayloadPreservesIdentities() throws {
        let pane = makePane(id: UUIDv7.generate(), title: "Running command")
        let tab = Tab(id: UUIDv7.generate(), paneId: pane.id, name: "Work")
        let original = WorkspaceUndoCloseSnapshot.tab(tab: tab, panes: [pane], tabIndex: 3)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceUndoCloseSnapshot.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.panes.map(\.id) == [pane.id])
        #expect(decoded.panes.first?.terminalState?.zmxSessionID == pane.terminalState?.zmxSessionID)
    }

    @Test("pane undo payload preserves the original placement anchor")
    func panePayloadPreservesPlacement() throws {
        let pane = makePane(id: UUIDv7.generate())
        let original = WorkspaceUndoCloseSnapshot.pane(
            .init(
                pane: pane,
                drawerChildPanes: [],
                drawerViewsByArrangementID: [:],
                tabID: UUIDv7.generate(),
                anchorPaneID: UUIDv7.generate(),
                direction: .vertical
            )
        )

        let decoded = try JSONDecoder().decode(
            WorkspaceUndoCloseSnapshot.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }
}
