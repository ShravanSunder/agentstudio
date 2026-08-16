import SwiftSyntax

struct ComparisonTargetQueryControlProductionRule: ArchitectureRule {
    let id = "agentstudio_comparison_target_query_control_production"
    let severity = ArchitectureSeverity.error
    let message =
        "Comparison-target query control must only authorize and reserve content; catalog production belongs to the content task producer"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let pathForMatching = path.hasPrefix("/") ? path : "/\(path)"
        let classifier = AgentStudioPathClassifier(path: pathForMatching)
        guard classifier.isAgentStudioSource, classifier.featureName == "Bridge" else {
            return []
        }

        let visitor = ComparisonTargetQueryControlProductionVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class ComparisonTargetQueryControlProductionVisitor: SyntaxVisitor {
    private static let productionReferenceNames: Set<String> = [
        "queryReviewComparisonTargets",
        "captureReviewComparisonTargets",
        "produceComparisonTargetCatalog",
        "produceCatalog",
        "BridgeReviewComparisonTargetCatalog",
        "JSONEncoder",
        "SHA256",
    ]

    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        guard Self.isControlResponseSwitch(node) else {
            return .visitChildren
        }

        for switchElement in node.cases {
            guard let switchCase = switchElement.as(SwitchCaseSyntax.self),
                Self.isComparisonTargetQueryCase(switchCase.label)
            else {
                continue
            }

            let productionVisitor = ComparisonTargetQueryControlProductionCallVisitor(
                productionReferenceNames: Self.productionReferenceNames
            )
            productionVisitor.walk(switchCase.statements)
            violations.append(contentsOf: productionVisitor.violations)
        }

        return .visitChildren
    }

    private static func isControlResponseSwitch(_ node: SwitchExprSyntax) -> Bool {
        var isProviderResponse = false
        var isSchemeProviderDeclaration = false
        var ancestor = node.parent
        while let currentAncestor = ancestor {
            if let function = currentAncestor.as(FunctionDeclSyntax.self) {
                isProviderResponse = function.name.text == "response"
            }
            if let actor = currentAncestor.as(ActorDeclSyntax.self) {
                isSchemeProviderDeclaration = actor.name.text == "BridgePaneProductSchemeProvider"
            }
            if let extensionDeclaration = currentAncestor.as(ExtensionDeclSyntax.self) {
                isSchemeProviderDeclaration =
                    extensionDeclaration.extendedType.trimmedDescription == "BridgePaneProductSchemeProvider"
            }
            ancestor = currentAncestor.parent
        }
        return isProviderResponse && isSchemeProviderDeclaration
    }

    private static func isComparisonTargetQueryCase(_ label: SwitchCaseSyntax.Label) -> Bool {
        guard case .case(let caseLabel) = label else {
            return false
        }
        return caseLabel.caseItems.contains { caseItem in
            caseItem.pattern.tokens(viewMode: .sourceAccurate).contains {
                $0.text == "reviewComparisonTargetsQuery"
            }
        }
    }
}

private final class ComparisonTargetQueryControlProductionCallVisitor: SyntaxVisitor {
    private let productionReferenceNames: Set<String>

    private(set) var violations: [ArchitectureViolation] = []

    init(productionReferenceNames: Set<String>) {
        self.productionReferenceNames = productionReferenceNames
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard productionReferenceNames.contains(node.baseName.text) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message:
                    "Comparison-target query control must only authorize and reserve content; catalog production belongs to the content task producer"
            )
        )
    }
}
