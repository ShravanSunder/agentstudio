import SwiftSyntax

struct TerminalLocalDispositionPublicationRule: ArchitectureRule {
    let id = "agentstudio_terminal_local_disposition_publication"
    let severity = ArchitectureSeverity.error
    let message =
        "GhosttyActionDisposition local-only cases must contract locally before routeActionToTerminalRuntimeOnMainActor"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let pathForMatching = path.hasPrefix("/") ? path : "/\(path)"
        let classifier = AgentStudioPathClassifier(path: pathForMatching)
        guard classifier.isAgentStudioSource, classifier.featureName == "Terminal" else {
            return []
        }

        let visitor = TerminalLocalDispositionPublicationVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class TerminalLocalDispositionPublicationVisitor: SyntaxVisitor {
    private static let localDispositionNames: Set<String> = [
        "latestPresentation",
        "latestSemanticMetadata",
        "activityEvidence",
        "exactLocalLifecycle",
        "diagnostic",
    ]

    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        guard Self.isGhosttyActionDispositionClassification(node.subject) else {
            return .visitChildren
        }

        for switchElement in node.cases {
            guard let switchCase = switchElement.as(SwitchCaseSyntax.self),
                Self.containsLocalDisposition(switchCase.label)
            else {
                continue
            }

            if switchCase.statements.last?.item.is(ReturnStmtSyntax.self) != true {
                violations.append(
                    ArchitectureViolation(
                        position: switchCase.positionAfterSkippingLeadingTrivia,
                        message:
                            "GhosttyActionDisposition local-only cases must end in a top-level return before semantic runtime publication"
                    )
                )
            }

            let publicationVisitor = TerminalRuntimePublicationCallVisitor()
            publicationVisitor.walk(switchCase.statements)
            violations.append(contentsOf: publicationVisitor.violations)
        }

        return .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard Self.isGhosttyActionDispositionClassification(ExprSyntax(node)),
            !Self.isDirectSwitchSubject(node)
        else {
            return
        }

        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message:
                    "GhosttyActionDisposition.classify results must be consumed directly by a switch"
            )
        )
    }

    private static func isGhosttyActionDispositionClassification(_ expression: ExprSyntax) -> Bool {
        guard let call = expression.as(FunctionCallExprSyntax.self),
            let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self)
        else {
            return false
        }
        return memberAccess.base?.trimmedDescription == "GhosttyActionDisposition"
            && memberAccess.declName.baseName.text == "classify"
    }

    private static func isDirectSwitchSubject(_ call: FunctionCallExprSyntax) -> Bool {
        guard let switchExpression = call.parent?.as(SwitchExprSyntax.self),
            let subjectCall = switchExpression.subject.as(FunctionCallExprSyntax.self)
        else {
            return false
        }
        return subjectCall.id == call.id
    }

    private static func containsLocalDisposition(_ label: SwitchCaseSyntax.Label) -> Bool {
        guard case .case(let caseLabel) = label else {
            return false
        }
        return caseLabel.caseItems.contains { caseItem in
            let tokens = Array(caseItem.pattern.tokens(viewMode: .sourceAccurate))
            return tokens.indices.dropLast().contains { tokenIndex in
                tokens[tokenIndex].text == "."
                    && localDispositionNames.contains(tokens[tokenIndex + 1].text)
            }
        }
    }
}

private final class TerminalRuntimePublicationCallVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard Self.isTerminalRuntimePublicationCall(node.calledExpression) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.calledExpression.positionAfterSkippingLeadingTrivia,
                message:
                    "GhosttyActionDisposition local-only cases must contract locally before routeActionToTerminalRuntimeOnMainActor"
            )
        )
    }

    private static func isTerminalRuntimePublicationCall(_ expression: ExprSyntax) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "routeActionToTerminalRuntimeOnMainActor"
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text == "routeActionToTerminalRuntimeOnMainActor"
        }
        return false
    }
}
