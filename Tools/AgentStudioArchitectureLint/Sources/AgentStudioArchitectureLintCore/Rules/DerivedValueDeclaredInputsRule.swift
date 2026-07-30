import SwiftSyntax

struct DerivedValueDeclaredInputsRule: ArchitectureRule {
    let id = "agentstudio_derived_value_declared_inputs"
    let severity = ArchitectureSeverity.error
    let message = "DerivedValue compute closures must use declared input revisions instead of reading atoms directly"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let helperCollector = DerivedValueHiddenInputHelperCollector()
        helperCollector.walk(context.sourceFile)

        let visitor = DerivedValueInputVisitor(
            hiddenInputHelperNames: helperCollector.hiddenInputHelperNames,
            requiresApprovedConstructionOwner: Self.isProductSource(context.path),
            isApprovedConstructionFile: context.normalizedPath.hasSuffix(
                "/Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift"
            )
        )
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }

    private static func isProductSource(_ path: String) -> Bool {
        path.hasPrefix("Sources/AgentStudio/")
            || path.contains("/Sources/AgentStudio/")
    }
}

private final class DerivedValueInputVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let hiddenInputHelperNames: Set<String>
    private let requiresApprovedConstructionOwner: Bool
    private let isApprovedConstructionFile: Bool
    private var classNames: [String] = []
    private var variableContexts: [VariableContext] = []
    private var approvedConstructionCount = 0

    init(
        hiddenInputHelperNames: Set<String>,
        requiresApprovedConstructionOwner: Bool,
        isApprovedConstructionFile: Bool,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.hiddenInputHelperNames = hiddenInputHelperNames
        self.requiresApprovedConstructionOwner = requiresApprovedConstructionOwner
        self.isApprovedConstructionFile = isApprovedConstructionFile
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        classNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        classNames.removeLast()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let bindingName =
            node.bindings.count == 1
            ? node.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            : nil
        variableContexts.append(
            VariableContext(
                bindingName: bindingName,
                isPrivate: node.modifiers.contains {
                    $0.name.text == "private" && $0.detail == nil
                },
                isLazy: node.modifiers.contains { $0.name.text == "lazy" }
            )
        )
        return .visitChildren
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        variableContexts.removeLast()
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard node.calledExpression.isDerivedValueConstructorReference else {
            return
        }

        if requiresApprovedConstructionOwner {
            let variableContext = variableContexts.last
            let isApprovedDeclaration =
                isApprovedConstructionFile
                && classNames.last == "WorkspaceTabLayoutAtom"
                && variableContext?.bindingName == "richTabSnapshotValue"
                && variableContext?.isPrivate == true
                && variableContext?.isLazy == true
            if isApprovedDeclaration {
                approvedConstructionCount += 1
                if approvedConstructionCount > 1 {
                    violations.append(
                        ArchitectureViolation(
                            position: node.positionAfterSkippingLeadingTrivia,
                            message:
                                "Production must contain exactly one private lazy richTabSnapshotValue DerivedValue"
                        )
                    )
                }
            } else {
                violations.append(
                    ArchitectureViolation(
                        position: node.positionAfterSkippingLeadingTrivia,
                        message:
                            "Production DerivedValue construction must be the private lazy richTabSnapshotValue in WorkspaceTabLayoutAtom"
                    )
                )
            }
        }

        let closures =
            node.arguments.compactMap { $0.expression.as(ClosureExprSyntax.self) }
            + [node.trailingClosure].compactMap { $0 }
        for closure in closures {
            let visitor = DerivedValueClosureVisitor(hiddenInputHelperNames: hiddenInputHelperNames)
            visitor.walk(closure)
            violations.append(contentsOf: visitor.violations)
        }
    }

    private struct VariableContext {
        let bindingName: String?
        let isPrivate: Bool
        let isLazy: Bool
    }
}

extension ExprSyntax {
    fileprivate var isDerivedValueConstructorReference: Bool {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "DerivedValue"
        }
        if let memberAccess = self.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text == "DerivedValue"
        }
        if let specialization = self.as(GenericSpecializationExprSyntax.self) {
            return specialization.expression.isDerivedValueConstructorReference
        }
        return false
    }
}

private final class DerivedValueHiddenInputHelperCollector: SyntaxVisitor {
    private(set) var hiddenInputHelperNames = Set<String>()

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        guard let body = node.body else {
            return
        }

        let visitor = DerivedValueClosureVisitor(hiddenInputHelperNames: [])
        visitor.walk(body)
        if !visitor.violations.isEmpty {
            hiddenInputHelperNames.insert(node.name.text)
        }
    }
}

private final class DerivedValueClosureVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let hiddenInputHelperNames: Set<String>
    private let deniedNames = Set(["atom", "CoreAtoms", "CoreAtomScope"])

    init(hiddenInputHelperNames: Set<String>, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.hiddenInputHelperNames = hiddenInputHelperNames
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard !node.isMemberAccessName else {
            return
        }
        guard deniedNames.contains(node.baseName.text) || hiddenInputHelperNames.contains(node.baseName.text) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "DerivedValue compute closures must declare atom inputs instead of reading atoms directly"
            )
        )
    }
}
