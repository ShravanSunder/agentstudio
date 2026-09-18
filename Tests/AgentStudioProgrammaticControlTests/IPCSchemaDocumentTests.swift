import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC catalog schema documents")
struct IPCSchemaDocumentTests {
    @Test("catalog schemas describe nested schemas without infinite expansion")
    func catalogSchemaSelfDescriptionIsFinite() throws {
        let descriptorSchema = IPCJSONSchema.object(fields: [
            .init(name: "name", description: "Open method name", schema: .string()),
            .init(name: "parameters", description: "Complete parameter schema", schema: .schemaDocument),
            .init(name: "result", description: "Complete result schema", schema: .schemaDocument),
        ])
        let descriptorData = try descriptorSchema.jsonSchemaData()
        #expect(descriptorData.count < 2048)
        let discoveredSchema = try JSONDecoder().decode(IPCJSONSchema.self, from: descriptorData)
        let value = SchemaDescriptorFixture(
            name: "example.catalog", parameters: descriptorSchema, result: descriptorSchema)
        let contract = try IPCMethodContract<SchemaDescriptorFixture, SchemaDescriptorFixture>(
            parameterSchema: discoveredSchema, resultSchema: discoveredSchema
        )
        let encoded = try contract.encodeResult(value)
        let decoded = try contract.decodeParameters(from: encoded)
        #expect(decoded.name == value.name)
        #expect(try decoded.parameters.jsonSchemaData() == descriptorData)
        #expect(try decoded.result.jsonSchemaData() == descriptorData)
    }

    @Test("the only schema reference is the fixed catalog meta-schema, with no resolver")
    func arbitrarySchemaReferencesAreRejected() throws {
        let schema = IPCJSONSchema.schemaDocument
        for json in [
            #"{"$ref":"https://private.invalid/schema"}"#,
            #"{"type":"string","unknown-private-key":"private-content"}"#,
            #"{"type":"integer","minimum":8,"maximum":3}"#,
            #"{"type":"string","minLength":3,"maxLength":1}"#,
        ] {
            do {
                _ = try schema.normalize(Data(json.utf8))
                Issue.record("Expected unsupported or contradictory schema to be rejected")
            } catch let failure as IPCSchemaValidationError {
                let correctionData = try JSONEncoder().encode(failure)
                let encodedFailure = try #require(String(bytes: correctionData, encoding: .utf8))
                #expect(!encodedFailure.contains("private"))
                #expect(failure.reason == .invalidDefinition)
            }
        }
        let selfDescription = try schema.jsonSchemaData()
        #expect(try schema.normalize(selfDescription) == selfDescription)
    }
}

private struct SchemaDescriptorFixture: Codable, Sendable {
    let name: String
    let parameters: IPCJSONSchema
    let result: IPCJSONSchema
}
