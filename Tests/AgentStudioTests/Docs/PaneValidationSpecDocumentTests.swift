import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneValidationSpecDocumentTests {
    @Test("architecture README indexes pane validation spec")
    func architectureReadmeIndexesPaneValidationSpec() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let readmeURL = projectRoot.appendingPathComponent("docs/architecture/README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        #expect(readme.contains("Pane Validation Spec"))
        #expect(readme.contains("pane_validation_spec.md"))
    }

    @Test("pane validation spec contains required reference sections")
    func paneValidationSpecContainsRequiredSections() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let specURL = projectRoot.appendingPathComponent("docs/architecture/pane_validation_spec.md")
        let spec = try String(contentsOf: specURL, encoding: .utf8)

        #expect(spec.contains("## Validator Ownership Table"))
        #expect(spec.contains("## Movement Matrix"))
        #expect(spec.contains("## Management-Mode Drawer Modal State Machine"))
        #expect(spec.contains("## Preview Commit Parity Contract"))
        #expect(spec.contains("```text"))
    }
}
