import Foundation

package enum IPCMethodCatalogDecoder {
    package static func decode(_ data: Data) throws -> IPCMethodCatalogResult {
        let provisional = try decodeProvisional(data)
        try validateCatalogIdentity(provisional)
        let entrySchemas = try provisional.methods.map { entry in
            try IPCMethodCatalogEntry.schemaForReceivedEntry(entry)
        }
        let catalogSchema = try IPCMethodCatalogResult.schema(
            compatibility: .current,
            methodSchemas: entrySchemas
        )
        let normalized = try catalogSchema.normalize(data)
        let decoded = try decodeProvisional(normalized)
        guard decoded == provisional else {
            throw failure(
                .decodingMismatch,
                path: "$",
                expected: "the validated typed method catalog"
            )
        }
        return decoded
    }

    private static func decodeProvisional(_ data: Data) throws -> IPCMethodCatalogResult {
        do {
            return try JSONDecoder().decode(IPCMethodCatalogResult.self, from: data)
        } catch let error as IPCSchemaValidationError {
            throw error
        } catch {
            throw failure(
                .decodingMismatch,
                path: "$",
                expected: "a complete typed method catalog"
            )
        }
    }

    private static func validateCatalogIdentity(
        _ catalog: IPCMethodCatalogResult
    ) throws {
        guard catalog.compatibility == .current else {
            throw failure(
                .invalidValue,
                path: "$.compatibility",
                expected: "the current protocol and catalog compatibility identity"
            )
        }
        let methodNames = catalog.methods.map(\.name)
        guard Set(methodNames).count == methodNames.count else {
            throw failure(
                .invalidValue,
                path: "$.methods",
                expected: "unique method names"
            )
        }
        guard methodNames == methodNames.sorted() else {
            throw failure(
                .invalidValue,
                path: "$.methods",
                expected: "method names in ascending order"
            )
        }
        guard methodNames.filter({ $0 == "system.capabilities" }).count == 1 else {
            throw failure(
                .invalidValue,
                path: "$.methods",
                expected: "exactly one system capabilities method"
            )
        }
    }

    private static func failure(
        _ reason: IPCSchemaValidationError.Reason,
        path: String,
        expected: String
    ) -> IPCSchemaValidationError {
        IPCSchemaValidationError(
            fieldPath: path,
            reason: reason,
            expected: expected
        )
    }
}
