import SwiftSyntax

/// The statement shapes that let a comparison decide whether an action runs.
/// A comparison whose result is stored, printed or discarded controls
/// nothing; these forms do:
///
/// - `guard <cmp> else { return | continue | break }` before the action;
/// - `if <cmp> { return | continue | break }` before the action;
/// - the action nested inside `if <cmp> { … }`.
extension CodeBlockSyntax {
    /// The block leaves its scope with a top-level `return`, `continue` or
    /// `break`.
    var exitsScope: Bool {
        statements.contains { statement in
            statement.item.is(ReturnStmtSyntax.self)
                || statement.item.is(ContinueStmtSyntax.self)
                || statement.item.is(BreakStmtSyntax.self)
        }
    }
}

extension CodeBlockItemSyntax {
    /// The `if` this statement is, however the parser wrapped it.
    var ifExpression: IfExprSyntax? {
        item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) ?? item.as(IfExprSyntax.self)
    }
}

extension ExprSyntax {
    /// The expression reads stored state the guard compares against: a member
    /// of `self` (`self.generation`, `self?.lastValue`, a subscript or member
    /// of one) or a bare property name. Literals, enum cases and the names in
    /// `localNames` (captured values, loop elements, locals) are not stored
    /// state, so `captured == 0` or `element != 0` guards nothing.
    func readsStoredState(excludingLocalNames localNames: Set<String>) -> Bool {
        var expression = self
        var isMemberBase = false
        while true {
            if let optional = expression.as(OptionalChainingExprSyntax.self) {
                expression = optional.expression
            } else if let forced = expression.as(ForceUnwrapExprSyntax.self) {
                expression = forced.expression
            } else if let subscriptCall = expression.as(SubscriptCallExprSyntax.self) {
                expression = subscriptCall.calledExpression
                isMemberBase = true
            } else if let member = expression.as(MemberAccessExprSyntax.self) {
                guard let base = member.base else {
                    return false
                }
                expression = base
                isMemberBase = true
            } else if let reference = expression.as(DeclReferenceExprSyntax.self) {
                if reference.baseName.tokenKind == .keyword(.self) {
                    return isMemberBase
                }
                let name = reference.baseName.text
                return !localNames.contains(name) && name.first?.isLowercase == true
            } else {
                return false
            }
        }
    }
}

/// Names bound by `let`, `var`, `guard let` or `if let` inside a syntax
/// subtree: values local to a closure or loop body, not stored state.
final class LocalBindingNameCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []

    static func names(in syntax: Syntax) -> Set<String> {
        let collector = LocalBindingNameCollector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        return collector.names
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            names.insert(name)
        }
    }

    override func visitPost(_ node: OptionalBindingConditionSyntax) {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            names.insert(name)
        }
    }
}
