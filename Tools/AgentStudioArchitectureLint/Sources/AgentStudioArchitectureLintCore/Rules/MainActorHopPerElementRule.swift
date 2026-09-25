import SwiftSyntax

/// A stream is admitted and contracted off MainActor; MainActor applies only
/// changed outcomes (`docs/architecture/runtime/pane_runtime_eventbus_design.md`,
/// "Admission And Hop Shape"). Two shapes break that:
///
/// - (a) a hop to MainActor inside a `for await` body — one MainActor turn per
///   element;
/// - (b) a `for await` that already runs on MainActor (inside
///   `Task { @MainActor`, or in a `@MainActor` type or method) and acts on
///   every element, instead of first comparing the element with what it last
///   published: `guard element != stored else { continue }`,
///   `if element == stored { continue }`, or the action nested in
///   `if element != stored`.
///
/// Leading `let` bindings and cancellation checks may come before the guard.
/// A comparison that does not decide whether the action runs does not count.
/// The thin adapters the architecture prescribes are named owners in
/// `ArchitectureAllowlists.mainActorPerElementAdapters`. Scope is product
/// sources; a test awaiting events on MainActor is not a publication path.
struct MainActorHopPerElementRule: ArchitectureRule {
    let id = "agentstudio_mainactor_hop_per_element"
    let severity = ArchitectureSeverity.error
    let message =
        "MainActor work per stream element: contract the stream off MainActor and publish only changed "
        + "outcomes, or guard each element against the last published value"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.isUnderSourcesDirectory else {
            return []
        }
        let visitor = PerElementHopVisitor(path: context.normalizedPath)
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class PerElementHopVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []
    private let path: String

    init(path: String) {
        self.path = path
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: ForStmtSyntax) {
        guard node.awaitKeyword != nil else {
            return
        }
        if let function = node.enclosingFunction,
            ArchitectureAllowlists.mainActorPerElementAdapters.contains(where: {
                path.hasSuffix($0.pathSuffix) && function.name.text == $0.functionName
            })
        {
            return
        }

        let hopVisitor = MainActorHopVisitor()
        hopVisitor.walk(node.body)
        positions.append(contentsOf: hopVisitor.positions)

        if node.runsOnMainActor, !node.guardsElementAgainstLastPublished {
            positions.append(node.forKeyword.positionAfterSkippingLeadingTrivia)
        }
    }
}

/// `MainActor.run` calls and `@MainActor` closures. A nested `for await` is
/// judged on its own visit, so its hops are not counted twice.
final class MainActorHopVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        node.awaitKeyword == nil ? .visitChildren : .skipChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "run",
            member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "MainActor"
        else {
            return
        }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        if node.isMainActorClosure {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
    }
}

extension ClosureExprSyntax {
    var isMainActorClosure: Bool {
        signature?.attributes.contains { $0.trimmedDescription == "@MainActor" } == true
    }

    /// The closure is the body of `Task { … }` or `Task(priority:) { … }`,
    /// which inherits the enclosing isolation.
    fileprivate var isInheritingTaskBody: Bool {
        let call =
            parent?.as(FunctionCallExprSyntax.self)
            ?? parent?.parent?.parent?.as(FunctionCallExprSyntax.self)
        return call?.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task"
    }
}

extension ForStmtSyntax {
    /// Lexically on MainActor: the nearest isolation-deciding ancestor is a
    /// `@MainActor` closure, method or type. An unannotated `Task { }` body
    /// inherits its context; any other closure, `nonisolated` or
    /// `@concurrent` method, or actor ends the search as off MainActor.
    fileprivate var runsOnMainActor: Bool {
        var current = parent
        while let node = current {
            if let closure = node.as(ClosureExprSyntax.self) {
                if closure.isMainActorClosure {
                    return true
                }
                if !closure.isInheritingTaskBody {
                    return false
                }
            } else if let function = node.as(FunctionDeclSyntax.self) {
                if function.attributes.containsAttribute("@MainActor") {
                    return true
                }
                if function.attributes.containsAttribute("@concurrent")
                    || function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) })
                {
                    return false
                }
            } else if let declaration = node.asProtocol(DeclGroupSyntax.self) {
                return !node.is(ActorDeclSyntax.self) && declaration.attributes.containsAttribute("@MainActor")
            }
            current = node.parent
        }
        return false
    }

    /// The loop body, after leading bindings and cancellation checks, starts
    /// with a controlling guard on the element: `guard element != stored else
    /// { exit }`, `if element == stored { exit }`, or is exactly
    /// `if element != stored { action }`.
    fileprivate var guardsElementAgainstLastPublished: Bool {
        guard let elementName = pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return false
        }
        let localNames = LocalBindingNameCollector.names(in: Syntax(body)).union([elementName])
        let statements = body.statements.drop { $0.isBindingOrCancellationCheck }
        guard let first = statements.first else {
            return false
        }
        if let guardStatement = first.item.as(GuardStmtSyntax.self) {
            return guardStatement.body.exitsScope
                && guardStatement.conditions.comparesElement(elementName, operator: "!=", localNames: localNames)
        }
        guard let ifExpression = first.ifExpression else {
            return false
        }
        if ifExpression.body.exitsScope,
            ifExpression.conditions.comparesElement(elementName, operator: "==", localNames: localNames)
        {
            return true
        }
        return statements.count == 1
            && ifExpression.conditions.comparesElement(elementName, operator: "!=", localNames: localNames)
    }
}

extension CodeBlockItemSyntax {
    fileprivate var isBindingOrCancellationCheck: Bool {
        if item.is(VariableDeclSyntax.self) {
            return true
        }
        let conditionText: String
        if let guardStatement = item.as(GuardStmtSyntax.self) {
            conditionText = guardStatement.conditions.trimmedDescription
        } else if let ifExpression = self.ifExpression {
            conditionText = ifExpression.conditions.trimmedDescription
        } else {
            return false
        }
        return conditionText.contains("isCancelled")
    }
}

extension ConditionElementListSyntax {
    /// Some condition compares the loop element (or a member of it) with
    /// another value using `operatorText`.
    /// Some condition compares the loop element (or a member of it) with the
    /// last published value: stored state, not a literal or a loop local.
    fileprivate func comparesElement(
        _ elementName: String,
        operator operatorText: String,
        localNames: Set<String>
    ) -> Bool {
        contains { element in
            guard let condition = element.condition.as(ExprSyntax.self) else {
                return false
            }
            return condition.binaryOperands(operator: operatorText).contains { comparison in
                let leftMentions = comparison.left.mentions(elementName)
                guard leftMentions != comparison.right.mentions(elementName) else {
                    return false
                }
                let other = leftMentions ? comparison.right : comparison.left
                return other.readsStoredState(excludingLocalNames: localNames)
            }
        }
    }
}

extension ExprSyntax {
    fileprivate func mentions(_ name: String) -> Bool {
        tokens(viewMode: .sourceAccurate).contains { $0.tokenKind == .identifier(name) }
    }
}

extension AttributeListSyntax {
    func containsAttribute(_ attribute: String) -> Bool {
        contains { $0.trimmedDescription == attribute }
    }
}
