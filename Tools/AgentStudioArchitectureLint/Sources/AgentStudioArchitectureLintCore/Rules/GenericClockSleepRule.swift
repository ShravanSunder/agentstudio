import SwiftSyntax

struct GenericClockSleepRule: ArchitectureRule {
    let id = "agentstudio_no_generic_clock_sleep"
    let severity = ArchitectureSeverity.error
    let message =
        "Production async delays must avoid generic clock sleep overloads; use Task.sleep(nanoseconds:) through Duration.nanosecondsForTaskSleep or AsyncDelay.taskSleep"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let pathForMatching = path.hasPrefix("/") ? path : "/\(path)"
        let classifier = AgentStudioPathClassifier(path: pathForMatching)
        guard classifier.isAgentStudioSource else {
            return []
        }

        let visitor = GenericClockSleepVisitor(
            allowsInjectedClockSleep: pathForMatching.hasSuffix(
                "Sources/AgentStudio/Infrastructure/Extensions/FoundationExtensions.swift"
            )
        )
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class GenericClockSleepVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let allowsInjectedClockSleep: Bool

    init(allowsInjectedClockSleep: Bool, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.allowsInjectedClockSleep = allowsInjectedClockSleep
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard node.arguments.first?.label?.text == "for" else {
            return
        }

        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "sleep"
        {
            if allowsInjectedClockSleep, !memberAccess.isTaskSleep {
                return
            }
            violations.append(Self.violation(at: memberAccess.positionAfterSkippingLeadingTrivia))
            return
        }

        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self),
            reference.baseName.text == "sleep"
        {
            violations.append(Self.violation(at: reference.positionAfterSkippingLeadingTrivia))
        }
    }

    private static func violation(at position: AbsolutePosition) -> ArchitectureViolation {
        ArchitectureViolation(
            position: position,
            message:
                "Use Task.sleep(nanoseconds:) with Duration.nanosecondsForTaskSleep, or route deterministic waits through AsyncDelay"
        )
    }
}

extension MemberAccessExprSyntax {
    fileprivate var isTaskSleep: Bool {
        base?.trimmedDescription == "Task" && declName.baseName.text == "sleep"
    }
}
