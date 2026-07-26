import SwiftSyntax

struct CanonicalAtomMutationRule: ArchitectureRule {
    let id = "agentstudio_canonical_atom_mutation"
    let severity = ArchitectureSeverity.error
    let message = "Canonical atom state must mutate through named owner methods or coordinators"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.normalizedPath.contains("/Sources/AgentStudio/"),
            context.normalizedPath.contains("/State/MainActor/Atoms/")
        else {
            return []
        }

        let visitor = CanonicalAtomMutationVisitor()
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class CanonicalAtomMutationVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !isDerivedReader(node.name.text) else {
            return .skipChildren
        }

        for member in node.memberBlock.members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                variableDecl.bindingSpecifier.text == "var"
            else {
                continue
            }
            validate(variableDecl)
        }
        return .visitChildren
    }

    private func validate(_ node: VariableDeclSyntax) {
        if hasWritableBinding(node) {
            violations.append(
                ArchitectureViolation(
                    position: node.positionAfterSkippingLeadingTrivia,
                    message: "Canonical atom owner classes must not store a writable binding"
                )
            )
            return
        }

        guard node.bindings.contains(where: isStoredProperty),
            !node.bindings.allSatisfy(isDerivedReaderBinding),
            !hasPrivateSetter(node)
        else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "Canonical mutable stored state must be private or private(set)"
            )
        )
    }

    private func hasWritableBinding(_ node: VariableDeclSyntax) -> Bool {
        if node.attributes.contains(where: { element in
            guard case .attribute(let attribute) = element else {
                return false
            }
            return attribute.attributeName.trimmedDescription.split(separator: ".").last == "Binding"
        }) {
            return true
        }
        return node.bindings.contains {
            $0.typeAnnotation?.type.trimmedDescription.hasPrefix("Binding<") == true
        }
    }

    private func isStoredProperty(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else {
            return true
        }
        switch accessorBlock.accessors {
        case .getter:
            return false
        case .accessors(let accessors):
            let accessorNames = Set(accessors.map(\.accessorSpecifier.text))
            let computedAccessorNames = Set(["get", "set", "_read", "read", "_modify", "modify"])
            return accessorNames.isDisjoint(with: computedAccessorNames)
        }
    }

    private func hasPrivateSetter(_ node: VariableDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.text == "private" }
    }

    private func isDerivedReaderBinding(_ binding: PatternBindingSyntax) -> Bool {
        let typeName = binding.typeAnnotation?.type.trimmedDescription
        let initializer = binding.initializer?.value.trimmedDescription
        return typeName?.hasSuffix("Derived") == true
            || initializer?.split(separator: "(").first?.hasSuffix("Derived") == true
    }

    private func isDerivedReader(_ className: String) -> Bool {
        className.hasSuffix("Derived")
            || className.hasSuffix("Reader")
            || className.hasSuffix("Projection")
    }
}
