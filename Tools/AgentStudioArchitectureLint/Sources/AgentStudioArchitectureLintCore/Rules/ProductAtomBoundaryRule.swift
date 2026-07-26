import SwiftSyntax

struct ProductAtomBoundaryRule: ArchitectureRule {
    let id = "agentstudio_product_atom_boundary"
    let severity = ArchitectureSeverity.error
    let message = "Product atom state must follow its Core, Feature, and App composition boundaries"

    private let stateOwnersByTypeName: [String: ProductStateOwner]

    init() {
        stateOwnersByTypeName = [:]
    }

    private init(stateOwnersByTypeName: [String: ProductStateOwner]) {
        self.stateOwnersByTypeName = stateOwnersByTypeName
    }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        var stateOwnersByTypeName: [String: ProductStateOwner] = [:]
        for context in contexts {
            let path = context.normalizedPath
            guard path.contains("/State/MainActor/Atoms/") else {
                continue
            }

            let classifier = AgentStudioPathClassifier(path: path)
            let owner: ProductStateOwner
            if classifier.layer == "Core" {
                owner = .core
            } else if let featureName = classifier.featureName {
                owner = .feature(featureName)
            } else {
                continue
            }

            let visitor = ProductStateDeclarationVisitor()
            visitor.walk(context.sourceFile)
            for typeName in visitor.classNames {
                stateOwnersByTypeName[typeName] = owner
            }
        }
        return Self(stateOwnersByTypeName: stateOwnersByTypeName)
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let classifier = AgentStudioPathClassifier(path: context.normalizedPath)
        guard classifier.isAgentStudioSource else {
            return []
        }

        let visitor = ProductAtomBoundaryVisitor(
            classifier: classifier,
            isAppCompositionSource: isAppCompositionSource(context.normalizedPath),
            stateOwnersByTypeName: stateOwnersByTypeName
        )
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }

    private func isAppCompositionSource(_ path: String) -> Bool {
        path.contains("/Sources/AgentStudio/App/")
            || path.hasSuffix("/Sources/AgentStudio/AtomRegistry.swift")
    }
}

private enum ProductStateOwner: Sendable, Equatable {
    case core
    case feature(String)
}

private final class ProductStateDeclarationVisitor: SyntaxVisitor {
    private(set) var classNames: [String] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        classNames.append(node.name.text)
    }
}

private final class ProductAtomBoundaryVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    private let classifier: AgentStudioPathClassifier
    private let isAppCompositionSource: Bool
    private let stateOwnersByTypeName: [String: ProductStateOwner]

    init(
        classifier: AgentStudioPathClassifier,
        isAppCompositionSource: Bool,
        stateOwnersByTypeName: [String: ProductStateOwner]
    ) {
        self.classifier = classifier
        self.isAppCompositionSource = isAppCompositionSource
        self.stateOwnersByTypeName = stateOwnersByTypeName
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: IdentifierTypeSyntax) {
        let typeName = node.name.text
        if typeName == "KeyPath",
            node.genericArgumentClause?.arguments.first?.argument.trimmedDescription == "AtomRegistry"
        {
            record(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "Lower targets must use KeyPath<CoreAtoms, Value>, never KeyPath<AtomRegistry, Value>"
            )
            return
        }
        validateProductStateReference(
            name: typeName,
            position: node.positionAfterSkippingLeadingTrivia
        )
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard !node.isMemberAccessName else {
            return
        }
        validateProductStateReference(
            name: node.baseName.text,
            position: node.positionAfterSkippingLeadingTrivia
        )
    }

    override func visitPost(_ node: AttributeSyntax) {
        let attributeName = node.attributeName.trimmedDescription.split(separator: ".").last.map(String.init)
        guard attributeName == "Atom" else {
            return
        }
        record(
            position: node.positionAfterSkippingLeadingTrivia,
            message: "Remove the @Atom compatibility API; Core uses atom(KeyPath<CoreAtoms, Value>)"
        )
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: TypeAliasDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        validateDeclarationName(node.name.text, position: node.name.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        guard isAppCompositionSource,
            variableDeclNamesAtomRegistry(node),
            node.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })
                || isFileScopeVariable(node)
        else {
            return
        }
        record(
            position: node.positionAfterSkippingLeadingTrivia,
            message: "App must not expose a static or global AtomRegistry; inject concrete Feature state"
        )
    }

    private func validateProductStateReference(name: String, position: AbsolutePosition) {
        if let compatibilityMessage = compatibilityMessage(for: name) {
            record(position: position, message: compatibilityMessage)
            return
        }

        guard let layer = classifier.layer else {
            return
        }
        if name == "AtomRegistry", layer != "App" {
            record(
                position: position,
                message: "Lower targets must not name the App-owned AtomRegistry"
            )
            return
        }

        let owner = stateOwnersByTypeName[name]
        if layer == "Infrastructure",
            owner != nil || ["CoreAtoms", "CoreAtomScope"].contains(name)
        {
            record(
                position: position,
                message: "Infrastructure must not name product atom state such as \(name)"
            )
            return
        }
        switch (layer, owner) {
        case ("Core", .feature):
            record(
                position: position,
                message: "Core must not name Feature-owned atom state \(name)"
            )
        case ("Features", .feature(let ownerFeature)):
            guard let currentFeature = classifier.featureName, currentFeature != ownerFeature else {
                return
            }
            record(
                position: position,
                message: "Feature \(currentFeature) must not name sibling Feature atom state \(name)"
            )
        default:
            break
        }
    }

    private func validateDeclarationName(_ name: String, position: AbsolutePosition) {
        if isAppCompositionSource, name.hasSuffix("AtomScope") {
            record(
                position: position,
                message: "App must not define a second App atom scope; CoreAtomScope is the only ambient scope"
            )
            return
        }
        if let message = compatibilityMessage(for: name) {
            record(position: position, message: message)
        }
    }

    private func compatibilityMessage(for name: String) -> String? {
        if name == "AtomScope" {
            return "Remove the old AtomScope compatibility API; CoreAtomScope is the sole ambient scope"
        }
        if name == "AgentStudioState" || name.hasSuffix("FeatureState") {
            return "Do not introduce a uniform Feature state root; inject each Feature's concrete state"
        }
        if name.hasSuffix("FeatureRegistry") || name.hasSuffix("FeatureAtomScope") {
            return "Do not introduce a Feature registry or ambient scope; inject concrete Feature state"
        }
        if name.contains("AtomResolver") || name == "resolveAtom" {
            return "Do not introduce a runtime atom resolver"
        }
        if name.contains("AtomRegistration") || name == "registerAtom" {
            return "Do not introduce runtime atom registration"
        }
        if name.contains("AtomCompatibility") || ["AtomReader", "Derived", "DerivedSelector"].contains(name) {
            return "Remove the atom compatibility API instead of preserving the old registry access path"
        }
        return nil
    }

    private func variableDeclNamesAtomRegistry(_ node: VariableDeclSyntax) -> Bool {
        node.bindings.contains { binding in
            binding.typeAnnotation.map { syntaxNamesAtomRegistry($0.type) } == true
                || binding.initializer.map { syntaxNamesAtomRegistry($0.value) } == true
        }
    }

    private func syntaxNamesAtomRegistry(_ node: some SyntaxProtocol) -> Bool {
        let visitor = AtomRegistryNameVisitor()
        visitor.walk(node)
        return visitor.namesAtomRegistry
    }

    private func isFileScopeVariable(_ node: VariableDeclSyntax) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(MemberBlockItemSyntax.self)
                || current.is(FunctionDeclSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(ClosureExprSyntax.self)
            {
                return false
            }
            if current.is(SourceFileSyntax.self) {
                return true
            }
            ancestor = current.parent
        }
        return false
    }

    private func record(position: AbsolutePosition, message: String) {
        violations.append(ArchitectureViolation(position: position, message: message))
    }
}

private final class AtomRegistryNameVisitor: SyntaxVisitor {
    private(set) var namesAtomRegistry = false

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: IdentifierTypeSyntax) {
        namesAtomRegistry = namesAtomRegistry || node.name.text == "AtomRegistry"
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        namesAtomRegistry = namesAtomRegistry || node.baseName.text == "AtomRegistry"
    }
}
