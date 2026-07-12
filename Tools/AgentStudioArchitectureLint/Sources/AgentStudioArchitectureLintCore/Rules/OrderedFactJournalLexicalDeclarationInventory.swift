import SwiftSyntax

final class OrderedFactJournalAliasInventory: SyntaxVisitor {
    private static let canonicalNominalIdentities: Set<OrderedFactJournalTypeIdentity> = [
        OrderedFactJournalTypeIdentity(["OrderedFactJournal"]),
        OrderedFactJournalTypeIdentity(["AdmissionProtectedRegionToken"]),
        OrderedFactJournalTypeIdentity(["OrderedFactJournal", "State"]),
    ]

    private(set) var declarations: [OrderedFactJournalAliasDeclaration] = []
    private let sourceIdentity: String

    init(
        sourceIdentity: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.sourceIdentity = sourceIdentity
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let lexicalNamespace = orderedFactJournalLexicalNamespace(
            of: node,
            sourceIdentity: sourceIdentity
        )
        let genericParameterNames = orderedFactJournalVisibleGenericParameterNames(at: node)
        let qualifiedTarget = orderedFactJournalQualifiedTypeIdentity(node.initializer.value)
        let targetBeginsWithGenericParameter =
            qualifiedTarget.map {
                genericParameterNames.contains($0.components.first ?? "")
            } ?? false
        declarations.append(
            OrderedFactJournalAliasDeclaration(
                identity: lexicalNamespace.appending(node.name.text),
                lexicalNamespace: lexicalNamespace,
                targetReferences: typeReferences(in: node.initializer.value).filter {
                    genericParameterNames.contains($0.components.first ?? "") == false
                },
                namespaceAliasTarget: node.genericParameterClause == nil
                    && targetBeginsWithGenericParameter == false
                    ? qualifiedTarget : nil
            ))
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        let lexicalNamespace = orderedFactJournalLexicalNamespace(
            of: node,
            sourceIdentity: sourceIdentity
        )
        declarations.append(
            OrderedFactJournalAliasDeclaration(
                identity: lexicalNamespace.appending(node.name.text),
                lexicalNamespace: lexicalNamespace,
                targetReferences: [],
                namespaceAliasTarget: nil
            ))
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNominalShadow(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNominalShadow(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNominalShadow(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNominalShadow(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNominalShadow(name: node.name.text, node: node)
        return .visitChildren
    }

    private func recordNominalShadow(
        name: String,
        node: some SyntaxProtocol
    ) {
        let lexicalNamespace = orderedFactJournalLexicalNamespace(
            of: node,
            sourceIdentity: sourceIdentity
        )
        let identity = lexicalNamespace.appending(name)
        guard Self.canonicalNominalIdentities.contains(identity) == false else { return }
        declarations.append(
            OrderedFactJournalAliasDeclaration(
                identity: identity,
                lexicalNamespace: lexicalNamespace,
                targetReferences: [],
                namespaceAliasTarget: nil
            ))
    }
}
