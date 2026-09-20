import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC typed command execution contracts")
struct IPCCommandExecutionContractTests {
    @Test("request preserves open command identity, required correlation, and role arguments")
    func requestRoundTripsOpenIdentityAndTypedArguments() throws {
        let unknownCommandId = IPCCommandIdentifier(rawValue: "newer.command.identity")
        let arguments = IPCCommandArguments.pane(
            IPCPaneCommandArguments(
                workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                paneSelector: try IPCCommandArgumentsTestFixtures.paneSelector("pane:3")
            )
        )
        let request = IPCCommandExecutionContractTestFixtures.request(
            commandId: unknownCommandId,
            arguments: arguments
        )
        let schema = try IPCCommandExecutionRequest.ipcSchema(allowing: [.pane])

        let decoded = try schema.decode(
            IPCCommandExecutionRequest.self,
            from: JSONEncoder().encode(request)
        )

        #expect(decoded == request)
        #expect(decoded.commandId == unknownCommandId)
        #expect(decoded.correlationId == IPCCommandExecutionContractTestFixtures.correlationId)
        #expect(decoded.arguments == arguments)
    }

    @Test("request schema requires correlation and rejects unknown envelope fields")
    func requestSchemaIsStrictAndRequiresCorrelation() throws {
        let schema = try IPCCommandExecutionRequest.ipcSchema(allowing: [.noArguments])
        let commandId = IPCCommandExecutionContractTestFixtures.commandId.rawValue
        let correlationId = IPCCommandExecutionContractTestFixtures.correlationId.uuidString

        for invalid in [
            try IPCCommandExecutionContractTestFixtures.encodedObject([
                "commandId": commandId,
                "arguments": ["kind": "noArguments"],
            ]),
            try IPCCommandExecutionContractTestFixtures.encodedObject([
                "commandId": commandId,
                "correlationId": correlationId,
                "arguments": ["kind": "noArguments"],
                "targetHandle": "self",
            ]),
            try IPCCommandExecutionContractTestFixtures.encodedObject([
                "commandId": commandId,
                "correlationId": correlationId,
                "arguments": ["kind": "noArguments"],
                "argumentsContainOnlyStrings": true,
            ]),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.normalize(invalid)
            }
        }
    }

    @Test("request schema accepts unknown nonempty ids and rejects empty ids")
    func requestSchemaKeepsVersionSkewAtLookupBoundary() throws {
        let schema = try IPCCommandExecutionRequest.ipcSchema(allowing: [.noArguments])
        let correlationId = IPCCommandExecutionContractTestFixtures.correlationId.uuidString

        _ = try schema.decode(
            IPCCommandExecutionRequest.self,
            from: try IPCCommandExecutionContractTestFixtures.encodedObject([
                "commandId": "command.from.a.newer.app",
                "correlationId": correlationId,
                "arguments": ["kind": "noArguments"],
            ])
        )
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(
                IPCCommandExecutionContractTestFixtures.encodedObject([
                    "commandId": "",
                    "correlationId": correlationId,
                    "arguments": ["kind": "noArguments"],
                ])
            )
        }
    }

    @Test("request schema admits only the selected argument variants")
    func requestSchemaRestrictsArgumentVariants() throws {
        let paneRequest = IPCCommandExecutionContractTestFixtures.request(
            arguments: .pane(
                IPCPaneCommandArguments(
                    workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                    paneSelector: try IPCCommandArgumentsTestFixtures.paneSelector("self")
                )
            )
        )
        let paneData = try JSONEncoder().encode(paneRequest)

        #expect(
            try IPCCommandExecutionRequest.ipcSchema(allowing: [.pane])
                .decode(IPCCommandExecutionRequest.self, from: paneData) == paneRequest
        )
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionRequest.ipcSchema(allowing: [.repository])
                .normalize(paneData)
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionRequest.ipcSchema(allowing: [])
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionRequest.ipcSchema(allowing: [.pane, .pane])
        }
    }

    @Test("every result alternative owns one discriminant and preserves identity accessors")
    func everyResultAlternativeRoundTrips() throws {
        let results = IPCCommandExecutionContractTestFixtures.allResults()
        let variants = results.map(\.variant)
        let schema = try IPCCommandExecutionResult.ipcSchema(
            allowing: IPCCommandResultVariant.allCases
        )

        #expect(results.count == 6)
        #expect(variants == IPCCommandResultVariant.allCases)
        #expect(Set(variants).count == IPCCommandResultVariant.allCases.count)

        for result in results {
            let encoded = try JSONEncoder().encode(result)
            let object = try #require(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            #expect(object["kind"] as? String == result.variant.rawValue)
            #expect(result.commandId == IPCCommandExecutionContractTestFixtures.commandId)
            #expect(result.correlationId == IPCCommandExecutionContractTestFixtures.correlationId)
            #expect(
                try schema.decode(IPCCommandExecutionResult.self, from: encoded) == result
            )
            #expect(
                try IPCCommandExecutionResult.ipcSchema(allowing: [result.variant])
                    .decode(IPCCommandExecutionResult.self, from: encoded) == result
            )
        }
    }

    @Test("accepted result supports acknowledgment with or without a real operation receipt")
    func acceptedOperationIdentityIsOptionalAndTyped() throws {
        let withoutOperation = IPCCommandExecutionResult.accepted(
            IPCCommandAcceptedResult(
                commandId: IPCCommandExecutionContractTestFixtures.commandId,
                correlationId: IPCCommandExecutionContractTestFixtures.correlationId,
                operationId: nil
            )
        )
        let schema = try IPCCommandExecutionResult.ipcSchema(allowing: [.accepted])

        #expect(
            try schema.decode(
                IPCCommandExecutionResult.self,
                from: JSONEncoder().encode(withoutOperation)
            ) == withoutOperation
        )
        #expect(
            try schema.decode(
                IPCCommandExecutionResult.self,
                from: JSONEncoder().encode(
                    IPCCommandExecutionContractTestFixtures.allResults()[1]
                )
            ) == IPCCommandExecutionContractTestFixtures.allResults()[1]
        )
    }

    @Test("result schema rejects unknown fields and another allowed result kind")
    func resultSchemaIsStrictAndVariantRestricted() throws {
        let applied = IPCCommandExecutionContractTestFixtures.allResults()[0]
        let appliedData = try JSONEncoder().encode(applied)

        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionResult.ipcSchema(allowing: [.applied])
                .normalize(
                    IPCCommandExecutionContractTestFixtures.encodedObject([
                        "kind": "applied",
                        "commandId": IPCCommandExecutionContractTestFixtures.commandId.rawValue,
                    ])
                )
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionResult.ipcSchema(allowing: [.accepted])
                .normalize(appliedData)
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionResult.ipcSchema(allowing: [.applied])
                .normalize(
                    IPCCommandExecutionContractTestFixtures.encodedObject([
                        "kind": "applied",
                        "commandId": IPCCommandExecutionContractTestFixtures.commandId.rawValue,
                        "correlationId": IPCCommandExecutionContractTestFixtures.correlationId.uuidString,
                        "details": ["paneId": IPCCommandExecutionContractTestFixtures.appliedPaneId.uuidString],
                    ])
                )
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionResult.ipcSchema(allowing: [])
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandExecutionResult.ipcSchema(allowing: [.applied, .applied])
        }
    }

    @Test("partial result requires a typed applied effect and finite reason")
    func partialResultRejectsEmptyEffectsAndRawReasons() throws {
        let schema = try IPCCommandExecutionResult.ipcSchema(allowing: [.partial])
        let commandId = IPCCommandExecutionContractTestFixtures.commandId.rawValue
        let correlationId = IPCCommandExecutionContractTestFixtures.correlationId.uuidString

        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(
                IPCCommandExecutionContractTestFixtures.encodedObject([
                    "kind": "partial",
                    "commandId": commandId,
                    "correlationId": correlationId,
                    "appliedEffects": [],
                    "reason": "ownerRejectedRemainingEffects",
                ])
            )
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(
                IPCCommandExecutionContractTestFixtures.encodedObject([
                    "kind": "partial",
                    "commandId": commandId,
                    "correlationId": correlationId,
                    "appliedEffects": [
                        [
                            "kind": "pane",
                            "id": IPCCommandExecutionContractTestFixtures.appliedPaneId.uuidString,
                        ]
                    ],
                    "reason": "raw private owner error",
                ])
            )
        }
    }
}
