import SwiftSyntax

/// SwiftParser does not fold operators: `a == b && c` parses as one flat
/// `SequenceExprSyntax` of operands and operators, not a tree of infix
/// expressions. Rules read comparisons and assignments from that sequence.
extension ExprSyntax {
    /// Every `left <operator> right` in this flat sequence, taking each
    /// operator's immediate neighbours as its operands.
    func binaryOperands(operator operatorText: String) -> [(left: ExprSyntax, right: ExprSyntax)] {
        guard let sequence = self.as(SequenceExprSyntax.self) else {
            return []
        }
        let elements = Array(sequence.elements)
        return elements.indices.compactMap { index in
            guard index > 0, index + 1 < elements.count,
                elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == operatorText
            else {
                return nil
            }
            return (elements[index - 1], elements[index + 1])
        }
    }

    /// `target = value` when this expression is exactly one assignment.
    var assignment: (target: ExprSyntax, value: ExprSyntax)? {
        guard let sequence = self.as(SequenceExprSyntax.self) else {
            return nil
        }
        let elements = Array(sequence.elements)
        guard elements.count == 3, elements[1].is(AssignmentExprSyntax.self) else {
            return nil
        }
        return (elements[0], elements[2])
    }
}
