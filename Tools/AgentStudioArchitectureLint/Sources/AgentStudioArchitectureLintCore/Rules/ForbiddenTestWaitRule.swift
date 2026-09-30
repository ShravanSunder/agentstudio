import SwiftSyntax

/// Forbids settling and eventual-assertion helpers in tests. Existing uses
/// live only in the reviewed, shrink-only forbidden-test-wait ledger.
struct ForbiddenTestWaitRule: ArchitectureRule {
    let id = "agentstudio_no_forbidden_test_wait"
    let severity = ArchitectureSeverity.error
    let message = "Tests await typed owner facts instead of waitUntilIdle or assertEventually helpers"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.workspaceRelativePath ?? context.normalizedPath
        guard path.hasSuffix(".swift"), path.hasPrefix("Tests/") || path.contains("/Tests/") else {
            return []
        }

        let visitor = ForbiddenTestWaitVisitor()
        visitor.walk(context.sourceFile)
        return visitor.references.map { reference in
            diagnostic(context: context, position: reference.positionAfterSkippingLeadingTrivia)
        }
    }

}

private enum ForbiddenWaitName {
    static let direct: Set<String> = ["waitUntilIdle", "assertEventuallyAsync", "assertEventuallyMain"]
}

private final class ForbiddenTestWaitVisitor: SyntaxVisitor {
    /// Every lexical block shadows names from its parents. A binding is an
    /// alias only when its initializer is a direct function reference or a
    /// previously resolved alias, never the result of calling one.
    private var bindings: [[String: Bool]] = [[:]]
    private(set) var references: [TokenSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        bindings.append([:])
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        bindings.removeLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        bindings.append([:])
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        bindings.removeLast()
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return }
        let expression = node.initializer?.value
        let referencedName =
            expression?.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? expression?.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        let isAlias =
            referencedName.map {
                ForbiddenWaitName.direct.contains($0) || resolvesAlias($0)
            } ?? false
        bindings[bindings.count - 1][name] = isAlias
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        // A member's declName is itself a DeclReferenceExprSyntax. The owning
        // MemberAccessExprSyntax reports it once, including optional chains.
        guard node.parent?.is(MemberAccessExprSyntax.self) != true else { return }
        let name = node.baseName.text
        if ForbiddenWaitName.direct.contains(name) || resolvesAlias(name) {
            references.append(node.baseName)
        }
    }

    override func visitPost(_ node: MemberAccessExprSyntax) {
        if ForbiddenWaitName.direct.contains(node.declName.baseName.text) {
            references.append(node.declName.baseName)
        }
    }

    private func resolvesAlias(_ name: String) -> Bool {
        for scope in bindings.reversed() {
            if let isAlias = scope[name] { return isAlias }
        }
        return false
    }
}
