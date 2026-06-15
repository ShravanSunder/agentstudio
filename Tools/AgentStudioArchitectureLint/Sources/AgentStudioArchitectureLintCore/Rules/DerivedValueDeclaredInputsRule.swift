import SwiftSyntax

struct DerivedValueDeclaredInputsRule: ArchitectureRule {
    let id = "agentstudio_derived_value_declared_inputs"
    let severity = ArchitectureSeverity.error
    let message = "DerivedValue compute closures must use declared input revisions instead of reading atoms directly"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let helperCollector = DerivedValueHiddenInputHelperCollector()
        helperCollector.walk(context.sourceFile)

        let visitor = DerivedValueInputVisitor(hiddenInputHelperNames: helperCollector.hiddenInputHelperNames)
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class DerivedValueInputVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let hiddenInputHelperNames: Set<String>

    init(hiddenInputHelperNames: Set<String>, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.hiddenInputHelperNames = hiddenInputHelperNames
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard node.calledExpression.trimmedDescription.contains("DerivedValue") else {
            return
        }

        let closures =
            node.arguments.compactMap { $0.expression.as(ClosureExprSyntax.self) }
            + [node.trailingClosure].compactMap { $0 }
        for closure in closures {
            let visitor = DerivedValueClosureVisitor(hiddenInputHelperNames: hiddenInputHelperNames)
            visitor.walk(closure)
            violations.append(contentsOf: visitor.violations)
        }
    }
}

private final class DerivedValueHiddenInputHelperCollector: SyntaxVisitor {
    private(set) var hiddenInputHelperNames = Set<String>()

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        guard let body = node.body else {
            return
        }

        let visitor = DerivedValueClosureVisitor(hiddenInputHelperNames: [])
        visitor.walk(body)
        if !visitor.violations.isEmpty {
            hiddenInputHelperNames.insert(node.name.text)
        }
    }
}

private final class DerivedValueClosureVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let hiddenInputHelperNames: Set<String>
    private let deniedNames = Set(["atom", "AtomScope", "AtomReader", "withTestAtomRegistry"])

    init(hiddenInputHelperNames: Set<String>, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.hiddenInputHelperNames = hiddenInputHelperNames
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard deniedNames.contains(node.baseName.text) || hiddenInputHelperNames.contains(node.baseName.text) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "DerivedValue compute closures must declare atom inputs instead of reading atoms directly"
            )
        )
    }
}
