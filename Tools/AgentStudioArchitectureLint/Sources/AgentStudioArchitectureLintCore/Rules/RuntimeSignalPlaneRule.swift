import SwiftSyntax

struct RuntimeSignalPlaneRule: ArchitectureRule {
    enum AdmissionProtectedRegionCategory: String, CaseIterable, Sendable {
        case producer
        case binding
        case drain
        case diagnostics
        case replayCapture
        case replayCompletion
        case cleanupDetachment
        case recovery
        case invalidation
    }

    enum AdmissionProtectedRegionInspectionScope: String, Sendable {
        case entrypointLockClosures
        case entireDeclaration
    }

    struct AdmissionProtectedRegionDescriptor: Equatable, Sendable {
        let declarationName: String
        let category: AdmissionProtectedRegionCategory
        let inspectionScope: AdmissionProtectedRegionInspectionScope

        init(
            declarationName: String,
            category: AdmissionProtectedRegionCategory,
            inspectionScope: AdmissionProtectedRegionInspectionScope = .entireDeclaration
        ) {
            self.declarationName = declarationName
            self.category = category
            self.inspectionScope = inspectionScope
        }
    }

    static let admissionProtectedRegionManifest: [AdmissionProtectedRegionDescriptor] = [
        AdmissionProtectedRegionDescriptor(
            declarationName: "offer",
            category: .producer,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "attemptOffer",
            category: .producer,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "completeContractedOffer",
            category: .producer
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "completeRetainedOffer",
            category: .producer
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "commitOfferIntoExistingGap",
            category: .producer
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "bindConsumer",
            category: .binding,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "takeDrain",
            category: .drain,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(declarationName: "takeLease", category: .drain),
        AdmissionProtectedRegionDescriptor(declarationName: "extractLease", category: .drain),
        AdmissionProtectedRegionDescriptor(
            declarationName: "acknowledge",
            category: .drain,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "diagnostics",
            category: .diagnostics,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "oldestRetainedAt",
            category: .diagnostics
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "oldestRecoveryAt",
            category: .diagnostics
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "oldestRetainedTimestamp",
            category: .diagnostics
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "ageMeasurement",
            category: .diagnostics
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "captureReplayState",
            category: .replayCapture
        ),
        AdmissionProtectedRegionDescriptor(declarationName: "captureReplay", category: .replayCapture),
        AdmissionProtectedRegionDescriptor(
            declarationName: "replay",
            category: .replayCapture,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "followingFacts",
            category: .replayCapture
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "releaseReplayReader",
            category: .replayCompletion
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "performCleanup",
            category: .cleanupDetachment,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "detachCleanup",
            category: .cleanupDetachment
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "detachCleanupTurn",
            category: .cleanupDetachment
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "detachRetiredCleanup",
            category: .cleanupDetachment
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "resynchronize",
            category: .recovery,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(declarationName: "commitGap", category: .recovery),
        AdmissionProtectedRegionDescriptor(declarationName: "widenGap", category: .recovery),
        AdmissionProtectedRegionDescriptor(
            declarationName: "invalidate",
            category: .invalidation,
            inspectionScope: .entrypointLockClosures
        ),
        AdmissionProtectedRegionDescriptor(
            declarationName: "invalidateState",
            category: .invalidation
        ),
    ]

    static func containsTopLevelOrderedFactJournalOwner(
        in sourceFile: SourceFileSyntax
    ) -> Bool {
        OrderedFactJournalLexicalOwnershipClassifier.containsTopLevelOwner(
            in: sourceFile
        )
    }

    let id = "agentstudio_runtime_signal_plane"
    let severity = ArchitectureSeverity.error
    let message =
        "Admission protected-state regions must use indexed O(1) access or loops bounded by typed lease or cleanup quanta"
    private let protectedRegionTokenMessage =
        "Admission protected-region token must remain noncopyable, borrowed by the wrapper, and unable to return a noncopyable result"
    private let journalLexicalOwnershipMessage =
        "OrderedFactJournal raw state, lock, and protected token access must remain in its lexical owner"
    private let journalOwnerResponsibilityMessage =
        "OrderedFactJournal owner may contain only lexical raw-custody declarations and typed owner entrypoints"
    private let journalDeclarationAliasIndex: OrderedFactJournalDeclarationAliasIndex?

    init(journalDeclarationAliasIndex: OrderedFactJournalDeclarationAliasIndex? = nil) {
        self.journalDeclarationAliasIndex = journalDeclarationAliasIndex
    }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        Self(
            journalDeclarationAliasIndex: OrderedFactJournalDeclarationAliasIndex(
                contexts: contexts
            )
        )
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.isProductionAdmissionSource else {
            return []
        }

        let inspectionScopesByDeclarationName = Dictionary(
            uniqueKeysWithValues: Self.admissionProtectedRegionManifest.map {
                ($0.declarationName, $0.inspectionScope)
            }
        )
        let typedQuantumBindings = TypedAdmissionQuantumBindingVisitor()
        typedQuantumBindings.walk(context.sourceFile)
        let visitor = AdmissionProtectedDeclarationVisitor(
            inspectionScopesByDeclarationName: inspectionScopesByDeclarationName,
            typedQuantumBindings: typedQuantumBindings.bindings,
            message: message
        )
        visitor.walk(context.sourceFile)
        var diagnostics = visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
        let tokenShapeVisitor = AdmissionProtectedRegionTokenShapeVisitor(
            message: protectedRegionTokenMessage
        )
        tokenShapeVisitor.walk(context.sourceFile)
        diagnostics.append(
            contentsOf: tokenShapeVisitor.violations.map {
                diagnostic(context: context, position: $0.position, message: $0.message)
            }
        )
        let journalOwnershipClassifier = OrderedFactJournalLexicalOwnershipClassifier(
            path: context.path,
            sourceIdentity: context.syntaxScopeSourceIdentity,
            sourceFile: context.sourceFile,
            declarationAliasIndex: journalDeclarationAliasIndex
                ?? OrderedFactJournalDeclarationAliasIndex(sourceFile: context.sourceFile),
            lexicalOwnershipMessage: journalLexicalOwnershipMessage,
            ownerResponsibilityMessage: journalOwnerResponsibilityMessage
        )
        diagnostics.append(
            contentsOf: journalOwnershipClassifier.violations.map {
                diagnostic(context: context, position: $0.position, message: $0.message)
            }
        )
        return diagnostics
    }
}

private final class AdmissionProtectedRegionTokenShapeVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let message: String

    init(
        message: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.message = message
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == "AdmissionProtectedRegionToken" else {
            return .visitChildren
        }
        let inheritedTypes =
            node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        guard
            inheritedTypes.contains("~Copyable"),
            inheritedTypes.contains("~Escapable") == false
        else {
            recordViolation(at: node.name.positionAfterSkippingLeadingTrivia)
            return .skipChildren
        }
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == "withToken" else { return .visitChildren }
        let parameterTypes = node.signature.parameterClause.parameters.map {
            $0.type.trimmedDescription
        }
        let genericParameters = node.genericParameterClause?.trimmedDescription
        let genericWhereClause = node.genericWhereClause?.trimmedDescription
        let returnType = node.signature.returnClause?.type.trimmedDescription
        guard
            parameterTypes == ["(borrowing AdmissionProtectedRegionToken) throws -> Result"],
            genericParameters == "<Result>",
            genericWhereClause == nil,
            returnType == "Result"
        else {
            recordViolation(at: node.name.positionAfterSkippingLeadingTrivia)
            return .skipChildren
        }
        return .skipChildren
    }

    private func recordViolation(at position: AbsolutePosition) {
        violations.append(ArchitectureViolation(position: position, message: message))
    }
}

private enum TypedAdmissionQuantum: Sendable {
    case gatherLimits
    case cleanup
    case orderedFactDrain

    init?(typeDescription: String) {
        switch typeDescription {
        case "GatherMailboxLimits": self = .gatherLimits
        case "AdmissionCleanupQuantum": self = .cleanup
        case "OrderedFactDrainQuantum": self = .orderedFactDrain
        default: return nil
        }
    }

    func permits(memberName: String) -> Bool {
        switch self {
        case .gatherLimits:
            return [
                "maximumContributionsPerLease",
                "maximumItemsPerLease",
                "maximumBytesPerLease",
            ].contains(memberName)
        case .cleanup:
            return ["maximumEntries", "maximumBytes"].contains(memberName)
        case .orderedFactDrain:
            return memberName == "maximumFacts"
        }
    }
}

private final class AdmissionProtectedDeclarationVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let inspectionScopesByDeclarationName:
        [String: RuntimeSignalPlaneRule.AdmissionProtectedRegionInspectionScope]
    private let typedQuantumBindings: [String: TypedAdmissionQuantum]
    private let message: String

    init(
        inspectionScopesByDeclarationName: [String: RuntimeSignalPlaneRule.AdmissionProtectedRegionInspectionScope],
        typedQuantumBindings: [String: TypedAdmissionQuantum],
        message: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.inspectionScopesByDeclarationName = inspectionScopesByDeclarationName
        self.typedQuantumBindings = typedQuantumBindings
        self.message = message
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard
            let inspectionScope = inspectionScopesByDeclarationName[node.name.text],
            let body = node.body
        else {
            return .visitChildren
        }
        inspectProtectedDeclaration(
            body,
            inspectionScope: inspectionScope,
            typedQuantumParameters: typedQuantumBindings.merging(
                typedQuantumParameters(in: node),
                uniquingKeysWith: { _, parameter in parameter }
            )
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard
                let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                let inspectionScope = inspectionScopesByDeclarationName[
                    identifier.identifier.text
                ],
                let accessorBlock = binding.accessorBlock
            else {
                continue
            }
            inspectProtectedDeclaration(
                accessorBlock,
                inspectionScope: inspectionScope,
                typedQuantumParameters: typedQuantumBindings
            )
        }
        return .skipChildren
    }

    private func typedQuantumParameters(
        in function: FunctionDeclSyntax
    ) -> [String: TypedAdmissionQuantum] {
        var parameters: [String: TypedAdmissionQuantum] = [:]
        for parameter in function.signature.parameterClause.parameters {
            guard
                let quantum = TypedAdmissionQuantum(
                    typeDescription: parameter.type.trimmedDescription
                )
            else {
                continue
            }
            let parameterName = parameter.secondName?.text ?? parameter.firstName.text
            guard parameterName != "_" else { continue }
            parameters[parameterName] = quantum
        }
        return parameters
    }

    private func inspectProtectedRegion(
        _ node: some SyntaxProtocol,
        typedQuantumParameters: [String: TypedAdmissionQuantum]
    ) {
        let visitor = AdmissionProtectedWorkVisitor(
            typedQuantumParameters: typedQuantumParameters,
            message: message
        )
        visitor.walk(node)
        violations.append(contentsOf: visitor.violations)
    }

    private func inspectProtectedDeclaration(
        _ node: some SyntaxProtocol,
        inspectionScope: RuntimeSignalPlaneRule.AdmissionProtectedRegionInspectionScope,
        typedQuantumParameters: [String: TypedAdmissionQuantum]
    ) {
        guard inspectionScope == .entrypointLockClosures else {
            inspectProtectedRegion(
                node,
                typedQuantumParameters: typedQuantumParameters
            )
            return
        }

        let lockClosureVisitor = AdmissionLockClosureVisitor()
        lockClosureVisitor.walk(node)
        guard lockClosureVisitor.lockClosures.isEmpty == false else { return }
        for lockClosure in lockClosureVisitor.lockClosures {
            inspectProtectedRegion(
                lockClosure,
                typedQuantumParameters: typedQuantumParameters
            )
        }
    }
}

private final class AdmissionLockClosureVisitor: SyntaxVisitor {
    private(set) var lockClosures: [ClosureExprSyntax] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard
            let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "withLock"
        else {
            return
        }
        if let trailingClosure = node.trailingClosure {
            lockClosures.append(trailingClosure)
        }
        for argument in node.arguments {
            if let closure = argument.expression.as(ClosureExprSyntax.self) {
                lockClosures.append(closure)
            }
        }
    }
}

private final class TypedAdmissionQuantumBindingVisitor: SyntaxVisitor {
    private(set) var bindings: [String: TypedAdmissionQuantum] = [:]

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard
                let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                let typeDescription = binding.typeAnnotation?.type.trimmedDescription,
                let quantum = TypedAdmissionQuantum(typeDescription: typeDescription)
            else {
                continue
            }
            bindings[identifier.identifier.text] = quantum
        }
    }
}

private final class AdmissionProtectedWorkVisitor: SyntaxVisitor {
    private static let forbiddenCollectionCalls: Set<String> = [
        "compactMap",
        "filter",
        "forEach",
        "map",
        "reduce",
        "removeAll",
        "removeFirst",
        "removeSubrange",
        "sort",
        "sorted",
    ]
    private static let forbiddenMaterializers: Set<String> = ["Array", "Dictionary", "Set"]
    private static let forbiddenFleetMembers: Set<String> = [
        "declaredKeysBySlot",
        "declaredSlotsByKey",
        "keyStates",
        "records",
    ]

    private(set) var violations: [ArchitectureViolation] = []
    private let typedQuantumParameters: [String: TypedAdmissionQuantum]
    private let message: String

    init(
        typedQuantumParameters: [String: TypedAdmissionQuantum],
        message: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.typedQuantumParameters = typedQuantumParameters
        self.message = message
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        guard
            isTypedQuantumBoundedSequence(node.sequence)
                || containsForbiddenFleetMember(node.sequence) == false
        else {
            recordViolation(at: node.forKeyword.positionAfterSkippingLeadingTrivia)
            return .visitChildren
        }
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        guard hasTypedQuantumBound(in: node.conditions) else {
            recordViolation(at: node.whileKeyword.positionAfterSkippingLeadingTrivia)
            return .visitChildren
        }
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        guard isTypedQuantumComparison(node.condition) else {
            recordViolation(at: node.repeatKeyword.positionAfterSkippingLeadingTrivia)
            return .visitChildren
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let memberName = memberAccess.declName.baseName.text
            if Self.forbiddenCollectionCalls.contains(memberName),
                let base = memberAccess.base,
                containsForbiddenFleetMember(base)
            {
                recordViolation(at: memberAccess.positionAfterSkippingLeadingTrivia)
            }
            return
        }
        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self),
            Self.forbiddenMaterializers.contains(reference.baseName.text),
            node.arguments.contains(where: { containsForbiddenFleetMember($0.expression) })
        {
            recordViolation(at: reference.positionAfterSkippingLeadingTrivia)
        }
    }

    private func containsForbiddenFleetMember(_ node: some SyntaxProtocol) -> Bool {
        node.tokens(viewMode: .sourceAccurate).contains { token in
            Self.forbiddenFleetMembers.contains(token.text)
        }
    }

    private func hasTypedQuantumBound(in conditions: ConditionElementListSyntax) -> Bool {
        conditions.contains { condition in
            guard case .expression(let expression) = condition.condition else { return false }
            return isTypedQuantumComparison(expression)
        }
    }

    private func isTypedQuantumBoundedSequence(_ sequence: ExprSyntax) -> Bool {
        guard
            let call = sequence.as(FunctionCallExprSyntax.self),
            let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "prefix"
        else {
            return false
        }
        return call.arguments.contains { argument in
            containsTypedQuantumMember(argument.expression)
        }
    }

    private func isTypedQuantumComparison(_ expression: ExprSyntax) -> Bool {
        let tokens = Array(expression.tokens(viewMode: .sourceAccurate))
        guard tokens.contains(where: { $0.text == "||" }) == false else { return false }
        let comparisonPositions = tokens.compactMap { token -> AbsolutePosition? in
            guard token.text == "<" || token.text == "<=" else { return nil }
            return token.positionAfterSkippingLeadingTrivia
        }
        guard comparisonPositions.isEmpty == false else { return false }

        let memberPositions = typedQuantumMemberPositions(expression)
        return comparisonPositions.contains { comparisonPosition in
            memberPositions.contains { memberPosition in
                comparisonPosition < memberPosition
            }
        }
    }

    private func containsTypedQuantumMember(_ node: some SyntaxProtocol) -> Bool {
        typedQuantumMemberPositions(node).isEmpty == false
    }

    private func typedQuantumMemberPositions(
        _ node: some SyntaxProtocol
    ) -> [AbsolutePosition] {
        let visitor = TypedQuantumMemberVisitor(typedQuantumParameters: typedQuantumParameters)
        visitor.walk(node)
        return visitor.typedQuantumMemberPositions
    }

    private func recordViolation(at position: AbsolutePosition) {
        violations.append(ArchitectureViolation(position: position, message: message))
    }
}

private final class TypedQuantumMemberVisitor: SyntaxVisitor {
    private(set) var typedQuantumMemberPositions: [AbsolutePosition] = []
    private let typedQuantumParameters: [String: TypedAdmissionQuantum]

    init(
        typedQuantumParameters: [String: TypedAdmissionQuantum],
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.typedQuantumParameters = typedQuantumParameters
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard
            let base = node.base?.as(DeclReferenceExprSyntax.self),
            let quantum = typedQuantumParameters[base.baseName.text],
            quantum.permits(memberName: node.declName.baseName.text)
        else {
            return .visitChildren
        }
        typedQuantumMemberPositions.append(node.positionAfterSkippingLeadingTrivia)
        return .skipChildren
    }
}
