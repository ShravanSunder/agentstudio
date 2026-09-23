import Foundation

/// A wire value declares its schema beside its Codable contract. Method
/// descriptors reuse these declarations instead of maintaining field lists in
/// the server and CLI independently.
package protocol IPCSchemaProviding: Codable, Sendable {
    static func ipcSchema() throws -> IPCJSONSchema
}

extension IPCSchemaProviding where Self: RawRepresentable & CaseIterable, RawValue == String {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .string(allowedValues: allCases.map(\.rawValue))
    }
}

package enum IPCSchemaScalars {
    package static let uuid = IPCJSONSchema.string(
        pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    )

    /// The transport's JSON numbers must remain exact when represented as Double.
    package static let maximumExactInteger: Int64 = 9_007_199_254_740_991
    package static let signedInteger = IPCJSONSchema.integer(
        minimum: -maximumExactInteger, maximum: maximumExactInteger
    )
    package static let unsignedInteger = IPCJSONSchema.integer(minimum: 0, maximum: maximumExactInteger)
    package static let unixTimestamp = IPCJSONSchema.number()
}

extension IPCObjectField {
    package static func optional(
        _ name: String, description: String, schema: IPCJSONSchema
    ) -> Self {
        .init(name: name, description: description, schema: .oneOf([schema, .null]), presence: .optional)
    }
}
