import Foundation

/// Immutable, canonical JSON for a documented constant. Construction remains
/// inside the schema implementation; callers supply concrete Encodable values.
package struct IPCJSONLiteral: Equatable, Sendable {
    let encodedValue: Data

    init(value: IPCSchemaValue) throws {
        encodedValue = try value.encoded()
    }

    func value() throws -> IPCSchemaValue {
        try JSONDecoder().decode(IPCSchemaValue.self, from: encodedValue)
    }
}

extension IPCJSONSchema {
    package static func literal<Value: Encodable>(_ value: Value) throws -> Self {
        do {
            let data = try JSONEncoder().encode(value)
            let schemaValue = try JSONDecoder().decode(IPCSchemaValue.self, from: data)
            return .literalValue(try IPCJSONLiteral(value: schemaValue))
        } catch {
            throw IPCSchemaValidationError(
                fieldPath: "$", reason: .invalidDefinition, expected: "an encodable typed constant"
            )
        }
    }
}
