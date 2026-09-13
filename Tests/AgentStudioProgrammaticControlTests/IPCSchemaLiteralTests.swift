import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC catalog example literals")
struct IPCSchemaLiteralTests {
    @Test("structured literals accept only the documented JSON value")
    func structuredLiteralValidation() throws {
        let example = LiteralExample(operation: "example.read", items: ["α", "second\nline"])
        let schema = try IPCJSONSchema.literal(example)
        let encoded = try JSONEncoder().encode(example)
        _ = try schema.normalize(encoded)
        let reordered = Data(#"{"items":["α","second\nline"],"operation":"example.read"}"#.utf8)
        _ = try schema.normalize(reordered)
        for invalid in [
            Data(#"{"items":["α"],"operation":"example.read"}"#.utf8),
            Data(#"{"items":["α","second\nline"],"operation":"different"}"#.utf8),
            Data(#"{"items":["α","second\nline"],"operation":"example.read","extra":true}"#.utf8),
        ] {
            #expect(throws: IPCSchemaValidationError.self) { try schema.normalize(invalid) }
        }
        let discovered = try JSONDecoder().decode(IPCJSONSchema.self, from: schema.jsonSchemaData())
        #expect(discovered == schema)
        let projection = try #require(
            JSONSerialization.jsonObject(with: schema.jsonSchemaData()) as? [String: Any]
        )
        #expect(projection["const"] is [String: Any])
    }

    @Test("literal mismatch correction contains no example or caller text")
    func literalMismatchRemainsContentFree() throws {
        let schema = try IPCJSONSchema.literal(["private-example"])
        do {
            _ = try schema.normalize(Data(#"["private-caller"]"#.utf8))
            Issue.record("Expected a literal mismatch")
        } catch let error as IPCSchemaValidationError {
            let data = try JSONEncoder().encode(error)
            let correction = try #require(String(bytes: data, encoding: .utf8))
            #expect(!correction.contains("private"))
            #expect(error.reason == .invalidValue)
        }
    }
}

private struct LiteralExample: Codable, Sendable {
    let operation: String
    let items: [String]
}
