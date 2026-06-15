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
            if isRawWorktreeEquality(expression: argument.expression.trimmedDescription) {
                violations.append(
                    ArchitectureViolation(
                        position: argument.positionAfterSkippingLeadingTrivia,
                        message: "Use a measured WorktreeEnrichment comparator instead of raw equality"
                    )
                )
            }
        }
    }

    private func isRawWorktreeEquality(expression: String) -> Bool {
        let compact = expression.filter { !$0.isWhitespace }
        return compact == "=="
            || compact.contains("inlhs==rhs")
            || compact.contains("inrhs==lhs")
            || compact.contains("in$0==$1")
            || compact.contains("in$1==$0")
    }
}
