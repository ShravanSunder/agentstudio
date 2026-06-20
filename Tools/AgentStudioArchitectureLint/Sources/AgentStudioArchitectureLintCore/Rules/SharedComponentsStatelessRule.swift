import SwiftSyntax

struct SharedComponentsStatelessRule: ArchitectureRule {
    let id = "agentstudio_shared_components_are_stateless"
    let severity = ArchitectureSeverity.error
    let message =
        "SharedComponents must render from explicit inputs without atoms or global-store access"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.normalizedPath.contains("/Sources/AgentStudio/SharedComponents/") else {
            return []
        }

        let visitor = SharedComponentStateVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class SharedComponentStateVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let deniedAttributes = Set(["Atom", "StateObject", "EnvironmentObject"])
    private let deniedReferences = Set(["AtomReader", "AtomScope", "AtomRegistry", "withTestAtomRegistry"])
    private let deniedTypeSuffixes = ["Atom", "Store"]

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: AttributeSyntax) {
        let attributeName = node.attributeName.trimmedDescription
        if attributeName == "Environment" && isStoreLikeEnvironmentRead(node) {
            violations.append(
                ArchitectureViolation(
                    position: node.positionAfterSkippingLeadingTrivia,
                    message: "SharedComponents must not resolve global state through environment values"
                )
            )
            return
        }

        guard deniedAttributes.contains(attributeName) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "SharedComponents must not own atom/global observable state"
            )
        )
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard node.baseName.text == "atom" || deniedReferences.contains(node.baseName.text) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "SharedComponents must not read atoms directly"
            )
        )
    }

    override func visitPost(_ node: IdentifierTypeSyntax) {
        let typeName = node.name.text
        guard deniedReferences.contains(typeName) || deniedTypeSuffixes.contains(where: typeName.hasSuffix) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "SharedComponents must not depend on atom or store types"
            )
        )
    }

    private func isStoreLikeEnvironmentRead(_ node: AttributeSyntax) -> Bool {
        let description = node.trimmedDescription.lowercased()
        return description.contains("atom") || description.contains("store")
            || description.contains("registry")
    }
}
