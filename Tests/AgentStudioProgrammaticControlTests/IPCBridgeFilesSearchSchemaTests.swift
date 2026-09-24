import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC Bridge Files search schema")
struct IPCBridgeFilesSearchSchemaTests {
    @Test("defaults search every member and opened document with the text matcher")
    func defaultsCoverTheWholeCollection() throws {
        // Arrange
        let schema = try IPCBridgeFilesSearchParams.ipcSchema()

        // Act
        let decoded = try schema.decode(
            IPCBridgeFilesSearchParams.self,
            from: Data(#"{"handle":"self","searchText":"plan"}"#.utf8)
        )

        // Assert
        #expect(
            decoded
                == IPCBridgeFilesSearchParams(
                    handle: "self",
                    searchText: "plan",
                    searchMode: .text,
                    scope: .all,
                    worktreeId: nil,
                    limit: IPCBridgeFilesSearchParams.defaultLimit
                )
        )
    }

    @Test("the member scope requires its worktree and no other scope accepts one")
    func memberScopeOwnsTheWorktree() throws {
        // Arrange
        let schema = try IPCBridgeFilesSearchParams.ipcSchema()
        let worktreeId = UUIDv7.generate()

        // Act
        let member = try schema.decode(
            IPCBridgeFilesSearchParams.self,
            from: Data(
                #"{"handle":"self","searchText":"","scope":"member","worktreeId":"\#(worktreeId.uuidString)"}"#
                    .utf8)
        )

        // Assert
        #expect(member.scope == .member)
        #expect(member.worktreeId == worktreeId)
        for json in [
            #"{"handle":"self","searchText":"","scope":"member"}"#,
            #"{"handle":"self","searchText":"","scope":"all","worktreeId":"\#(worktreeId.uuidString)"}"#,
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.decode(IPCBridgeFilesSearchParams.self, from: Data(json.utf8))
            }
        }
    }

    @Test("the limit is bounded by the collection worker's answer size")
    func limitIsBounded() throws {
        // Arrange
        let schema = try IPCBridgeFilesSearchParams.ipcSchema()

        // Act / Assert
        for limit in [0, IPCBridgeFilesSearchParams.maximumLimit + 1] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.decode(
                    IPCBridgeFilesSearchParams.self,
                    from: Data(#"{"handle":"self","searchText":"","limit":\#(limit)}"#.utf8)
                )
            }
        }
        let maximum = try schema.decode(
            IPCBridgeFilesSearchParams.self,
            from: Data(
                #"{"handle":"self","searchText":"","limit":\#(IPCBridgeFilesSearchParams.maximumLimit)}"#.utf8)
        )
        #expect(maximum.limit == IPCBridgeFilesSearchParams.maximumLimit)
    }

    @Test("an unavailable result omits matches' optional fields and round-trips its schema")
    func unavailableResultMatchesSchema() throws {
        // Arrange
        let result = IPCBridgeFilesSearchResult(
            paneId: UUIDv7.generate(),
            status: .unavailable,
            reason: .notMounted
        )

        // Act
        let normalized = try IPCBridgeFilesSearchResult.ipcSchema().normalize(JSONEncoder().encode(result))
        let decoded = try JSONDecoder().decode(IPCBridgeFilesSearchResult.self, from: normalized)

        // Assert
        #expect(decoded == result)
    }
}
