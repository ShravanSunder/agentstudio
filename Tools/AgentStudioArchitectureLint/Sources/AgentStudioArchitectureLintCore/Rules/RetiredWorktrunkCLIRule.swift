import SwiftSyntax

struct RetiredWorktrunkCLIRule: ArchitectureRule {
    let id = "agentstudio_retired_worktrunk_cli"
    let severity = ArchitectureSeverity.error
    let message = "The retired Worktrunk and production worktree CLI integration must not be reintroduced"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        guard
            path.contains("/Sources/AgentStudio/")
                || path.contains("/Tests/AgentStudioTests/")
        else {
            return []
        }

        let visitor = RetiredWorktrunkCLIVisitor(
            isProductSource: path.contains("/Sources/AgentStudio/")
        )
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class RetiredWorktrunkCLIVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    private let isProductSource: Bool

    init(isProductSource: Bool) {
        self.isProductSource = isProductSource
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: IdentifierTypeSyntax) {
        validateRetiredName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        validateRetiredName(node.baseName.text, position: node.baseName.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: EnumCaseElementSyntax) {
        let name = node.name.text
        if name == "checkWorktrunkDependency" {
            violations.append(
                ArchitectureViolation(
                    position: node.name.positionAfterSkippingLeadingTrivia,
                    message: "Remove the retired Worktrunk startup dependency phase"
                )
            )
            return
        }
        validateRetiredName(name, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard isProductSource else {
            return
        }
        for argument in node.arguments where argument.label?.text == "command" {
            guard let literal = argument.expression.as(StringLiteralExprSyntax.self) else {
                continue
            }
            let command = literal.segments.description
            guard command == "wt" || command == "git" else {
                continue
            }
            violations.append(
                ArchitectureViolation(
                    position: literal.positionAfterSkippingLeadingTrivia,
                    message: "Remove the production \(command) CLI fallback; use AgentStudioGit"
                )
            )
        }
    }

    private func validateRetiredName(_ name: String, position: AbsolutePosition) {
        if name == "checkWorktrunkDependency" {
            violations.append(
                ArchitectureViolation(
                    position: position,
                    message: "Remove the retired Worktrunk startup dependency phase"
                )
            )
        } else if name.localizedCaseInsensitiveContains("worktrunk") {
            violations.append(
                ArchitectureViolation(
                    position: position,
                    message: "Remove the retired Worktrunk integration"
                )
            )
        }
    }
}
