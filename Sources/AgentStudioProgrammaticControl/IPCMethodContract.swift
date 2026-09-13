import Foundation

/// The method registry attaches its handler to this typed request/result pair.
/// Validation and discovery consume the same schemas; Codable cannot silently
/// discard a schema-declared non-null field before the handler sees it.
package struct IPCMethodContract<Parameters: Codable & Sendable, Result: Codable & Sendable>: Sendable {
    package let parameterSchema: IPCJSONSchema
    package let resultSchema: IPCJSONSchema

    package init(parameterSchema: IPCJSONSchema, resultSchema: IPCJSONSchema) throws {
        _ = try parameterSchema.jsonSchemaData()
        _ = try resultSchema.jsonSchemaData()
        self.parameterSchema = parameterSchema
        self.resultSchema = resultSchema
    }

    package func decodeParameters(from data: Data) throws -> Parameters {
        let normalized = try parameterSchema.normalize(data)
        let parameters = try parameterSchema.decode(Parameters.self, from: normalized)
        try parameterSchema.validateTypedEncoding(
            normalized: normalized, encoded: encodedValue(parameters)
        )
        return parameters
    }

    package func encodeResult(_ result: Result) throws -> Data {
        let encoded = try encodedValue(result)
        let normalized = try resultSchema.normalize(encoded)
        try resultSchema.validateTypedEncoding(normalized: normalized, encoded: encoded)
        return normalized
    }

    package func validateExample(parameters: Parameters, result: Result) throws {
        _ = try decodeParameters(from: encodedValue(parameters))
        _ = try encodeResult(result)
    }

    private func encodedValue<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw IPCSchemaValidationError(
                fieldPath: "$", reason: .decodingMismatch, expected: "an encodable typed contract value"
            )
        }
    }
}
