import Testing

@testable import AgentStudio

@Suite("Foundation extensions")
struct FoundationExtensionsTests {
    @Test("trimmedNonEmpty returns nil for nil and whitespace")
    func trimmedNonEmptyRejectsEmptyValues() {
        let missing: String? = nil
        let whitespace: String? = " \n\t "

        #expect(missing.trimmedNonEmpty == nil)
        #expect(whitespace.trimmedNonEmpty == nil)
    }

    @Test("trimmedNonEmpty returns trimmed content")
    func trimmedNonEmptyReturnsTrimmedContent() {
        let value: String? = "  AgentStudio \n"

        #expect(value.trimmedNonEmpty == "AgentStudio")
    }
}
