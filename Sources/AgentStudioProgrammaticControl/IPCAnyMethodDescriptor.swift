import Foundation

package struct IPCAnyMethodDescriptor: Sendable {
    package let metadata: IPCMethodCatalogEntry
    package let catalogEntrySchema: IPCJSONSchema
    private let parameterNormalizer: @Sendable (Data) throws -> Data

    package init<Parameters, Result>(
        erasing descriptor: IPCMethodDescriptor<Parameters, Result>
    ) throws where Parameters: Codable & Sendable, Result: Codable & Sendable {
        let parameterSchema = descriptor.contract.parameterSchema
        let resultSchema = descriptor.contract.resultSchema
        let examples = try descriptor.examples.map { example in
            try descriptor.contract.validateExample(
                parameters: example.parameters,
                result: example.result
            )
            let parameterData = try JSONEncoder().encode(example.parameters)
            let resultData = try JSONEncoder().encode(example.result)
            return try IPCMethodExampleDocument(
                description: example.description,
                parameters: parameterData,
                result: resultData
            )
        }
        metadata = IPCMethodCatalogEntry(
            name: descriptor.name,
            description: descriptor.description,
            parameterSchema: parameterSchema,
            resultSchema: resultSchema,
            examples: examples,
            exposure: descriptor.exposure,
            requiredPrivileges: descriptor.requiredPrivileges.sorted { $0.rawValue < $1.rawValue },
            dataScope: descriptor.dataScope,
            allowedTargetKinds: descriptor.allowedTargetKinds.sorted { $0.rawValue < $1.rawValue },
            commandRelationship: descriptor.commandRelationship,
            executionOwner: descriptor.executionOwner,
            principalAvailability: descriptor.principalAvailability,
            resultSemantics: descriptor.resultSemantics,
            documentedErrors: descriptor.documentedErrors,
            isMutating: descriptor.isMutating,
            correlationPolicy: descriptor.correlationPolicy,
            offlineEligibility: descriptor.offlineEligibility,
            modelCalls: descriptor.modelCalls
        )
        catalogEntrySchema = try IPCMethodCatalogEntry.schemaForExamples(
            methodName: descriptor.name,
            examples: descriptor.examples
        )
        parameterNormalizer = { data in
            let parameters = try descriptor.decodeParameters(from: data)
            return try parameterSchema.normalize(JSONEncoder().encode(parameters))
        }
        _ = try catalogEntrySchema.decode(
            IPCMethodCatalogEntry.self,
            from: JSONEncoder().encode(metadata)
        )
    }

    package func normalizeParameters(_ data: Data) throws -> Data {
        try parameterNormalizer(data)
    }
}
