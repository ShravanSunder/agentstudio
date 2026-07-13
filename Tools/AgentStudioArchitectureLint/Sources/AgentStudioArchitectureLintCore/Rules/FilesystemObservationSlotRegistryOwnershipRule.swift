import SwiftSyntax

struct FilesystemObservationSlotRegistryOwnershipRule: ArchitectureRule {
    static let primaryOwnerMessage =
        "FilesystemObservationSlotRegistry must remain exactly one top-level final primary class in its owner file"
    static let ownerExtensionMessage =
        "FilesystemObservationSlotRegistry must not have production extensions"
    static let ownerAliasMessage =
        "FilesystemObservationSlotRegistry must not be aliased in production"
    static let outsideTransitionMessage =
        "Filesystem observation binding/control/native construction must occur directly in beginNativeLifetime's selected transition"
    static let constructorCardinalityMessage =
        "Each filesystem observation binding/control/native constructor must have exactly one production call site"
    static let constructorAliasMessage =
        "Filesystem observation binding/control/native constructor types must not be aliased"
    static let initializerEscapeMessage =
        "Filesystem observation binding/control/native initializers must not escape as values"
    static let mutableContractMessage =
        "Filesystem observation slot-registry contracts must remain immutable value contracts with read-only projections"

    let id = "agentstudio_filesystem_observation_slot_registry_ownership"
    let severity = ArchitectureSeverity.error
    let message = Self.primaryOwnerMessage
    private let preparedInventory: FilesystemObservationSlotRegistryOwnershipInventory?

    init() {
        preparedInventory = nil
    }

    private init(
        preparedInventory: FilesystemObservationSlotRegistryOwnershipInventory
    ) {
        self.preparedInventory = preparedInventory
    }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        Self(
            preparedInventory: FilesystemObservationSlotRegistryOwnershipInventory(
                contexts: contexts
            )
        )
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let inventory =
            preparedInventory
            ?? FilesystemObservationSlotRegistryOwnershipInventory(contexts: [context])
        return inventory.violationsBySourceIdentity[context.syntaxScopeSourceIdentity, default: []]
            .map { violation in
                diagnostic(
                    context: context,
                    position: violation.position,
                    message: violation.message
                )
            }
    }
}

private enum FilesystemObservationLifetimeConstructor: String, CaseIterable, Sendable {
    case binding = "FilesystemObservationSlotBinding"
    case bindingIdentity = "FilesystemObservationSlotBindingIdentity"
    case controlBlockIdentity = "FilesystemObservationControlBlockIdentity"
    case nativeGenerationIdentity = "FilesystemObservationNativeGenerationIdentity"
}

private struct FilesystemObservationOwnershipSite: Sendable {
    let sourceIdentity: String
    let position: AbsolutePosition
}

private struct FilesystemObservationOwnerSite: Sendable {
    let site: FilesystemObservationOwnershipSite
    let isApprovedPrimaryShape: Bool
}

private struct FilesystemObservationConstructionSite: Sendable {
    let site: FilesystemObservationOwnershipSite
    let constructor: FilesystemObservationLifetimeConstructor
    let isApprovedTransition: Bool
}

private struct FilesystemObservationOwnershipViolation: Sendable {
    let position: AbsolutePosition
    let message: String
}

// swiftlint:disable:next type_name
private struct FilesystemObservationSlotRegistryOwnershipInventory: Sendable {
    static let registryName = "FilesystemObservationSlotRegistry"
    static let productionSourcePrefix = "Sources/AgentStudio/"
    static let registryPath =
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistry.swift"
    static let contractsPath =
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistryContracts.swift"

    let violationsBySourceIdentity: [String: [FilesystemObservationOwnershipViolation]]

    // swiftlint:disable:next function_body_length
    init(contexts: [ArchitectureLintContext]) {
        let productionContexts = contexts.filter { context in
            context.workspaceRelativePath?.hasPrefix(Self.productionSourcePrefix) == true
        }
        guard !productionContexts.isEmpty else {
            violationsBySourceIdentity = [:]
            return
        }

        let contractTypeNames = Self.contractTypeNames(in: productionContexts)
        let scans = productionContexts.map { context in
            let scanner = FilesystemObservationSlotRegistryOwnershipScanner(
                sourceIdentity: context.syntaxScopeSourceIdentity,
                workspaceRelativePath: context.workspaceRelativePath ?? "",
                contractTypeNames: contractTypeNames
            )
            scanner.walk(context.sourceFile)
            return scanner
        }

        var violations: [String: [FilesystemObservationOwnershipViolation]] = [:]
        func append(
            _ site: FilesystemObservationOwnershipSite,
            message: String
        ) {
            violations[site.sourceIdentity, default: []].append(
                FilesystemObservationOwnershipViolation(
                    position: site.position,
                    message: message
                )
            )
        }

        let ownerSites = scans.flatMap(\.ownerSites)
        let approvedOwnerSites = ownerSites.filter(\.isApprovedPrimaryShape)
        let registryContext = productionContexts.first(where: {
            $0.workspaceRelativePath == Self.registryPath
        })
        let contractsContext = productionContexts.first(where: {
            $0.workspaceRelativePath == Self.contractsPath
        })
        let ownershipAnchorContext =
            registryContext
            ?? contractsContext
            ?? productionContexts.first(where: { context in
                let path = context.workspaceRelativePath ?? ""
                return path.contains("FilesystemObservationSlotRegistry")
                    || context.source.contains(Self.registryName)
                    || FilesystemObservationLifetimeConstructor.allCases.contains { constructor in
                        context.source.contains(constructor.rawValue)
                    }
            })
        if let canonicalOwner = approvedOwnerSites.first {
            for ownerSite in ownerSites
            where ownerSite.site.sourceIdentity != canonicalOwner.site.sourceIdentity
                || ownerSite.site.position != canonicalOwner.site.position
            {
                append(
                    ownerSite.site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.primaryOwnerMessage
                )
            }
        } else if !ownerSites.isEmpty {
            for ownerSite in ownerSites {
                append(
                    ownerSite.site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.primaryOwnerMessage
                )
            }
        } else if let diagnosticContext = ownershipAnchorContext {
            append(
                FilesystemObservationOwnershipSite(
                    sourceIdentity: diagnosticContext.syntaxScopeSourceIdentity,
                    position: diagnosticContext.sourceFile.positionAfterSkippingLeadingTrivia
                ),
                message: FilesystemObservationSlotRegistryOwnershipRule.primaryOwnerMessage
            )
        }

        for scanner in scans {
            for site in scanner.ownerExtensionSites {
                append(
                    site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.ownerExtensionMessage
                )
            }
            for site in scanner.ownerAliasSites {
                append(
                    site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.ownerAliasMessage
                )
            }
            for site in scanner.constructorAliasSites {
                append(
                    site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.constructorAliasMessage
                )
            }
            for site in scanner.initializerEscapeSites {
                append(
                    site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.initializerEscapeMessage
                )
            }
            for site in scanner.mutableContractSites {
                append(
                    site,
                    message: FilesystemObservationSlotRegistryOwnershipRule.mutableContractMessage
                )
            }
        }

        let constructionSites = scans.flatMap(\.constructionSites)
        for constructionSite in constructionSites where !constructionSite.isApprovedTransition {
            append(
                constructionSite.site,
                message: FilesystemObservationSlotRegistryOwnershipRule.outsideTransitionMessage
            )
        }
        for constructor in FilesystemObservationLifetimeConstructor.allCases {
            let sites = constructionSites.filter { $0.constructor == constructor }
            if sites.isEmpty, ownershipAnchorContext != nil || !ownerSites.isEmpty {
                let diagnosticSite: FilesystemObservationOwnershipSite? =
                    approvedOwnerSites.first?.site
                    ?? ownerSites.first?.site
                    ?? ownershipAnchorContext.map { context in
                        FilesystemObservationOwnershipSite(
                            sourceIdentity: context.syntaxScopeSourceIdentity,
                            position: context.sourceFile.positionAfterSkippingLeadingTrivia
                        )
                    }
                if let diagnosticSite {
                    append(
                        diagnosticSite,
                        message: FilesystemObservationSlotRegistryOwnershipRule.constructorCardinalityMessage
                    )
                }
            } else if sites.count > 1 {
                let retainedSite = sites.first(where: \.isApprovedTransition) ?? sites[0]
                var retainedOne = false
                for site in sites {
                    if !retainedOne,
                        site.site.sourceIdentity == retainedSite.site.sourceIdentity,
                        site.site.position == retainedSite.site.position
                    {
                        retainedOne = true
                        continue
                    }
                    append(
                        site.site,
                        message: FilesystemObservationSlotRegistryOwnershipRule.constructorCardinalityMessage
                    )
                }
            }
        }

        violationsBySourceIdentity = violations.mapValues { violations in
            violations.sorted { left, right in
                if left.position != right.position {
                    return left.position < right.position
                }
                return left.message < right.message
            }
        }
    }

    private static func contractTypeNames(
        in contexts: [ArchitectureLintContext]
    ) -> Set<String> {
        guard let contractsContext = contexts.first(where: { $0.workspaceRelativePath == contractsPath }) else {
            return []
        }
        let collector = FilesystemObservationContractTypeNameCollector()
        collector.walk(contractsContext.sourceFile)
        var contractTypeNames = collector.typeNames
        for _ in 0...contexts.count {
            let aliasCollector = FilesystemObservationContractAliasNameCollector(
                contractTypeNames: contractTypeNames
            )
            for context in contexts {
                aliasCollector.walk(context.sourceFile)
            }
            let expandedTypeNames = contractTypeNames.union(aliasCollector.aliasNames)
            if expandedTypeNames == contractTypeNames {
                break
            }
            contractTypeNames = expandedTypeNames
        }
        return contractTypeNames
    }
}

private final class FilesystemObservationContractAliasNameCollector: SyntaxVisitor {
    private(set) var aliasNames: Set<String> = []
    private let contractTypeNames: Set<String>

    init(
        contractTypeNames: Set<String>,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.contractTypeNames = contractTypeNames
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let referencedNames = filesystemObservationIdentifierTokens(
            in: node.initializer.value.trimmedDescription
        )
        if !referencedNames.isDisjoint(with: contractTypeNames) {
            aliasNames.insert(node.name.text)
        }
        return .visitChildren
    }
}

private final class FilesystemObservationContractTypeNameCollector: SyntaxVisitor {
    private(set) var typeNames: Set<String> = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: node.name.text, node: node)
        return .visitChildren
    }

    private func collect(name: String, node: some SyntaxProtocol) {
        guard filesystemObservationIsTopLevel(node) else { return }
        typeNames.insert(name)
    }
}

private final class FilesystemObservationSlotRegistryOwnershipScanner: SyntaxVisitor {
    private(set) var ownerSites: [FilesystemObservationOwnerSite] = []
    private(set) var ownerExtensionSites: [FilesystemObservationOwnershipSite] = []
    private(set) var ownerAliasSites: [FilesystemObservationOwnershipSite] = []
    private(set) var constructionSites: [FilesystemObservationConstructionSite] = []
    private(set) var constructorAliasSites: [FilesystemObservationOwnershipSite] = []
    private(set) var initializerEscapeSites: [FilesystemObservationOwnershipSite] = []
    private(set) var mutableContractSites: [FilesystemObservationOwnershipSite] = []

    private let sourceIdentity: String
    private let workspaceRelativePath: String
    private let contractTypeNames: Set<String>

    init(
        sourceIdentity: String,
        workspaceRelativePath: String,
        contractTypeNames: Set<String>,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.sourceIdentity = sourceIdentity
        self.workspaceRelativePath = workspaceRelativePath
        self.contractTypeNames = contractTypeNames
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == FilesystemObservationSlotRegistryOwnershipInventory.registryName {
            recordOwner(
                node: node,
                isFinalClass: node.modifiers.contains { $0.name.text == "final" }
            )
        }
        if isCanonicalContractsSource,
            !filesystemObservationIsInsideExecutableScope(node)
        {
            recordMutableContract(node)
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNonClassOwner(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNonClassOwner(name: node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordNonClassOwner(name: node.name.text, node: node)
        if isCanonicalContractsSource,
            !filesystemObservationIsInsideExecutableScope(node)
        {
            recordMutableContract(node)
        }
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if filesystemObservationTerminalTypeName(node.extendedType.trimmedDescription)
            == FilesystemObservationSlotRegistryOwnershipInventory.registryName
        {
            ownerExtensionSites.append(site(node))
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard
            let constructor =
                filesystemObservationConstructor(
                    expressionDescription: node.calledExpression.trimmedDescription
                ) ?? contextualConstructor(of: node)
        else {
            return .visitChildren
        }
        constructionSites.append(
            FilesystemObservationConstructionSite(
                site: site(node.calledExpression),
                constructor: constructor,
                isApprovedTransition: isApprovedConstruction(node)
            )
        )
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let referencedNames = filesystemObservationIdentifierTokens(
            in: node.initializer.value.trimmedDescription
        )
        if referencedNames.contains(
            FilesystemObservationSlotRegistryOwnershipInventory.registryName
        ) {
            ownerAliasSites.append(site(node))
        }
        if !referencedNames.isDisjoint(
            with: Set(FilesystemObservationLifetimeConstructor.allCases.map(\.rawValue))
        ) {
            constructorAliasSites.append(site(node))
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if node.declName.baseName.text == "self",
            let base = node.base,
            filesystemObservationConstructor(expressionDescription: base.trimmedDescription) != nil
        {
            constructorAliasSites.append(site(node))
            return .visitChildren
        }
        guard node.declName.baseName.text == "init",
            let base = node.base,
            filesystemObservationConstructor(expressionDescription: base.trimmedDescription) != nil,
            !isCalledExpression(node)
        else {
            return .visitChildren
        }
        initializerEscapeSites.append(site(node))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindingSpecifier.text == "var",
            node.bindings.contains(where: filesystemObservationBindingIsMutable)
        else {
            return .visitChildren
        }
        if isCanonicalContractsSource {
            guard !filesystemObservationIsInsideExecutableScope(node) else {
                return .visitChildren
            }
            recordMutableContract(node)
            return .visitChildren
        }
        guard let ownerName = filesystemObservationNearestMemberOwnerName(of: node),
            contractTypeNames.contains(ownerName)
        else {
            return .visitChildren
        }
        recordMutableContract(node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.modifiers.contains(where: { $0.name.text == "mutating" })
        else {
            return .visitChildren
        }
        if isCanonicalContractsSource {
            recordMutableContract(node)
            return .visitChildren
        }
        guard let ownerName = filesystemObservationNearestMemberOwnerName(of: node),
            contractTypeNames.contains(ownerName)
        else {
            return .visitChildren
        }
        recordMutableContract(node)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let accessorBlock = node.accessorBlock,
            filesystemObservationAccessorBlockIsWritable(accessorBlock)
        else {
            return .visitChildren
        }
        if isCanonicalContractsSource {
            recordMutableContract(node)
            return .visitChildren
        }
        guard let ownerName = filesystemObservationNearestMemberOwnerName(of: node),
            contractTypeNames.contains(ownerName)
        else {
            return .visitChildren
        }
        recordMutableContract(node)
        return .visitChildren
    }

    private var isCanonicalContractsSource: Bool {
        workspaceRelativePath
            == FilesystemObservationSlotRegistryOwnershipInventory.contractsPath
    }

    private func contextualConstructor(
        of node: FunctionCallExprSyntax
    ) -> FilesystemObservationLifetimeConstructor? {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "init",
            memberAccess.base == nil || memberAccess.base?.trimmedDescription == "Self"
        else {
            return nil
        }

        var ancestor = node.parent
        while let current = ancestor {
            if let declaration = current.as(ExtensionDeclSyntax.self),
                let constructor = filesystemObservationConstructor(
                    expressionDescription: declaration.extendedType.trimmedDescription
                )
            {
                return constructor
            }
            if let declaration = current.as(FunctionDeclSyntax.self),
                let returnType = declaration.signature.returnClause?.type,
                let constructor = filesystemObservationConstructor(
                    expressionDescription: returnType.trimmedDescription
                )
            {
                return constructor
            }
            if let declaration = current.as(VariableDeclSyntax.self) {
                for binding in declaration.bindings {
                    guard let type = binding.typeAnnotation?.type,
                        let constructor = filesystemObservationConstructor(
                            expressionDescription: type.trimmedDescription
                        )
                    else {
                        continue
                    }
                    return constructor
                }
            }
            ancestor = current.parent
        }
        return nil
    }

    private func recordOwner(node: ClassDeclSyntax, isFinalClass: Bool) {
        ownerSites.append(
            FilesystemObservationOwnerSite(
                site: site(node),
                isApprovedPrimaryShape: workspaceRelativePath
                    == FilesystemObservationSlotRegistryOwnershipInventory.registryPath
                    && isFinalClass
                    && filesystemObservationIsTopLevel(node)
            )
        )
    }

    private func recordNonClassOwner(name: String, node: some SyntaxProtocol) {
        guard name == FilesystemObservationSlotRegistryOwnershipInventory.registryName else { return }
        ownerSites.append(
            FilesystemObservationOwnerSite(
                site: site(node),
                isApprovedPrimaryShape: false
            )
        )
    }

    private func recordMutableContract(_ node: some SyntaxProtocol) {
        mutableContractSites.append(site(node))
    }

    private func site(_ node: some SyntaxProtocol) -> FilesystemObservationOwnershipSite {
        FilesystemObservationOwnershipSite(
            sourceIdentity: sourceIdentity,
            position: node.positionAfterSkippingLeadingTrivia
        )
    }

    private func isCalledExpression(_ node: MemberAccessExprSyntax) -> Bool {
        guard let call = node.parent?.as(FunctionCallExprSyntax.self) else { return false }
        return call.calledExpression.id == node.id
    }

    private func isApprovedConstruction(_ node: FunctionCallExprSyntax) -> Bool {
        guard
            workspaceRelativePath
                == FilesystemObservationSlotRegistryOwnershipInventory.registryPath
        else {
            return false
        }

        var foundSelectedCase = false
        var ancestor = node.parent
        while let current = ancestor {
            if let switchCase = current.as(SwitchCaseSyntax.self) {
                guard !foundSelectedCase,
                    filesystemObservationIsExactSelectedCase(switchCase)
                else {
                    return false
                }
                foundSelectedCase = true
            } else if current.is(ClosureExprSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(SubscriptDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(StructDeclSyntax.self)
                || current.is(EnumDeclSyntax.self)
                || current.is(ActorDeclSyntax.self)
                || current.is(ExtensionDeclSyntax.self)
            {
                return false
            } else if let function = current.as(FunctionDeclSyntax.self) {
                guard function.name.text == "beginNativeLifetime", foundSelectedCase else {
                    return false
                }
                return filesystemObservationFunctionIsDirectRegistryMember(function)
            } else if current.is(ClassDeclSyntax.self) {
                return false
            }
            ancestor = current.parent
        }
        return false
    }
}

private func filesystemObservationConstructor(
    expressionDescription: String
) -> FilesystemObservationLifetimeConstructor? {
    var description = expressionDescription
    if description.hasSuffix(".init") {
        description.removeLast(".init".count)
    }
    let terminalName = filesystemObservationTerminalTypeName(description)
    return FilesystemObservationLifetimeConstructor.allCases.first { $0.rawValue == terminalName }
}

private func filesystemObservationIsExactSelectedCase(
    _ switchCase: SwitchCaseSyntax
) -> Bool {
    guard case .case(let caseLabel) = switchCase.label,
        caseLabel.caseItems.count == 1,
        let caseItem = caseLabel.caseItems.first
    else {
        return false
    }
    guard filesystemObservationSwitchUsesCanonicalSlotState(switchCase) else {
        return false
    }
    guard let expressionPattern = caseItem.pattern.as(ExpressionPatternSyntax.self) else {
        return false
    }
    let expression = expressionPattern.expression
    if let call = expression.as(FunctionCallExprSyntax.self) {
        return filesystemObservationDirectMemberName(call.calledExpression) == "selected"
    }
    return filesystemObservationDirectMemberName(expression) == "selected"
}

private func filesystemObservationSwitchUsesCanonicalSlotState(
    _ switchCase: SwitchCaseSyntax
) -> Bool {
    var ancestor = switchCase.parent
    while let current = ancestor {
        if let switchExpression = current.as(SwitchExprSyntax.self) {
            guard
                filesystemObservationDirectMemberName(switchExpression.subject) == "slotState",
                let function = filesystemObservationEnclosingFunction(switchExpression),
                filesystemObservationHasReservationParameter(function),
                filesystemObservationSwitchImmediatelyFollowsCanonicalLookup(
                    switchExpression,
                    in: function
                )
            else {
                return false
            }
            return true
        }
        if current.is(FunctionDeclSyntax.self)
            || current.is(InitializerDeclSyntax.self)
            || current.is(ClosureExprSyntax.self)
        {
            return false
        }
        ancestor = current.parent
    }
    return false
}

private func filesystemObservationEnclosingFunction(
    _ switchExpression: SwitchExprSyntax
) -> FunctionDeclSyntax? {
    var ancestor = switchExpression.parent
    while let current = ancestor {
        if let function = current.as(FunctionDeclSyntax.self) {
            return function
        }
        if current.is(InitializerDeclSyntax.self) || current.is(ClosureExprSyntax.self) {
            return nil
        }
        ancestor = current.parent
    }
    return nil
}

private func filesystemObservationHasReservationParameter(
    _ function: FunctionDeclSyntax
) -> Bool {
    function.signature.parameterClause.parameters.contains { parameter in
        let localName = parameter.secondName?.text ?? parameter.firstName.text
        return localName == "reservation"
    }
}

private func filesystemObservationSwitchImmediatelyFollowsCanonicalLookup(
    _ switchExpression: SwitchExprSyntax,
    in function: FunctionDeclSyntax
) -> Bool {
    let statements = Array(function.body?.statements ?? [])
    guard
        let precedingStatement = statements.last(where: {
            $0.positionAfterSkippingLeadingTrivia
                < switchExpression.positionAfterSkippingLeadingTrivia
        }),
        let guardStatement = precedingStatement.item.as(GuardStmtSyntax.self),
        guardStatement.conditions.count == 1,
        let condition = guardStatement.conditions.first?.condition.as(
            OptionalBindingConditionSyntax.self
        ),
        condition.bindingSpecifier.tokenKind == .keyword(.let),
        condition.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "slotState",
        let initializer = condition.initializer?.value.as(SubscriptCallExprSyntax.self),
        filesystemObservationDirectMemberName(initializer.calledExpression)
            == "statesByPhysicalSlotID",
        initializer.arguments.count == 1,
        let keyExpression = initializer.arguments.first?.expression.as(MemberAccessExprSyntax.self),
        keyExpression.declName.baseName.text == "physicalSlotID",
        let keyBase = keyExpression.base,
        filesystemObservationDirectMemberName(keyBase) == "reservation"
    else {
        return false
    }
    return true
}

private func filesystemObservationDirectMemberName(_ expression: ExprSyntax) -> String? {
    if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
        return memberAccess.declName.baseName.text
    }
    if let declarationReference = expression.as(DeclReferenceExprSyntax.self) {
        return declarationReference.baseName.text
    }
    return nil
}

private func filesystemObservationTerminalTypeName(_ description: String) -> String {
    description.split(separator: ".").last.map(String.init) ?? description
}

private func filesystemObservationIdentifierTokens(in description: String) -> Set<String> {
    Set(
        description.split { character in
            !character.isLetter && !character.isNumber && character != "_"
        }.map(String.init)
    )
}

private func filesystemObservationIsTopLevel(_ node: some SyntaxProtocol) -> Bool {
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

private func filesystemObservationIsInsideExecutableScope(
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

private func filesystemObservationFunctionIsDirectRegistryMember(
    _ function: FunctionDeclSyntax
) -> Bool {
    var ancestor = function.parent
    while let current = ancestor {
        if let owner = current.as(ClassDeclSyntax.self) {
            return owner.name.text
                == FilesystemObservationSlotRegistryOwnershipInventory.registryName
                && owner.modifiers.contains { $0.name.text == "final" }
                && filesystemObservationIsTopLevel(owner)
        }
        if current.is(FunctionDeclSyntax.self)
            || current.is(InitializerDeclSyntax.self)
            || current.is(SubscriptDeclSyntax.self)
            || current.is(AccessorDeclSyntax.self)
            || current.is(ClosureExprSyntax.self)
            || current.is(ExtensionDeclSyntax.self)
            || current.is(StructDeclSyntax.self)
            || current.is(EnumDeclSyntax.self)
            || current.is(ActorDeclSyntax.self)
        {
            return false
        }
        ancestor = current.parent
    }
    return false
}

private func filesystemObservationNearestMemberOwnerName(
    of node: some SyntaxProtocol
) -> String? {
    var ancestor = node.parent
    while let current = ancestor {
        if let declaration = current.as(ClassDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(StructDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(EnumDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(ActorDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = current.as(ExtensionDeclSyntax.self) {
            return filesystemObservationTerminalTypeName(
                declaration.extendedType.trimmedDescription
            )
        }
        if current.is(FunctionDeclSyntax.self)
            || current.is(InitializerDeclSyntax.self)
            || current.is(SubscriptDeclSyntax.self)
            || current.is(AccessorDeclSyntax.self)
            || current.is(ClosureExprSyntax.self)
        {
            return nil
        }
        ancestor = current.parent
    }
    return nil
}

private func filesystemObservationBindingIsMutable(_ binding: PatternBindingSyntax) -> Bool {
    guard let accessorBlock = binding.accessorBlock else {
        return true
    }
    return filesystemObservationAccessorBlockIsWritable(accessorBlock)
}

private func filesystemObservationAccessorBlockIsWritable(
    _ accessorBlock: AccessorBlockSyntax
) -> Bool {
    switch accessorBlock.accessors {
    case .getter:
        return false
    case .accessors(let accessors):
        return accessors.contains { accessor in
            let accessorName = accessor.accessorSpecifier.text
            return accessorName != "get" && accessorName != "_read"
        }
    }
}
