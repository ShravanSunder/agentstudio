import SwiftSyntax

func filesystemObservationIdentifierTokens(in description: String) -> Set<String> {
    Set(
        description.split { character in
            !character.isLetter && !character.isNumber && character != "_"
        }.map(String.init)
    )
}

func filesystemObservationIsTopLevel(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = node.parent
    while let current = ancestor {
        if current.is(SourceFileSyntax.self) {
            return true
        }
        if current.is(ClassDeclSyntax.self)
            || current.is(StructDeclSyntax.self)
            || current.is(EnumDeclSyntax.self)
            || current.is(ActorDeclSyntax.self)
            || current.is(ExtensionDeclSyntax.self)
            || current.is(FunctionDeclSyntax.self)
            || current.is(InitializerDeclSyntax.self)
            || current.is(SubscriptDeclSyntax.self)
            || current.is(AccessorDeclSyntax.self)
            || current.is(ClosureExprSyntax.self)
        {
            return false
        }
        ancestor = current.parent
    }
    return false
}

func filesystemObservationIsInsideExecutableScope(
    _ node: some SyntaxProtocol
) -> Bool {
    var ancestor = node.parent
    while let current = ancestor {
        if current.is(FunctionDeclSyntax.self)
            || current.is(InitializerDeclSyntax.self)
            || current.is(SubscriptDeclSyntax.self)
            || current.is(AccessorDeclSyntax.self)
            || current.is(AccessorBlockSyntax.self)
            || current.is(ClosureExprSyntax.self)
        {
            return true
        }
        ancestor = current.parent
    }
    return false
}

func filesystemObservationRegistryReceiverNames(
    in sourceFile: SourceFileSyntax,
    registryName: String
) -> Set<String> {
    let collector = FilesystemObservationRegistryReceiverCollector(
        registryName: registryName
    )
    collector.walk(sourceFile)
    return collector.receiverNames
}

private final class FilesystemObservationRegistryReceiverCollector: SyntaxVisitor {
    private(set) var receiverNames: Set<String> = []
    private let registryName: String

    init(
        registryName: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.registryName = registryName
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        guard
            filesystemObservationIdentifierTokens(
                in: node.type.trimmedDescription
            ).contains(registryName)
        else {
            return .visitChildren
        }
        let localName = node.secondName?.text ?? node.firstName.text
        if localName != "_" {
            receiverNames.insert(localName)
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        guard let typeAnnotation = node.typeAnnotation,
            filesystemObservationIdentifierTokens(
                in: typeAnnotation.type.trimmedDescription
            ).contains(registryName),
            let identifier = node.pattern.as(IdentifierPatternSyntax.self)
        else {
            return .visitChildren
        }
        receiverNames.insert(identifier.identifier.text)
        return .visitChildren
    }
}
