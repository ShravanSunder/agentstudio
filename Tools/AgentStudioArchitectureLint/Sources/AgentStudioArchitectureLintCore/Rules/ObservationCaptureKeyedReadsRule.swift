import SwiftSyntax

struct ObservationCaptureKeyedReadsRule: ArchitectureRule {
    let id = "agentstudio_observation_capture_keyed_reads"
    let severity = ArchitectureSeverity.report
    let message = "Observation capture closures must use keyed reads instead of broad snapshots"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard
            !ArchitectureAllowlists.observationCaptureAllowedPathSuffixes.contains(
                where: context.normalizedPath.hasSuffix
            )
        else { return [] }
        let visitor = ObservationCaptureVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class ObservationCaptureVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.calledExpression.trimmedDescription == "withObservationTracking" else {
            return .visitChildren
        }
        let captureVisitor = BroadObservationReadVisitor()
        for argument in node.arguments {
            captureVisitor.walk(argument.expression)
        }
        if let trailingClosure = node.trailingClosure {
            captureVisitor.walk(trailingClosure)
        }
        positions.append(contentsOf: captureVisitor.positions)
        return .skipChildren
    }
}

private final class BroadObservationReadVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        let calledName: String
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            calledName = member.declName.baseName.text
        } else if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calledName = reference.baseName.text
        } else {
            return
        }
        guard ArchitectureAllowlists.broadObservationReadNames.contains(calledName) else { return }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }
}
