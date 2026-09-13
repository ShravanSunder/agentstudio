import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC shared wire contracts")
struct IPCSharedWireContractsTests {
    @Test("empty parameters reject unknown fields before typed decoding")
    func emptyParametersRejectUnknownFields() throws {
        let contract = try makeContract(IPCEmptyParams.self, IPCSystemPingResult.self)
        #expect(try contract.decodeParameters(from: Data("{}".utf8)) == IPCEmptyParams())
        #expect(throws: IPCSchemaValidationError.self) {
            try contract.decodeParameters(from: Data(#"{"ignored":true}"#.utf8))
        }
    }

    @Test("pane selectors accept only self, UUID, and positive pane ordinals")
    func paneSelectorsUseTheSharedVocabulary() throws {
        let contract = try makeContract(IPCPaneSelectorParams.self, IPCPaneFocusResult.self)
        let paneId = UUIDv7.generate()

        for handle in ["self", paneId.uuidString, "pane:3"] {
            let data = try JSONEncoder().encode(["handle": handle])
            #expect(try contract.decodeParameters(from: data).handle == handle)
        }
        for handle in ["pane:0", "pane:-1", "workspace:2", "focused", ""] {
            let data = try JSONEncoder().encode(["handle": handle])
            #expect(throws: IPCSchemaValidationError.self) {
                try contract.decodeParameters(from: data)
            }
        }
    }

    @Test("pane controls require a non-null UUID correlation")
    func paneControlsRequireCorrelation() throws {
        let contract = try makeContract(IPCPaneControlParams.self, IPCPaneFocusResult.self)
        let correlationId = UUIDv7.generate()
        let valid = try contract.decodeParameters(
            from: encodedObject([
                "handle": "self",
                "correlationId": correlationId.uuidString,
            ])
        )

        #expect(valid == IPCPaneControlParams(handle: "self", correlationId: correlationId))
        for invalid in [
            Data(#"{"handle":"self"}"#.utf8),
            Data(#"{"handle":"self","correlationId":null}"#.utf8),
            Data(#"{"handle":"self","correlationId":"not-a-uuid"}"#.utf8),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try contract.decodeParameters(from: invalid)
            }
        }
    }

    @Test("terminal input preserves exact Unicode and newlines with required correlation")
    func terminalInputPreservesExactText() throws {
        let contract = try makeContract(IPCTerminalSendParams.self, IPCTerminalSendInputResult.self)
        let correlationId = UUIDv7.generate()
        let exactInput = "printf 'héllo 👋'\nsecond line\n"
        let parameters = IPCTerminalSendParams(
            handle: "self",
            input: exactInput,
            correlationId: correlationId
        )
        let result = IPCTerminalSendInputResult(
            paneId: UUIDv7.generate(),
            commandId: UUIDv7.generate(),
            correlationId: correlationId,
            disposition: .accepted,
            queuePosition: nil
        )

        try contract.validateExample(parameters: parameters, result: result)
        let decoded = try contract.decodeParameters(from: JSONEncoder().encode(parameters))
        #expect(decoded.input == exactInput)
        #expect(decoded.correlationId == correlationId)
        #expect(throws: IPCSchemaValidationError.self) {
            try contract.decodeParameters(
                from: encodedObject(["handle": "self", "input": exactInput])
            )
        }
    }

    @Test("terminal wait rejects negative and non-finite seconds and invalid sequences")
    func terminalWaitValidatesNumericBounds() throws {
        let contract = try makeContract(IPCTerminalWaitParams.self, IPCTerminalWaitResult.self)
        let valid = try contract.decodeParameters(
            from: Data(
                #"{"handle":"self","condition":"titleChanged","timeoutSeconds":0.25,"afterSequence":7}"#.utf8
            )
        )
        #expect(valid.timeoutSeconds == 0.25)
        #expect(valid.afterSequence == 7)

        for invalid in [
            Data(#"{"handle":"self","condition":"titleChanged","timeoutSeconds":-0.1}"#.utf8),
            Data(#"{"handle":"self","condition":"titleChanged","timeoutSeconds":1e9999}"#.utf8),
            Data(#"{"handle":"self","condition":"titleChanged","timeoutSeconds":1,"afterSequence":-1}"#.utf8),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try contract.decodeParameters(from: invalid)
            }
        }
    }

    @Test("auth login exposes only a non-empty token in its staged body")
    func authLoginHasNoPaneHintCompatibilityField() throws {
        let contract = try makeContract(IPCAuthLoginParams.self, IPCAuthStatusResult.self)
        #expect(
            try contract.decodeParameters(from: Data(#"{"token":"secret"}"#.utf8))
                == IPCAuthLoginParams(token: "secret")
        )
        #expect(throws: IPCSchemaValidationError.self) {
            try contract.decodeParameters(from: Data(#"{"token":"secret","paneHint":"pane:1"}"#.utf8))
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try contract.decodeParameters(from: Data(#"{"token":""}"#.utf8))
        }
    }

    @Test("auth status alternatives reject contradictory or incomplete principal fields")
    func authStatusUsesExactAlternatives() throws {
        let contract = try makeContract(IPCEmptyParams.self, IPCAuthStatusResult.self)
        let principalId = UUIDv7.generate()
        let runtimeId = UUIDv7.generate()
        let authenticated = IPCAuthStatusResult.authenticated(
            principalId: principalId,
            runtimeId: runtimeId,
            accessMode: .agentStudioOnly
        )

        try contract.validateExample(parameters: IPCEmptyParams(), result: .unauthenticated)
        try contract.validateExample(parameters: IPCEmptyParams(), result: authenticated)
        #expect(
            try JSONDecoder().decode(
                IPCAuthStatusResult.self,
                from: contract.encodeResult(authenticated)
            ) == authenticated
        )
        for invalid in [
            try encodedObject([
                "authenticated": false,
                "principalId": principalId.uuidString,
                "runtimeId": runtimeId.uuidString,
                "accessMode": "agentStudioOnly",
            ]),
            Data(#"{"authenticated":true}"#.utf8),
            try encodedObject([
                "authenticated": true,
                "principalId": principalId.uuidString,
                "runtimeId": runtimeId.uuidString,
                "accessMode": "future-mode",
            ]),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try IPCAuthStatusResult.ipcSchema().normalize(invalid)
            }
        }
    }

    @Test("ping and unsubscribe results enforce literal true flags")
    func literalSuccessFlagsCannotMasqueradeAsFailure() throws {
        let runtimeId = UUIDv7.generate()
        let subscriptionId = UUIDv7.generate()
        let pingContract = try makeContract(IPCEmptyParams.self, IPCSystemPingResult.self)
        let unsubscribeContract = try makeContract(
            IPCEventsUnsubscribeParams.self,
            IPCEventsUnsubscribeResult.self
        )

        try pingContract.validateExample(
            parameters: IPCEmptyParams(),
            result: IPCSystemPingResult(runtimeId: runtimeId)
        )
        try unsubscribeContract.validateExample(
            parameters: IPCEventsUnsubscribeParams(
                subscriptionId: subscriptionId,
                correlationId: UUIDv7.generate()
            ),
            result: IPCEventsUnsubscribeResult(subscriptionId: subscriptionId)
        )
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCSystemPingResult.ipcSchema().normalize(
                encodedObject(["ok": false, "runtimeId": runtimeId.uuidString])
            )
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCEventsUnsubscribeResult.ipcSchema().normalize(
                encodedObject(["unsubscribed": false, "subscriptionId": subscriptionId.uuidString])
            )
        }
    }

    @Test("event subscription mutations require correlation and non-empty event names")
    func eventSubscriptionParametersAreTypedMutations() throws {
        let subscribeContract = try makeContract(
            IPCEventsSubscribeParams.self,
            IPCEventSubscriptionResult.self
        )
        let unsubscribeContract = try makeContract(
            IPCEventsUnsubscribeParams.self,
            IPCEventsUnsubscribeResult.self
        )
        let correlationId = UUIDv7.generate()
        let subscriptionId = UUIDv7.generate()

        #expect(
            try subscribeContract.decodeParameters(
                from: encodedObject([
                    "eventNames": ["terminal.commandFinished"],
                    "correlationId": correlationId.uuidString,
                ])
            )
                == IPCEventsSubscribeParams(
                    eventNames: [.terminalCommandFinished],
                    correlationId: correlationId
                )
        )
        #expect(
            try unsubscribeContract.decodeParameters(
                from: encodedObject([
                    "subscriptionId": subscriptionId.uuidString,
                    "correlationId": correlationId.uuidString,
                ])
            )
                == IPCEventsUnsubscribeParams(
                    subscriptionId: subscriptionId,
                    correlationId: correlationId
                )
        )
        for invalid in [
            try encodedObject(["eventNames": [String](), "correlationId": correlationId.uuidString]),
            try encodedObject(["eventNames": ["future.event"], "correlationId": correlationId.uuidString]),
            try encodedObject(["eventNames": ["terminal.commandFinished"]]),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try subscribeContract.decodeParameters(from: invalid)
            }
        }
    }

    private func makeContract<Parameters: IPCSchemaProviding, Result: IPCSchemaProviding>(
        _: Parameters.Type,
        _: Result.Type
    ) throws -> IPCMethodContract<Parameters, Result> {
        try IPCMethodContract(
            parameterSchema: Parameters.ipcSchema(),
            resultSchema: Result.ipcSchema()
        )
    }

    private func encodedObject(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
