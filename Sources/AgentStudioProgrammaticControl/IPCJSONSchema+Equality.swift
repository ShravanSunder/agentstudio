import Foundation

extension IPCJSONSchema {
    /// JSON object property order is not part of a schema's contract.
    package static func == (left: Self, right: Self) -> Bool {
        switch (left, right) {
        case (.object(let leftFields), .object(let rightFields)):
            leftFields.sorted { $0.name < $1.name } == rightFields.sorted { $0.name < $1.name }
        case (.dictionary(let leftValue), .dictionary(let rightValue)):
            leftValue == rightValue
        case (
            .array(let leftItem, let leftMinimum, let leftMaximum),
            .array(let rightItem, let rightMinimum, let rightMaximum)
        ):
            leftItem == rightItem && leftMinimum == rightMinimum && leftMaximum == rightMaximum
        case (.string(let leftValue), .string(let rightValue)):
            leftValue == rightValue
        case (.integer(let leftMinimum, let leftMaximum), .integer(let rightMinimum, let rightMaximum)):
            leftMinimum == rightMinimum && leftMaximum == rightMaximum
        case (.number(let leftMinimum, let leftMaximum), .number(let rightMinimum, let rightMaximum)):
            leftMinimum == rightMinimum && leftMaximum == rightMaximum
        case (.boolean, .boolean), (.null, .null), (.schemaDocument, .schemaDocument):
            true
        case (.booleanConstant(let leftValue), .booleanConstant(let rightValue)):
            leftValue == rightValue
        case (.literalValue(let leftValue), .literalValue(let rightValue)):
            leftValue == rightValue
        case (.oneOf(let leftValues), .oneOf(let rightValues)):
            leftValues == rightValues
        default:
            false
        }
    }
}
