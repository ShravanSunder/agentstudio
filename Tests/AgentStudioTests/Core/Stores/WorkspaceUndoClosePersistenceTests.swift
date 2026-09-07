import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Workspace durable close persistence")
struct WorkspaceUndoClosePersistenceTests {
    @Test("eleventh committed close evicts oldest and retires only unowned sessions", arguments: [true, false])
    func eleventhCloseEvictsOldestWithoutRetiringSharedSession(shareSession: Bool) throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUIDv7.generate()
        let sharedSessionID = ZmxSessionID.generateUUIDv7()
        let workspace = WorkspaceCoreRepository.WorkspaceRecord(
            id: workspaceID,
            name: "Durable undo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var closeIDs: [UUID] = []
        var sessionIDs: [ZmxSessionID] = []

        for index in 0..<11 {
            let closeID = UUIDv7.generate()
            closeIDs.append(closeID)
            let sessionID = shareSession ? sharedSessionID : ZmxSessionID.generateUUIDv7()
            sessionIDs.append(sessionID)
            let request = WorkspaceUndoCloseWrite(
                closeID: closeID,
                workspaceID: workspaceID,
                kind: .pane,
                closedAt: Date(timeIntervalSince1970: 100 + Double(index)),
                expiresAt: Date(timeIntervalSince1970: 400 + Double(index)),
                deadlineBootID: "boot-fixture",
                deadlineUptimeNanoseconds: Int64(400 + index) * 1_000_000_000,
                snapshotVersion: 1,
                snapshotPayload: Data("{}".utf8),
                members: [.init(paneID: UUIDv7.generate(), sessionID: sessionID)]
            )
            let receipt = try fixture.repository.replaceWorkspaceSnapshot(
                workspace: workspace,
                paneGraph: .init(panes: []),
                tabShells: [],
                tabGraph: .init(tabs: []),
                undoChange: .record(request)
            )
            if index == 10 {
                #expect(receipt?.availableCloseIDs.count == 10)
                #expect(receipt?.retiredCloses.map(\.closeID) == [closeIDs[0]])
            }
        }

        try fixture.databaseQueue.read { database in
            let available = try String.fetchAll(
                database,
                sql: "SELECT close_id FROM workspace_undo_close WHERE state = 'available' ORDER BY close_sequence"
            )
            #expect(available == closeIDs.dropFirst().map(\.uuidString))
            #expect(
                try String.fetchOne(
                    database,
                    sql: "SELECT state FROM workspace_undo_close WHERE close_id = ?",
                    arguments: [closeIDs[0].uuidString]
                ) == "evicted"
            )
            #expect(
                try String.fetchOne(
                    database,
                    sql: "SELECT cleanup_state FROM workspace_terminal_session_ownership WHERE session_id = ?",
                    arguments: [sessionIDs[0].rawValue]
                ) == (shareSession ? "owned" : "pending")
            )
        }
    }

    @Test("failed undo insertion rolls back its workspace composition change")
    func failedUndoInsertionRollsBackComposition() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let workspace = WorkspaceCoreRepository.WorkspaceRecord(
            id: workspaceID,
            name: "Rollback",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try fixture.repository.upsertWorkspace(workspace)
        try fixture.insertPane(workspaceId: workspaceID, paneId: paneID, cwd: URL(filePath: "/tmp/undo-rollback"))
        let originalGraph = try fixture.repository.fetchPaneGraph(workspaceId: workspaceID)
        let request = WorkspaceUndoCloseWrite(
            closeID: UUIDv7.generate(),
            workspaceID: workspaceID,
            kind: .pane,
            closedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 400),
            deadlineBootID: "boot-fixture",
            deadlineUptimeNanoseconds: 400_000_000_000,
            snapshotVersion: 0,
            snapshotPayload: Data("{}".utf8),
            members: [.init(paneID: paneID, sessionID: nil)]
        )

        #expect(throws: DatabaseError.self) {
            try fixture.repository.replaceWorkspaceSnapshot(
                workspace: workspace,
                paneGraph: .init(panes: []),
                tabShells: [],
                tabGraph: .init(tabs: []),
                undoChange: .record(request)
            )
        }
        #expect(try fixture.repository.fetchPaneGraph(workspaceId: workspaceID) == originalGraph)
    }
}
