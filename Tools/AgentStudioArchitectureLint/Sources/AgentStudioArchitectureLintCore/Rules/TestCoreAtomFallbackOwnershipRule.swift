import SwiftSyntax

struct TestCoreAtomFallbackOwnershipRule: ArchitectureRule {
    let id = "agentstudio_test_core_atom_fallback_ownership"
    let severity = ArchitectureSeverity.error
    let message =
        "Tests must install the shared Core atom fallback through TestSupport/TestAtomRegistry.swift"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let pathForMatching = path.hasPrefix("/") ? path : "/\(path)"
        guard pathForMatching.contains("/Tests/AgentStudioTests/"),
            !Self.allowedInstallationPaths.contains(where: pathForMatching.hasSuffix)
        else {
            return []
        }

        let visitor = CoreAtomScopeSetUpVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map {
            diagnostic(context: context, position: $0)
        }
    }

    private static let allowedInstallationPaths = [
        "/Tests/AgentStudioTests/TestSupport/TestAtomRegistry.swift",
        "/Tests/AgentStudioTests/App/State/AppAtomRegistryInstallationExitTests.swift",
    ]
}

private final class CoreAtomScopeSetUpVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "setUp",
            let scopeReference = memberAccess.base?.as(DeclReferenceExprSyntax.self),
            scopeReference.baseName.text == "CoreAtomScope"
        else {
            return
        }

        positions.append(memberAccess.positionAfterSkippingLeadingTrivia)
    }
}
