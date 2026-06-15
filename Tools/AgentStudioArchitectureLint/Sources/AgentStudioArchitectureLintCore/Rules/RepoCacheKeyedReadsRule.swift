import SwiftSyntax

struct RepoCacheKeyedReadsRule: ArchitectureRule {
    let id = "agentstudio_repo_cache_keyed_reads"
    let severity = ArchitectureSeverity.error
    let message = "Hot production code must use repo-cache keyed readers or named cold snapshots"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let classifier = AgentStudioPathClassifier(path: path)
        guard classifier.isAgentStudioSource,
            !ArchitectureAllowlists.repoCacheAllowedPathSuffixes.contains(where: { path.hasSuffix($0) })
        else {
            return []
        }

        let visitor = RawRepoCacheMemberVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class RawRepoCacheMemberVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: MemberAccessExprSyntax) {
        let memberName = node.declName.baseName.text
        guard ArchitectureAllowlists.rawRepoCacheMembers.contains(memberName) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "Use keyed repo-cache readers such as worktreeFacts(for:) or named snapshot bridges"
            )
        )
    }
}
