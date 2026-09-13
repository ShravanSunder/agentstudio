import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC typed JSON schema")
struct IPCJSONSchemaTests {
    @Test("object field order survives discovery without hiding contract differences")
    func objectFieldOrderIsNotContractMeaning() throws {
        let title = IPCObjectField(name: "title", description: "Title", schema: .string())
        let count = IPCObjectField(name: "count", description: "Count", schema: .integer(minimum: 1))
        let schema = IPCJSONSchema.object(fields: [title, count])
        #expect(schema == .object(fields: [count, title]))
        #expect(try JSONDecoder().decode(IPCJSONSchema.self, from: schema.jsonSchemaData()) == schema)
        #expect(schema != .object(fields: [title]))
        #expect(
            schema
                != .object(fields: [title, .init(name: "count", description: "Count", schema: .integer(minimum: 2))]))
        #expect(
            schema != .object(fields: [title, .optional("count", description: "Count", schema: .integer(minimum: 1))]))
    }

    @Test("boolean discriminators enforce their literal value in discovery and admission")
    func booleanDiscriminatorsUseLiteralValues() throws {
        for expected in [true, false] {
            let schema = IPCJSONSchema.booleanConstant(expected)
            _ = try schema.normalize(JSONEncoder().encode(expected))
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.normalize(JSONEncoder().encode(!expected))
            }
            let discovered = try JSONDecoder().decode(IPCJSONSchema.self, from: schema.jsonSchemaData())
            #expect(discovered == schema)
            #expect(throws: IPCSchemaValidationError.self) {
                try discovered.normalize(Data("null".utf8))
            }
        }
    }

    @Test("identifier patterns are advertised and enforced before typed decoding")
    func identifierPatternsMatchDiscovery() throws {
        let schema = IPCJSONSchema.string(pattern: "^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$")
        let identifier = String(repeating: "a", count: 40)
        _ = try schema.normalize(JSONEncoder().encode(identifier))
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(JSONEncoder().encode(String(repeating: "a", count: 41)))
        }
        let discovered = try JSONDecoder().decode(IPCJSONSchema.self, from: schema.jsonSchemaData())
        #expect(throws: IPCSchemaValidationError.self) {
            try discovered.normalize(JSONEncoder().encode(String(repeating: "z", count: 40)))
        }
    }

    @Test("typed method contracts reject fields that Codable would silently ignore")
    func typedContractRejectsIgnoredFields() throws {
        let contract = try IPCMethodContract<SchemaTextOnlyParameters, SchemaTextOnlyParameters>(
            parameterSchema: messageSchema(),
            resultSchema: .object(fields: [
                .init(name: "text", description: "Exact response text", schema: .string())
            ])
        )

        do {
            _ = try contract.decodeParameters(from: Data(#"{"text":"hello","priority":2}"#.utf8))
            Issue.record("A schema field was ignored by the Swift parameter type")
        } catch let failure as IPCSchemaValidationError {
            #expect(failure.fieldPath == "$.priority")
            #expect(failure.reason == .decodingMismatch)
        }
    }

    @Test("typed method examples and result encoding use the declared contract")
    func typedExamplesUseDeclaredContract() throws {
        let contract = try IPCMethodContract<SchemaMessageParameters, SchemaTextOnlyParameters>(
            parameterSchema: messageSchema(),
            resultSchema: .object(fields: [
                .init(name: "text", description: "Exact response text", schema: .string())
            ])
        )
        let parameters = SchemaMessageParameters(text: "hello", priority: 2, urgent: true)
        try contract.validateExample(parameters: parameters, result: .init(text: "saved"))
        let result = try contract.encodeResult(.init(text: "saved"))
        #expect(try JSONDecoder().decode(SchemaTextOnlyParameters.self, from: result).text == "saved")
    }

    @Test("discovered schemas retain defaults and validation when read by a client")
    func discoveredSchemaRoundTripPreservesBehavior() throws {
        let schema = try messageSchema()
        let discovered = try JSONDecoder().decode(IPCJSONSchema.self, from: schema.jsonSchemaData())
        let input = Data(#"{"text":"hello"}"#.utf8)
        #expect(try discovered.normalize(input) == schema.normalize(input))
        #expect(throws: IPCSchemaValidationError.self) {
            try discovered.normalize(Data(#"{"text":"hello","priority":4}"#.utf8))
        }
    }

    @Test("dictionary entries have typed values without echoing caller-owned keys")
    func dictionaryEntriesHaveTypedValues() throws {
        let schema = IPCJSONSchema.dictionary(values: .integer(minimum: 0))
        let decoded = try schema.decode([String: Int].self, from: Data(#"{"count":3}"#.utf8))
        #expect(decoded == ["count": 3])
        do {
            _ = try schema.normalize(Data(#"{"private caller key":"wrong type"}"#.utf8))
            Issue.record("Expected a typed dictionary error")
        } catch let failure as IPCSchemaValidationError {
            #expect(failure.fieldPath == "$.*")
            #expect(failure.reason == .wrongType)
        }
    }

    @Test("declared defaults are applied by the same schema that discovery exposes")
    func declaredDefaultsMatchDecoding() throws {
        let schema = try messageSchema()

        let parameters = try schema.decode(
            SchemaMessageParameters.self,
            from: Data(#"{"text":"hello"}"#.utf8)
        )

        #expect(parameters == SchemaMessageParameters(text: "hello", priority: 1, urgent: false))
        let projection = try JSONSerialization.jsonObject(with: schema.jsonSchemaData()) as? [String: Any]
        let properties = projection?["properties"] as? [String: [String: Any]]
        #expect(properties?["priority"]?["default"] as? Int == 1)
        #expect(properties?["urgent"]?["default"] as? Bool == false)
        #expect(projection?["required"] as? [String] == ["text"])
        #expect(projection?["additionalProperties"] as? Bool == false)
    }

    @Test("field errors identify the correction without echoing private input")
    func invalidInputDoesNotEnterCorrectionData() throws {
        let schema = try messageSchema()

        do {
            _ = try schema.decode(
                SchemaMessageParameters.self,
                from: Data(#"{"text":"private message","priority":"private value"}"#.utf8)
            )
            Issue.record("Expected an integer correction")
        } catch let failure as IPCSchemaValidationError {
            #expect(failure.fieldPath == "$.priority")
            #expect(failure.reason == .wrongType)
            let encodedCorrection = try JSONEncoder().encode(failure)
            let correction = try #require(String(bytes: encodedCorrection, encoding: .utf8))
            #expect(!correction.contains("private message"))
            #expect(!correction.contains("private value"))
        }
    }

    @Test("integers reject booleans, fractional values and out-of-range values")
    func scalarKindsAndBoundsAreEnforced() throws {
        let schema = try messageSchema()
        for invalidPriority in ["true", "1.5", "0", "4"] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.normalize(Data("{\"text\":\"hello\",\"priority\":\(invalidPriority)}".utf8))
            }
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(#"{"text":"hello","urgent":1}"#.utf8))
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(#"{"text":"hello","extra":"ignored?"}"#.utf8))
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(#"{"priority":1}"#.utf8))
        }
    }

    @Test("typed alternatives keep variant fields separate")
    func alternativesRejectMixedVariants() throws {
        let schema = IPCJSONSchema.oneOf([
            .object(fields: [
                .init(name: "kind", description: "Operation", schema: .string(allowedValues: ["message"])),
                .init(name: "text", description: "Private message", schema: .string()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "Operation", schema: .string(allowedValues: ["done"]))
            ]),
        ])

        _ = try schema.normalize(Data(#"{"kind":"message","text":"exact\ntext"}"#.utf8))
        _ = try schema.normalize(Data(#"{"kind":"done"}"#.utf8))
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(#"{"kind":"done","text":"not a done field"}"#.utf8))
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(#"{"kind":"future"}"#.utf8))
        }
    }

    @Test("array and nullable schemas retain nested correction paths")
    func nestedCollectionsPreserveFieldPaths() throws {
        let schema = IPCJSONSchema.object(fields: [
            .init(
                name: "values",
                description: "Optional numeric values",
                schema: .array(items: .oneOf([.integer(minimum: 1), .null]), maximumCount: 3)
            )
        ])
        _ = try schema.normalize(Data(#"{"values":[1,null,2]}"#.utf8))
        do {
            _ = try schema.normalize(Data(#"{"values":[1,"bad"]}"#.utf8))
            Issue.record("Expected a nested field correction")
        } catch let failure as IPCSchemaValidationError {
            #expect(failure.fieldPath == "$.values[1]")
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(Data(#"{"values":[1,2,3,4]}"#.utf8))
        }
    }

    private func messageSchema() throws -> IPCJSONSchema {
        try .object(fields: [
            .init(name: "text", description: "Exact private text", schema: .string(minimumLength: 1)),
            .init(
                name: "priority", description: "Bounded fixture priority", schema: .integer(minimum: 1, maximum: 3),
                presence: .defaulted(1)
            ),
            .init(name: "urgent", description: "Fixture switch", schema: .boolean, presence: .defaulted(false)),
        ])
    }
}

private struct SchemaMessageParameters: Codable, Equatable, Sendable {
    let text: String
    let priority: Int
    let urgent: Bool
}

private struct SchemaTextOnlyParameters: Codable, Equatable, Sendable {
    let text: String
}
