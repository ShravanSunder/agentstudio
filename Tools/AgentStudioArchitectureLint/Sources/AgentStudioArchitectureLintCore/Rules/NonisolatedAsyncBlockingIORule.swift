import SwiftSyntax

struct NonisolatedAsyncBlockingIORule: ArchitectureRule {
    let id = "agentstudio_nonisolated_async_blocking_io_requires_concurrent"
    let severity = ArchitectureSeverity.report
    let message = "Blocking I/O in nonisolated async declarations requires @concurrent"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard
            !ArchitectureAllowlists.concurrentIOAllowedPathSuffixes.contains(
                where: context.normalizedPath.hasSuffix
            )
        else { return [] }
        let visitor = NonisolatedAsyncBlockingIOVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class NonisolatedAsyncBlockingIOVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let isNonisolated = node.modifiers.contains { $0.name.text == "nonisolated" }
        let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        let isConcurrent = node.attributes.contains { $0.trimmedDescription == "@concurrent" }
        guard isNonisolated, isAsync, !isConcurrent, let body = node.body else {
            return .visitChildren
        }
        let visitor = BlockingIOCallVisitor()
        visitor.walk(body)
        positions.append(contentsOf: visitor.positions)
        return .skipChildren
    }
}

private final class BlockingIOCallVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        let hasContentsOfArgument = node.arguments.first?.label?.text == "contentsOf"
        let isFileManagerRead =
            node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            == "contentsOfDirectory"
        guard hasContentsOfArgument || isFileManagerRead else { return }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }
}
