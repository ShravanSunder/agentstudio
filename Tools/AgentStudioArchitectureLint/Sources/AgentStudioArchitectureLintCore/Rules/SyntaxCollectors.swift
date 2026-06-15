import SwiftSyntax

struct ImportRecord {
    let path: [String]
    let position: AbsolutePosition
}

struct ReferenceRecord {
    let name: String
    let position: AbsolutePosition
}

struct InheritanceRecord {
    let name: String
    let position: AbsolutePosition
}

struct ArchitectureViolation {
    let position: AbsolutePosition
    let message: String
}

extension DeclReferenceExprSyntax {
    var isMemberAccessName: Bool {
        guard let memberAccess = parent?.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return memberAccess.declName.baseName.text == baseName.text
    }
}

final class ImportCollectingVisitor: SyntaxVisitor {
    private(set) var imports: [ImportRecord] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: ImportDeclSyntax) {
        imports.append(
            ImportRecord(
                path: node.path.map(\.name.text),
                position: node.positionAfterSkippingLeadingTrivia
            )
        )
    }
}

final class ReferenceCollectingVisitor: SyntaxVisitor {
    private(set) var references: [ReferenceRecord] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        references.append(
            ReferenceRecord(
                name: node.baseName.text,
                position: node.positionAfterSkippingLeadingTrivia
            )
        )
    }
}

final class InheritanceCollectingVisitor: SyntaxVisitor {
    private(set) var inheritedTypes: [InheritanceRecord] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: InheritedTypeSyntax) {
        inheritedTypes.append(
            InheritanceRecord(
                name: node.type.trimmedDescription,
                position: node.positionAfterSkippingLeadingTrivia
            )
        )
    }
}
