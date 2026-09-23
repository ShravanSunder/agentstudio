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
