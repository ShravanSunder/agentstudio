import SwiftSyntax

struct MainActorUnboundedCollectionWorkRule: ArchitectureRule {
    let id = "agentstudio_mainactor_unbounded_collection_work"
    let severity = ArchitectureSeverity.report
    let message = "MainActor collection-wide work requires an explicit bounded owner or allowlist"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard
            !ArchitectureAllowlists.mainActorCollectionWorkAllowedPathSuffixes.contains(
                where: context.normalizedPath.hasSuffix
            )
        else { return [] }
        let visitor = MainActorCollectionWorkVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class MainActorCollectionWorkVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []
    private var mainActorScopeDepth = 0

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth -= 1
        }
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth -= 1
        }
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth -= 1
        }
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        if node.attributes.contains(where: { $0.trimmedDescription == "@MainActor" }) {
            mainActorScopeDepth -= 1
        }
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard mainActorScopeDepth > 0,
            let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            ArchitectureAllowlists.unboundedCollectionCallNames.contains(member.declName.baseName.text)
        else { return }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }
}
