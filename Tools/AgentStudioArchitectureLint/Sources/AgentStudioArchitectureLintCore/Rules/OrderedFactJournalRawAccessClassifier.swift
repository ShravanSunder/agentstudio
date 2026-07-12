import SwiftSyntax

final class OrderedFactJournalRawAccessVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex
    private let sourceIdentity: String
    private let message: String

    init(
        declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex,
        sourceIdentity: String,
        message: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.declarationAliasIndex = declarationAliasIndex
        self.sourceIdentity = sourceIdentity
        self.message = message
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard
            declarationAliasIndex.containsJournalType(
                in: node.extendedType,
                lexicalNamespace: lexicalNamespace(of: node)
            )
        else {
            return .visitChildren
        }
        let markers = OrderedFactJournalRawMarkerVisitor(
            declarationAliasIndex: declarationAliasIndex,
            sourceIdentity: sourceIdentity
        )
        markers.walk(node.memberBlock)
        if markers.foundRawAccess {
            recordViolation(at: node.extensionKeyword.positionAfterSkippingLeadingTrivia)
        }
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let lexicalNamespace = lexicalNamespace(of: node)
        if declarationAliasIndex.containsRawStateType(
            in: node.initializer.value,
            lexicalNamespace: lexicalNamespace
        ) {
            recordViolation(at: node.name.positionAfterSkippingLeadingTrivia)
        }
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if isForbiddenDirectSignature(
            parts: [Syntax(node.signature)],
            lexicalNamespace: lexicalNamespace(of: node)
        ) {
            recordViolation(at: node.name.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if isForbiddenDirectSignature(
            parts: [Syntax(node.signature)],
            lexicalNamespace: lexicalNamespace(of: node)
        ) {
            recordViolation(at: node.initKeyword.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if isForbiddenDirectSignature(
            parts: [Syntax(node.parameterClause), Syntax(node.returnClause)],
            lexicalNamespace: lexicalNamespace(of: node)
        ) {
            recordViolation(at: node.subscriptKeyword.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let lexicalNamespace = lexicalNamespace(of: node)
        let typeAnnotations = node.bindings.compactMap(\.typeAnnotation)
        let containsRawState = typeAnnotations.contains {
            declarationAliasIndex.containsRawStateType(
                in: $0.type,
                lexicalNamespace: lexicalNamespace
            )
        }
        let containsToken = typeAnnotations.contains {
            declarationAliasIndex.containsProtectedTokenType(
                in: $0.type,
                lexicalNamespace: lexicalNamespace
            )
        }
        let containsJournal = typeAnnotations.contains {
            declarationAliasIndex.containsJournalType(
                in: $0.type,
                lexicalNamespace: lexicalNamespace
            )
        }
        if containsRawState || containsToken && containsJournal {
            recordViolation(at: node.bindingSpecifier.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    private func isForbiddenDirectSignature(
        parts: [Syntax],
        lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        let containsRawState = parts.contains {
            declarationAliasIndex.containsRawStateType(
                in: $0,
                lexicalNamespace: lexicalNamespace
            )
        }
        let containsToken = parts.contains {
            declarationAliasIndex.containsProtectedTokenType(
                in: $0,
                lexicalNamespace: lexicalNamespace
            )
        }
        let containsJournal = parts.contains {
            declarationAliasIndex.containsJournalType(
                in: $0,
                lexicalNamespace: lexicalNamespace
            )
        }
        return containsRawState || containsToken && containsJournal
    }

    private func lexicalNamespace(
        of node: some SyntaxProtocol
    ) -> OrderedFactJournalTypeIdentity {
        declarationAliasIndex.resolvedLexicalNamespace(
            orderedFactJournalLexicalNamespace(
                of: node,
                sourceIdentity: sourceIdentity
            )
        )
    }

    private func recordViolation(at position: AbsolutePosition) {
        violations.append(ArchitectureViolation(position: position, message: message))
    }
}

private final class OrderedFactJournalRawMarkerVisitor: SyntaxVisitor {
    private(set) var foundRawAccess = false
    private let declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex
    private let sourceIdentity: String

    init(
        declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex,
        sourceIdentity: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.declarationAliasIndex = declarationAliasIndex
        self.sourceIdentity = sourceIdentity
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        recordRawStateTypeIfNeeded(node)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        recordRawStateTypeIfNeeded(node)
        return .visitChildren
    }

    private func recordRawStateTypeIfNeeded(_ node: some SyntaxProtocol) {
        let lexicalNamespace = declarationAliasIndex.resolvedLexicalNamespace(
            orderedFactJournalLexicalNamespace(
                of: node,
                sourceIdentity: sourceIdentity
            )
        )
        if declarationAliasIndex.containsRawStateType(
            in: node,
            lexicalNamespace: lexicalNamespace
        ) {
            foundRawAccess = true
        }
        if declarationAliasIndex.containsProtectedTokenType(
            in: node,
            lexicalNamespace: lexicalNamespace
        ) {
            foundRawAccess = true
        }
        if declarationAliasIndex.containsRawLockType(
            in: node,
            lexicalNamespace: lexicalNamespace
        ) {
            foundRawAccess = true
        }
    }
}
