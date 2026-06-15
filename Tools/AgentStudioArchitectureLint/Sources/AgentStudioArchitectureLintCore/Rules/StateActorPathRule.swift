import SwiftSyntax

struct StateActorPathRule: ArchitectureRule {
    let id = "agentstudio_state_actor_path"
    let severity = ArchitectureSeverity.warning
    let message = "Atom and store source files should live under State/MainActor/{Atoms,Persistence}"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let classifier = AgentStudioPathClassifier(path: path)
        guard classifier.isAgentStudioSource,
            path.contains("/State/"),
            !path.contains("/State/MainActor/Atoms/"),
            !path.contains("/State/MainActor/Persistence/"),
            !ArchitectureAllowlists.stateActorGrandfatheredPathFragments.contains(where: { path.contains($0) })
        else {
            return []
        }

        let visitor = StateOwnerDeclarationVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map {
            diagnostic(
                context: context,
                position: $0,
                message: "Move atom/store owners under State/MainActor/Atoms or State/MainActor/Persistence"
            )
        }
    }
}

private final class StateOwnerDeclarationVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        recordIfStateOwner(name: node.name.text, position: node.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        recordIfStateOwner(name: node.name.text, position: node.positionAfterSkippingLeadingTrivia)
    }

    private func recordIfStateOwner(name: String, position: AbsolutePosition) {
        if name.hasSuffix("Atom") || name.hasSuffix("Store") {
            positions.append(position)
        }
    }
}
