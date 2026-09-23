import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC request schemas")
struct IPCRequestSchemaTests {
    @Test("UI presentation names its owning window instead of borrowing focus")
    func presentationRequiresExplicitWindowAndCorrelation() throws {
        let windowId = UUIDv7.generate()
        let correlationId = UUIDv7.generate()
        let commandBarData = Data(
            """
            {"workspaceWindowId":"\(windowId.uuidString)","scope":"commands","correlationId":"\(correlationId.uuidString)"}
            """.utf8
        )
        let commandBar = try IPCCommandBarOpenParams.ipcSchema().decode(
            IPCCommandBarOpenParams.self, from: commandBarData
        )
        #expect(commandBar.workspaceWindowId == windowId)
        #expect(commandBar.correlationId == correlationId)
        let arrangementsData = Data(
            """
            {"workspaceWindowId":"\(windowId.uuidString)","targetPaneHandle":"self","correlationId":"\(correlationId.uuidString)"}
            """.utf8
        )
        let arrangements = try IPCArrangementsOpenParams.ipcSchema().decode(
            IPCArrangementsOpenParams.self, from: arrangementsData
        )
        #expect(arrangements.workspaceWindowId == windowId)
        #expect(arrangements.targetPaneHandle == "self")
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandBarOpenParams.ipcSchema().normalize(
                Data(#"{"scope":"commands","correlationId":"01941f29-7c00-7000-8000-000000000001"}"#.utf8)
            )
        }
    }

    @Test("Bridge search schema preserves the existing UTF-16 bound and default mode")
    func bridgeSearchBoundAndDefault() throws {
        let schema = try IPCBridgeFileTreeSearchParams.ipcSchema()
        let correlationId = UUIDv7.generate()
        let admitted = IPCBridgeFileTreeSearchParams(
            handle: "self", searchText: String(repeating: "🙂", count: 2048), correlationId: correlationId
        )
        _ = try schema.normalize(JSONEncoder().encode(admitted))
        let rejected = IPCBridgeFileTreeSearchParams(
            handle: "self", searchText: String(repeating: "🙂", count: 2049), correlationId: correlationId
        )
        do {
            _ = try schema.normalize(JSONEncoder().encode(rejected))
            Issue.record("The schema must enforce the existing UTF-16 limit before typed decoding")
        } catch let failure as IPCSchemaValidationError {
            #expect(failure.fieldPath == "$.searchText")
            #expect(failure.reason == .outOfBounds)
        }
        let missingMode = """
            {"handle":"self","searchText":"café","correlationId":"\(correlationId.uuidString)"}
            """
        let decoded = try schema.decode(IPCBridgeFileTreeSearchParams.self, from: Data(missingMode.utf8))
        #expect(decoded.searchMode == .text)
        let discoveredSchema = try JSONDecoder().decode(IPCJSONSchema.self, from: schema.jsonSchemaData())
        #expect(throws: IPCSchemaValidationError.self) {
            try discoveredSchema.normalize(JSONEncoder().encode(rejected))
        }
    }

    @Test("pane mutation admits only pane selectors and requires wire correlation")
    func paneMutationSelectorsAndCorrelation() throws {
        let correlationId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let schema = try IPCPaneSplitParams.ipcSchema()
        for handle in ["self", paneId.uuidString, "pane:2"] {
            let parameters = IPCPaneSplitParams(handle: handle, direction: .right, correlationId: correlationId)
            let decoded = try schema.decode(IPCPaneSplitParams.self, from: JSONEncoder().encode(parameters))
            #expect(decoded == parameters)
        }
        for handle in ["window:2", "workspace:2", "pane:0", "pane:-1", "pane:\(paneId.uuidString)"] {
            let parameters = IPCPaneSplitParams(handle: handle, direction: .right, correlationId: correlationId)
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.decode(IPCPaneSplitParams.self, from: JSONEncoder().encode(parameters))
            }
        }
        for json in [
            #"{"handle":"self","direction":"right"}"#,
            #"{"handle":"self","direction":"right","correlationId":null}"#,
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.decode(IPCPaneSplitParams.self, from: Data(json.utf8))
            }
        }
    }

    @Test("Bridge filter request uses its exact typed alternative and preserves private search text")
    func bridgeRequestAlternativesAndText() throws {
        let correlationId = UUIDv7.generate()
        let parameters = IPCBridgeFileTreeSetFilterParams(
            handle: "self",
            candidate: .review(gitStatusFilter: .modified, categoryFilter: .source, showBinary: false, showLarge: true),
            correlationId: correlationId
        )
        let schema = try IPCBridgeFileTreeSetFilterParams.ipcSchema()
        #expect(
            try schema.decode(IPCBridgeFileTreeSetFilterParams.self, from: JSONEncoder().encode(parameters))
                == parameters
        )
        let mixed = """
            {"handle":"self","correlationId":"\(correlationId.uuidString)",
             "candidate":{"surface":"files","categoryFilter":"source","showBinary":false}}
            """
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(mixed.utf8))
        }

        let search = IPCBridgeFileTreeSearchParams(
            handle: "self", searchText: "λ café\n第二行", correlationId: correlationId
        )
        #expect(
            try IPCBridgeFileTreeSearchParams.ipcSchema().decode(
                IPCBridgeFileTreeSearchParams.self, from: JSONEncoder().encode(search)
            ) == search
        )
    }
}
