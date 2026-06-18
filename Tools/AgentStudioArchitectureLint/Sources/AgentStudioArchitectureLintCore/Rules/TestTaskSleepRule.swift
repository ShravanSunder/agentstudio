import SwiftSyntax

struct TestTaskSleepRule: ArchitectureRule {
    let id = "agentstudio_no_task_sleep_in_tests"
    let severity = ArchitectureSeverity.error
    let message =
        "Tests must wait for explicit events, state, or injected fake clocks instead of direct Task.sleep"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard let targetPath = Self.targetPath(for: context) else {
            return []
        }
        guard targetPath.contains("/Tests/"), targetPath.hasSuffix(".swift") else {
            return []
        }

        let visitor = TestTaskSleepVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }

    private static func targetPath(for context: ArchitectureLintContext) -> String? {
        let normalizedPath = context.normalizedPath
        let pathForFixtureMatching = normalizedPath.hasPrefix("/") ? normalizedPath : "/\(normalizedPath)"
        for marker in ["/Fixtures/Bad/", "/Fixtures/Good/"] {
            if let range = pathForFixtureMatching.range(of: marker) {
                return "/\(pathForFixtureMatching[range.upperBound...])"
            }
        }
        guard let relativePath = context.workspaceRelativePath else {
            return nil
        }
        return relativePath.hasPrefix("/") ? relativePath : "/\(relativePath)"
    }
}

private final class TestTaskSleepVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.isDirectTaskSleep
        else {
            return
        }

        violations.append(
            ArchitectureViolation(
                position: memberAccess.positionAfterSkippingLeadingTrivia,
                message: "Use event/state waiters or injected fake clocks instead of direct Task.sleep in tests"
            )
        )
    }
}

extension MemberAccessExprSyntax {
    fileprivate var isDirectTaskSleep: Bool {
        guard declName.baseName.text == "sleep" else {
            return false
        }
        return base?.isTaskTypeReference == true
    }
}

extension ExprSyntax {
    fileprivate var isTaskTypeReference: Bool {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "Task"
        }

        if let memberAccess = self.as(MemberAccessExprSyntax.self) {
            guard memberAccess.declName.baseName.text == "Task",
                let baseReference = memberAccess.base?.as(DeclReferenceExprSyntax.self)
            else {
                return false
            }
            return baseReference.baseName.text == "Swift"
                || baseReference.baseName.text == "_Concurrency"
        }

        if let specialization = self.as(GenericSpecializationExprSyntax.self) {
            return specialization.expression.isTaskTypeReference
        }

        return false
    }
}
