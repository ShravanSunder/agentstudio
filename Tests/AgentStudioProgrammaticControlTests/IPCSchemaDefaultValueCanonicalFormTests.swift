import Foundation
import Testing

@testable import AgentStudioProgrammaticControl

/// A defaulted field's bytes are compared verbatim, and one side of that
/// comparison has always been through a wire round trip. They therefore have to
/// be written in the one canonical form, or a schema composed locally and the
/// same schema read back from the catalog disagree over escaping alone.
@Suite("IPC schema default value canonical form")
struct IPCSchemaDefaultValueCanonicalFormTests {
    @Test("a defaulted value survives a schema round trip when it contains slashes")
    func defaultedValueSurvivesRoundTripWithSlashes() throws {
        let field = IPCObjectField(
            name: "url",
            description: "Webview URL; omission opens GitHub",
            schema: .string(),
            presence: try .defaulted("https://github.com")
        )
        let built = IPCJSONSchema.object(fields: [
            IPCObjectField(name: "kind", description: "Variant", schema: .string()),
            field,
        ])

        let decoded = try JSONDecoder().decode(
            IPCJSONSchema.self, from: try JSONEncoder().encode(built))

        #expect(built == decoded)
    }

    @Test("the shipped webview argument schema survives a round trip")
    func webviewArgumentSchemaSurvivesRoundTrip() throws {
        // The one command in the catalog with a defaulted URL argument, and the
        // one whose descriptor round trip broke discovery for all 146.
        let built = try IPCCommandArgumentVariant.webview.schema

        let decoded = try JSONDecoder().decode(
            IPCJSONSchema.self, from: try JSONEncoder().encode(built))

        #expect(built == decoded)
    }
}
