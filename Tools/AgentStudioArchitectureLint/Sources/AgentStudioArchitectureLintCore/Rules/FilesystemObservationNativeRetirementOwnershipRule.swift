import SwiftSyntax

struct FilesystemObservationNativeRetirementOwnershipRule: ArchitectureRule {
    static let registryOwnerMessage =
        "Filesystem observation unpublished final receipt and retirement authority construction must occur directly in FilesystemObservationSlotRegistry.finalizeUnpublishedNativeGeneration"
    static let nativeOwnerMessage =
        "Filesystem observation context finalization and release acknowledgement construction must occur directly in DarwinFSEventRegistrationNativeOwner"
    static let constructionEscapeMessage =
        "Filesystem observation native-retirement constructors must not be aliased or escape as metatype/initializer values"
    static let uuidV7Message =
        "Filesystem observation retirement authorities must be minted with a direct UUIDv7.generate() value"

    let id = "agentstudio_filesystem_observation_native_retirement_ownership"
    let severity = ArchitectureSeverity.error
    let message = Self.nativeOwnerMessage
    private let preparedViolations: [String: [NativeRetirementOwnershipViolation]]?

    init() {
        preparedViolations = nil
    }

    private init(
        preparedViolations: [String: [NativeRetirementOwnershipViolation]]
    ) {
        self.preparedViolations = preparedViolations
    }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        let productionContexts = contexts.filter { context in
            context.workspaceRelativePath?.hasPrefix("Sources/AgentStudio/") == true
        }
        var violations: [String: [NativeRetirementOwnershipViolation]] = [:]
        for context in productionContexts {
            let scanner = FilesystemObservationNativeRetirementOwnershipScanner(
                workspaceRelativePath: context.workspaceRelativePath ?? ""
            )
            scanner.walk(context.sourceFile)
            violations[context.syntaxScopeSourceIdentity] = scanner.violations.sorted {
                if $0.position != $1.position {
                    return $0.position < $1.position
                }
                return $0.message < $1.message
            }
        }
        return Self(preparedViolations: violations)
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard let preparedViolations else {
            return Self(preparedViolations: [:])
                .prepared(for: [context])
                .validate(context: context)
        }
        return preparedViolations[context.syntaxScopeSourceIdentity, default: []].map { violation in
            diagnostic(
                context: context,
                position: violation.position,
                message: violation.message
            )
        }
    }
}

private struct NativeRetirementOwnershipViolation: Sendable {
    let position: AbsolutePosition
    let message: String
}

private enum NativeRetirementProtectedConstructor: String, CaseIterable, Sendable {
    case unpublishedFinalReceipt = "FilesystemObservationUnpublishedFinalReceipt"
    case unpublishedRetirementAuthority =
        "FilesystemUnpublishedRetirementAuthority"
    case contextReleaseAuthority = "FilesystemObservationContextReleaseAuthority"
    case releasedContextFinalization = "FilesystemObservationReleasedContextFinalization"
    case neverMaterializedFinalization =
        "FilesystemObservationNeverMaterializedFinalization"
    case fenceBackedAcknowledgement =
        "FilesystemFenceContextReleaseAcknowledgement"
    case releasedRetainedContextAcknowledgement
    case neverMaterializedAcknowledgement

    var ownerMessage: String {
        switch self {
        case .unpublishedFinalReceipt, .unpublishedRetirementAuthority:
            FilesystemObservationNativeRetirementOwnershipRule.registryOwnerMessage
        case .contextReleaseAuthority, .releasedContextFinalization,
            .neverMaterializedFinalization, .fenceBackedAcknowledgement,
            .releasedRetainedContextAcknowledgement, .neverMaterializedAcknowledgement:
            FilesystemObservationNativeRetirementOwnershipRule.nativeOwnerMessage
        }
    }

    var requiresUUIDv7Value: Bool {
        switch self {
        case .unpublishedRetirementAuthority, .contextReleaseAuthority:
            true
        case .unpublishedFinalReceipt, .releasedContextFinalization,
            .neverMaterializedFinalization, .fenceBackedAcknowledgement,
            .releasedRetainedContextAcknowledgement, .neverMaterializedAcknowledgement:
            false
        }
    }

    static func explicitType(named name: String) -> Self? {
        allCases.first { constructor in
            switch constructor {
            case .releasedRetainedContextAcknowledgement,
                .neverMaterializedAcknowledgement:
                false
            default:
                constructor.rawValue == name
            }
        }
    }
}

// swiftlint:disable:next type_name
private final class FilesystemObservationNativeRetirementOwnershipScanner: SyntaxVisitor {
    private static let registryPath =
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistry+NativeRetirement.swift"
    private static let nativeOwnerPath =
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventRegistrationNativeOwner.swift"
    private static let registryTypeName = "FilesystemObservationSlotRegistry"
    private static let nativeOwnerTypeName = "DarwinFSEventRegistrationNativeOwner"
    private static let acknowledgementArgumentLabels = [
        "receipt", "finalization", "releaseAuthority",
    ]

    private(set) var violations: [NativeRetirementOwnershipViolation] = []
    private let workspaceRelativePath: String

    init(
        workspaceRelativePath: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.workspaceRelativePath = workspaceRelativePath
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let constructor = protectedConstructor(of: node) else {
            return .visitChildren
        }
        if !isApprovedConstruction(node, constructor: constructor) {
            record(node.calledExpression, message: constructor.ownerMessage)
        }
        if constructor.requiresUUIDv7Value,
            !hasDirectUUIDv7Value(node)
        {
            record(
                node.calledExpression,
                message: FilesystemObservationNativeRetirementOwnershipRule.uuidV7Message
            )
        }
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let referencedNames = nativeRetirementIdentifierTokens(
            in: node.initializer.value.trimmedDescription
        )
        guard !referencedNames.isDisjoint(with: protectedTypeNames) else {
            return .visitChildren
        }
        record(
            node,
            message: FilesystemObservationNativeRetirementOwnershipRule
                .constructionEscapeMessage
        )
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let base = node.base,
            protectedType(named: base.trimmedDescription) != nil
        else {
            return .visitChildren
        }
        if node.declName.baseName.text == "self"
            || (node.declName.baseName.text == "init" && !isCalledExpression(node))
        {
            record(
                node,
                message: FilesystemObservationNativeRetirementOwnershipRule
                    .constructionEscapeMessage
            )
        }
        return .visitChildren
    }

    private var protectedTypeNames: Set<String> {
        Set(
            NativeRetirementProtectedConstructor.allCases.compactMap { constructor in
                switch constructor {
                case .releasedRetainedContextAcknowledgement,
                    .neverMaterializedAcknowledgement:
                    nil
                default:
                    constructor.rawValue
                }
            }
        )
    }

    private func protectedConstructor(
        of node: FunctionCallExprSyntax
    ) -> NativeRetirementProtectedConstructor? {
        let expressionName = normalizedConstructorName(
            node.calledExpression.trimmedDescription
        )
        if let explicitConstructor = protectedType(named: expressionName) {
            return explicitConstructor
        }
        if let contextualConstructor = contextualInitializerConstructor(of: node) {
            return contextualConstructor
        }
        guard
            let memberName = FilesystemSlotConstructionPolicy.directMemberName(
                node.calledExpression
            ),
            node.arguments.map(\.label?.text) == Self.acknowledgementArgumentLabels
        else {
            return nil
        }
        switch memberName {
        case "releasedRetainedContext":
            return .releasedRetainedContextAcknowledgement
        case "neverMaterialized":
            return .neverMaterializedAcknowledgement
        default:
            return nil
        }
    }

    private func protectedType(named description: String) -> NativeRetirementProtectedConstructor? {
        NativeRetirementProtectedConstructor.explicitType(
            named: FilesystemSlotConstructionPolicy.terminalTypeName(
                normalizedConstructorName(description)
            )
        )
    }

    private func normalizedConstructorName(_ description: String) -> String {
        description.hasSuffix(".init")
            ? String(description.dropLast(".init".count))
            : description
    }

    private func contextualInitializerConstructor(
        of node: FunctionCallExprSyntax
    ) -> NativeRetirementProtectedConstructor? {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "init",
            memberAccess.base == nil || memberAccess.base?.trimmedDescription == "Self"
        else {
            return nil
        }
        var ancestor = node.parent
        while let current = ancestor {
            if let declaration = current.as(ExtensionDeclSyntax.self),
                let constructor = protectedType(named: declaration.extendedType.trimmedDescription)
            {
                return constructor
            }
            if let function = current.as(FunctionDeclSyntax.self),
                let returnType = function.signature.returnClause?.type,
                let constructor = protectedType(named: returnType.trimmedDescription)
            {
                return constructor
            }
            if let variable = current.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    guard let type = binding.typeAnnotation?.type,
                        let constructor = protectedType(named: type.trimmedDescription)
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

    private func isApprovedConstruction(
        _ node: FunctionCallExprSyntax,
        constructor: NativeRetirementProtectedConstructor
    ) -> Bool {
        switch constructor {
        case .unpublishedFinalReceipt, .unpublishedRetirementAuthority:
            return workspaceRelativePath == Self.registryPath
                && isDirectOwnerMethod(
                    node,
                    methodName: "finalizeUnpublishedNativeGeneration",
                    ownerTypeName: Self.registryTypeName
                )
        case .contextReleaseAuthority:
            return workspaceRelativePath == Self.nativeOwnerPath
                && (isDirectOwnerMethod(
                    node,
                    methodName: "makeReleasedContextAcknowledgement",
                    ownerTypeName: Self.nativeOwnerTypeName
                )
                    || isDirectOwnerMethod(
                        node,
                        methodName: "makeNeverMaterializedAcknowledgement",
                        ownerTypeName: Self.nativeOwnerTypeName
                    ))
        case .releasedContextFinalization, .fenceBackedAcknowledgement,
            .releasedRetainedContextAcknowledgement:
            return workspaceRelativePath == Self.nativeOwnerPath
                && isDirectOwnerMethod(
                    node,
                    methodName: "makeReleasedContextAcknowledgement",
                    ownerTypeName: Self.nativeOwnerTypeName
                )
        case .neverMaterializedFinalization, .neverMaterializedAcknowledgement:
            return workspaceRelativePath == Self.nativeOwnerPath
                && isDirectOwnerMethod(
                    node,
                    methodName: "makeNeverMaterializedAcknowledgement",
                    ownerTypeName: Self.nativeOwnerTypeName
                )
        }
    }

    private func isDirectOwnerMethod(
        _ node: FunctionCallExprSyntax,
        methodName: String,
        ownerTypeName: String
    ) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(ClosureExprSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(SubscriptDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(ExtensionDeclSyntax.self)
                || current.is(StructDeclSyntax.self)
                || current.is(EnumDeclSyntax.self)
                || current.is(ActorDeclSyntax.self)
            {
                return false
            }
            if let function = current.as(FunctionDeclSyntax.self) {
                guard function.name.text == methodName,
                    functionHasApprovedSignature(function, methodName: methodName)
                else { return false }
                if ownerTypeName == Self.registryTypeName {
                    return functionIsDirectRegistryRetirementExtensionMember(function)
                }
                return functionIsDirectPrimaryOwnerMember(
                    function,
                    ownerTypeName: ownerTypeName
                )
            }
            if current.is(ClassDeclSyntax.self) {
                return false
            }
            ancestor = current.parent
        }
        return false
    }

    private func functionIsDirectRegistryRetirementExtensionMember(
        _ function: FunctionDeclSyntax
    ) -> Bool {
        var ancestor = function.parent
        while let current = ancestor {
            if let owner = current.as(ExtensionDeclSyntax.self) {
                return FilesystemSlotConstructionPolicy.terminalTypeName(
                    owner.extendedType.trimmedDescription
                ) == Self.registryTypeName
                    && nativeRetirementIsTopLevel(owner)
            }
            if current.is(FunctionDeclSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(SubscriptDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(ClosureExprSyntax.self)
                || current.is(ClassDeclSyntax.self)
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

    private func functionHasApprovedSignature(
        _ function: FunctionDeclSyntax,
        methodName: String
    ) -> Bool {
        let parameters = Array(function.signature.parameterClause.parameters)
        switch methodName {
        case "finalizeUnpublishedNativeGeneration":
            guard parameters.count == 2 else { return false }
            return parameters[0].firstName.text == "_"
                && parameters[0].secondName?.text == "retiringLifetime"
                && FilesystemSlotConstructionPolicy.terminalTypeName(
                    parameters[0].type.trimmedDescription
                ) == "FilesystemObservationRetiringUnpublishedNativeLifetime"
                && parameters[1].firstName.text == "completion"
                && parameters[1].secondName == nil
                && FilesystemSlotConstructionPolicy.terminalTypeName(
                    parameters[1].type.trimmedDescription
                ) == "DarwinFSEventUnpublishedNativeCompletion"
        case "makeReleasedContextAcknowledgement",
            "makeNeverMaterializedAcknowledgement":
            guard parameters.count == 1 else { return false }
            return parameters[0].firstName.text == "for"
                && parameters[0].secondName?.text == "permit"
                && FilesystemSlotConstructionPolicy.terminalTypeName(
                    parameters[0].type.trimmedDescription
                ) == "FilesystemObservationNativeRetirementPermit"
        default:
            return false
        }
    }

    private func functionIsDirectPrimaryOwnerMember(
        _ function: FunctionDeclSyntax,
        ownerTypeName: String
    ) -> Bool {
        var ancestor = function.parent
        while let current = ancestor {
            if let owner = current.as(ClassDeclSyntax.self) {
                return owner.name.text == ownerTypeName
                    && owner.modifiers.contains { $0.name.text == "final" }
                    && nativeRetirementIsTopLevel(owner)
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

    private func hasDirectUUIDv7Value(_ node: FunctionCallExprSyntax) -> Bool {
        guard let valueArgument = node.arguments.first(where: { $0.label?.text == "value" }),
            let call = valueArgument.expression.as(FunctionCallExprSyntax.self)
        else {
            return false
        }
        return FilesystemSlotConstructionPolicy.isUUIDv7Generation(call)
    }

    private func isCalledExpression(_ node: MemberAccessExprSyntax) -> Bool {
        guard let call = node.parent?.as(FunctionCallExprSyntax.self) else { return false }
        return call.calledExpression.id == node.id
    }

    private func record(_ node: some SyntaxProtocol, message: String) {
        violations.append(
            NativeRetirementOwnershipViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: message
            )
        )
    }
}

private func nativeRetirementIdentifierTokens(in description: String) -> Set<String> {
    Set(
        description.split { character in
            !character.isLetter && !character.isNumber && character != "_"
        }.map(String.init)
    )
}

private func nativeRetirementIsTopLevel(_ node: some SyntaxProtocol) -> Bool {
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
