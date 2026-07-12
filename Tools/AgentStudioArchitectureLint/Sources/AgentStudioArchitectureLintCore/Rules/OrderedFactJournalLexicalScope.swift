import SwiftSyntax

private struct OrderedFactJournalScopeSegment {
    let components: [String]
    let isExecutable: Bool
}

func orderedFactJournalLexicalNamespace(
    of node: some SyntaxProtocol,
    sourceIdentity: String
) -> OrderedFactJournalTypeIdentity {
    var reversedScopeSegments: [OrderedFactJournalScopeSegment] = []
    var ancestor = node.parent
    while let current = ancestor {
        if let declaration = current.as(ClassDeclSyntax.self) {
            reversedScopeSegments.append(nominalScopeSegment(declaration.name.text))
        } else if let declaration = current.as(StructDeclSyntax.self) {
            reversedScopeSegments.append(nominalScopeSegment(declaration.name.text))
        } else if let declaration = current.as(EnumDeclSyntax.self) {
            reversedScopeSegments.append(nominalScopeSegment(declaration.name.text))
        } else if let declaration = current.as(ActorDeclSyntax.self) {
            reversedScopeSegments.append(nominalScopeSegment(declaration.name.text))
        } else if let declaration = current.as(ProtocolDeclSyntax.self) {
            reversedScopeSegments.append(nominalScopeSegment(declaration.name.text))
        } else if let declaration = current.as(ExtensionDeclSyntax.self),
            let identity = orderedFactJournalQualifiedTypeIdentity(declaration.extendedType)
        {
            reversedScopeSegments.append(
                OrderedFactJournalScopeSegment(
                    components: identity.components,
                    isExecutable: false
                )
            )
        } else if let declaration = current.as(FunctionDeclSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "function:\(declaration.name.text)",
                    position: declaration.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let declaration = current.as(InitializerDeclSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "initializer",
                    position: declaration.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let declaration = current.as(SubscriptDeclSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "subscript",
                    position: declaration.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let declaration = current.as(AccessorDeclSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "accessor:\(declaration.accessorSpecifier.text)",
                    position: declaration.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let declaration = current.as(ClosureExprSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "closure",
                    position: declaration.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let branch = current.as(SwitchCaseSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "switch-case",
                    position: branch.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let branch = current.as(IfConfigClauseSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "if-config-clause",
                    position: branch.positionAfterSkippingLeadingTrivia
                )
            )
        } else if let declaration = current.as(CodeBlockSyntax.self) {
            reversedScopeSegments.append(
                executableScopeSegment(
                    kind: "block",
                    position: declaration.positionAfterSkippingLeadingTrivia
                )
            )
        }
        ancestor = current.parent
    }

    var components: [String] = []
    var insertedSourceIdentity = false
    for segment in reversedScopeSegments.reversed() {
        if segment.isExecutable, insertedSourceIdentity == false {
            components.append("$file:\(sourceIdentity)")
            insertedSourceIdentity = true
        }
        components.append(contentsOf: segment.components)
    }
    return OrderedFactJournalTypeIdentity(components)
}

func orderedFactJournalVisibleGenericParameterNames(
    at node: some SyntaxProtocol
) -> Set<String> {
    var parameterNames: Set<String> = []
    var current: Syntax? = Syntax(node)
    while let syntax = current {
        let genericParameterClause: GenericParameterClauseSyntax?
        if let declaration = syntax.as(ClassDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(StructDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(EnumDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(ActorDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(FunctionDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(InitializerDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(SubscriptDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(TypeAliasDeclSyntax.self) {
            genericParameterClause = declaration.genericParameterClause
        } else {
            genericParameterClause = nil
        }
        if let genericParameterClause {
            parameterNames.formUnion(genericParameterClause.parameters.map { $0.name.text })
        }
        current = syntax.parent
    }
    return parameterNames
}

private func nominalScopeSegment(_ name: String) -> OrderedFactJournalScopeSegment {
    OrderedFactJournalScopeSegment(components: [name], isExecutable: false)
}

private func executableScopeSegment(
    kind: String,
    position: AbsolutePosition
) -> OrderedFactJournalScopeSegment {
    OrderedFactJournalScopeSegment(
        components: ["$\(kind)@\(position.utf8Offset)"],
        isExecutable: true
    )
}
