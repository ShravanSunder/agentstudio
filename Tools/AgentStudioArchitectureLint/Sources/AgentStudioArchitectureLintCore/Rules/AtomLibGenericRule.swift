import SwiftSyntax

struct AtomLibGenericRule: ArchitectureRule {
    let id = "agentstudio_atomlib_is_generic"
    let severity = ArchitectureSeverity.error
    let message = "Infrastructure/AtomLib must contain only generic atom primitives and helpers"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.normalizedPath.contains("/Sources/AgentStudio/Infrastructure/AtomLib/") else {
            return []
        }

        let visitor = AtomLibGenericVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class AtomLibGenericVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let productPrefixes = ["Workspace", "Repo", "Pane", "Tab", "Inbox", "Bridge", "Terminal", "CommandBar"]
    private let deniedNames = Set(["AtomRegistry", "RepoCacheAtom", "SessionRuntimeAtom", "WorkspaceStore"])

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: ImportDeclSyntax) {
        let importPath = node.path.map(\.name.text)
        guard let importedLayer = AgentStudioPathClassifier.importedLayer(importPath),
            importedLayer != "Infrastructure"
        else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "AtomLib must not import product layers"
            )
        )
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        let name = node.baseName.text
        guard deniedNames.contains(name) || productPrefixes.contains(where: { name.hasPrefix($0) }) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "AtomLib must not reference product-specific state or registry types"
            )
        )
    }
}
