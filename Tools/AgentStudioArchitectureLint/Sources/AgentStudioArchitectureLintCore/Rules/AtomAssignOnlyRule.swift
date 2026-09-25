import SwiftSyntax

/// Atom methods may assign, suppress equal writes, and keep observation
/// indexes — nothing else. File, process, network or database access,
/// timers, dispatch queues, new tasks, observation tracking and collection
/// sorts inside a MainActor atom put I/O, scheduling or derivation on the
/// publication owner. Those belong in a repository, coordinator or derived
/// projection (`docs/architecture/state/atom_persistence_boundaries.md#need-an-atom`).
///
/// Scope: types named `*Atom` (and extensions of them) in files under
/// `/State/MainActor/Atoms/`. `*Derived` readers, rule modules and free
/// `nonisolated` index builders in those folders are outside the shape.
struct AtomAssignOnlyRule: ArchitectureRule {
    let id = "agentstudio_atom_assign_only"
    let severity = ArchitectureSeverity.error
    let message =
        "An atom may only assign and keep observation indexes; move I/O, scheduling, tasks, observation "
        + "tracking and sorting to a repository, coordinator or derived projection"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.normalizedPath.contains("/State/MainActor/Atoms/") else {
            return []
        }
        let visitor = AtomSideEffectVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class AtomSideEffectVisitor: SyntaxVisitor {
    private static let deniedTypeNames: Set<String> = [
        "FileManager", "Process", "URLSession", "Timer", "DispatchQueue",
    ]
    private static let deniedCalleeNames: Set<String> = ["withObservationTracking", "sorted", "sort"]

    private(set) var positions: [AbsolutePosition] = []
    /// Innermost-last names of the enclosing type declarations.
    private var typeNames: [String] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    private var isInsideAtom: Bool {
        typeNames.last?.hasSuffix("Atom") == true
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeNames.removeLast()
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard isInsideAtom, !node.isMemberAccessName else {
            return
        }
        let name = node.baseName.text
        if Self.deniedTypeNames.contains(name) || name.hasPrefix("sqlite3_") {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard isInsideAtom else {
            return
        }
        if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task"
            || node.calledExpression.isTaskDetachedReference
        {
            positions.append(node.positionAfterSkippingLeadingTrivia)
            return
        }
        if let calleeName = node.calleeName, Self.deniedCalleeNames.contains(calleeName) {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
    }
}

extension ExprSyntax {
    /// The detached-task factory, however `Task` is spelled.
    fileprivate var isTaskDetachedReference: Bool {
        guard let member = self.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "detached" else {
            return false
        }
        return member.base?.isTaskTypeReference == true
    }
}
