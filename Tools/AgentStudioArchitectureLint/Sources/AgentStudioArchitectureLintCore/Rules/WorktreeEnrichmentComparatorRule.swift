import SwiftSyntax

struct WorktreeEnrichmentComparatorRule: ArchitectureRule {
    let id = "agentstudio_worktree_enrichment_comparator"
    let severity = ArchitectureSeverity.error
    let message = "WorktreeEnrichment atom comparators must not use raw equality"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let visitor = WorktreeEnrichmentComparatorVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class WorktreeEnrichmentComparatorVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard node.trimmedDescription.contains("WorktreeEnrichment") else {
            return
        }

        for argument in node.arguments where argument.label?.text == "isContentEqual" {
            let expression = argument.expression.trimmedDescription
            if expression == "==" || expression.contains("==") {
                violations.append(
                    ArchitectureViolation(
                        position: argument.positionAfterSkippingLeadingTrivia,
                        message: "Use a measured WorktreeEnrichment comparator instead of raw equality"
                    )
                )
            }
        }
    }
}
