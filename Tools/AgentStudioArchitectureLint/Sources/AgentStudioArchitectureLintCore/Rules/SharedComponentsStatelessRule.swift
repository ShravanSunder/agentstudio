import SwiftSyntax

struct SharedComponentsStatelessRule: ArchitectureRule {
    let id = "agentstudio_shared_components_are_stateless"
    let severity = ArchitectureSeverity.error
    let message =
        "SharedComponents must render from values, bindings, and closures without atom subscriptions or observable owners"

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
    private let deniedAttributes = Set([
        "Atom", "Observable", "ObservedObject", "State", "StateObject", "EnvironmentObject",
    ])
    private let deniedReferences = Set(["AtomReader", "AtomScope", "withTestAtomRegistry"])

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: AttributeSyntax) {
        let attributeName = node.attributeName.trimmedDescription
        guard deniedAttributes.contains(attributeName) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "SharedComponents must not own state or subscribe to atoms/object wrappers"
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
}
