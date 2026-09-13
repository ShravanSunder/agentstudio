import Foundation

package enum IPCMethodDescriptorError: Error, Equatable, Sendable {
    case invalidMethodName
    case missingDescription
    case missingPrivilegeClass
    case invalidCommandIdentifier
    case invalidDocumentedError
    case duplicateDocumentedErrorReason
    case mutationRequiresCorrelation
    case invalidCorrelationField
    case parametersMustBeAnObjectForModelCalls
    case duplicateModelCallVariant
    case invalidModelCallMetadata
    case unknownModelParameterField(String)
    case invalidModelSelectorValue(String)
    case modelSelectorsMustMatchOneAlternative
    case invalidOfflineEligibility
}

package struct IPCMethodDescriptor<
    Parameters: Codable & Sendable,
    Result: Codable & Sendable
>: Sendable {
    package let name: String
    package let description: String
    package let contract: IPCMethodContract<Parameters, Result>
    package let examples: [IPCMethodExample<Parameters, Result>]
    package let exposure: IPCMethodExposure
    package let requiredPrivileges: Set<IPCPrivilegeClass>
    package let dataScope: IPCDataScope
    package let allowedTargetKinds: Set<IPCHandleKind>
    package let commandRelationship: IPCCommandRelationship
    package let executionOwner: IPCExecutionOwner
    package let principalAvailability: IPCPrincipalAvailability
    package let resultSemantics: IPCResultSemantics
    package let documentedErrors: [IPCMethodErrorCase]
    package let isMutating: Bool
    package let correlationPolicy: IPCCorrelationPolicy
    package let offlineEligibility: IPCMethodOfflineEligibility
    package let modelCalls: [IPCModelCallProjection]

    package init(
        name: String,
        description: String,
        examples: [IPCMethodExample<Parameters, Result>],
        exposure: IPCMethodExposure,
        requiredPrivileges: Set<IPCPrivilegeClass>,
        dataScope: IPCDataScope,
        allowedTargetKinds: Set<IPCHandleKind>,
        commandRelationship: IPCCommandRelationship,
        executionOwner: IPCExecutionOwner,
        principalAvailability: IPCPrincipalAvailability,
        resultSemantics: IPCResultSemantics,
        documentedErrors: [IPCMethodErrorCase],
        isMutating: Bool,
        correlationPolicy: IPCCorrelationPolicy,
        offlineEligibility: IPCMethodOfflineEligibility = .never,
        modelCalls: [IPCModelCallProjection] = []
    ) throws where Parameters: IPCSchemaProviding, Result: IPCSchemaProviding {
        try self.init(
            name: name,
            description: description,
            parameterSchema: Parameters.ipcSchema(),
            resultSchema: Result.ipcSchema(),
            examples: examples,
            exposure: exposure,
            requiredPrivileges: requiredPrivileges,
            dataScope: dataScope,
            allowedTargetKinds: allowedTargetKinds,
            commandRelationship: commandRelationship,
            executionOwner: executionOwner,
            principalAvailability: principalAvailability,
            resultSemantics: resultSemantics,
            documentedErrors: documentedErrors,
            isMutating: isMutating,
            correlationPolicy: correlationPolicy,
            offlineEligibility: offlineEligibility,
            modelCalls: modelCalls
        )
    }

    package init(
        name: String,
        description: String,
        parameterSchema: IPCJSONSchema,
        resultSchema: IPCJSONSchema,
        examples: [IPCMethodExample<Parameters, Result>],
        exposure: IPCMethodExposure,
        requiredPrivileges: Set<IPCPrivilegeClass>,
        dataScope: IPCDataScope,
        allowedTargetKinds: Set<IPCHandleKind>,
        commandRelationship: IPCCommandRelationship,
        executionOwner: IPCExecutionOwner,
        principalAvailability: IPCPrincipalAvailability,
        resultSemantics: IPCResultSemantics,
        documentedErrors: [IPCMethodErrorCase],
        isMutating: Bool,
        correlationPolicy: IPCCorrelationPolicy,
        offlineEligibility: IPCMethodOfflineEligibility = .never,
        modelCalls: [IPCModelCallProjection] = []
    ) throws {
        try Self.validateMethodName(name)
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IPCMethodDescriptorError.missingDescription
        }
        guard !requiredPrivileges.isEmpty else {
            throw IPCMethodDescriptorError.missingPrivilegeClass
        }
        try Self.validateCommandRelationship(commandRelationship)
        try Self.validateDocumentedErrors(documentedErrors)

        let contract = try IPCMethodContract<Parameters, Result>(
            parameterSchema: parameterSchema,
            resultSchema: resultSchema
        )
        if isMutating {
            guard correlationPolicy == .required else {
                throw IPCMethodDescriptorError.mutationRequiresCorrelation
            }
            try Self.validateRequiredCorrelationField(in: parameterSchema)
        }
        try Self.validateModelCalls(modelCalls, parameterSchema: parameterSchema)
        try Self.validateOfflineEligibility(offlineEligibility, modelCalls: modelCalls)
        for example in examples {
            guard !example.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw IPCMethodDescriptorError.invalidModelCallMetadata
            }
            try contract.validateExample(parameters: example.parameters, result: example.result)
        }

        self.name = name
        self.description = description
        self.contract = contract
        self.examples = examples
        self.exposure = exposure
        self.requiredPrivileges = requiredPrivileges
        self.dataScope = dataScope
        self.allowedTargetKinds = allowedTargetKinds
        self.commandRelationship = commandRelationship
        self.executionOwner = executionOwner
        self.principalAvailability = principalAvailability
        self.resultSemantics = resultSemantics
        self.documentedErrors = documentedErrors
        self.isMutating = isMutating
        self.correlationPolicy = correlationPolicy
        self.offlineEligibility = offlineEligibility
        self.modelCalls = modelCalls
    }

    package func decodeParameters(from data: Data) throws -> Parameters {
        try contract.decodeParameters(from: data)
    }

    package func encodeResult(_ result: Result) throws -> Data {
        try contract.encodeResult(result)
    }

    package var metadata: IPCMethodDescriptorMetadata<Parameters, Result> {
        .init(
            name: name,
            description: description,
            parameterSchema: contract.parameterSchema,
            resultSchema: contract.resultSchema,
            examples: examples,
            exposure: exposure,
            requiredPrivileges: requiredPrivileges.sorted { $0.rawValue < $1.rawValue },
            dataScope: dataScope,
            allowedTargetKinds: allowedTargetKinds.sorted { $0.rawValue < $1.rawValue },
            commandRelationship: commandRelationship,
            executionOwner: executionOwner,
            principalAvailability: principalAvailability,
            resultSemantics: resultSemantics,
            documentedErrors: documentedErrors,
            isMutating: isMutating,
            correlationPolicy: correlationPolicy,
            offlineEligibility: offlineEligibility,
            modelCalls: modelCalls
        )
    }

    private static func validateMethodName(_ name: String) throws {
        let reservedBackendPrefix = ["z", "m", "x"].joined() + "."
        guard name.contains("."), !name.hasPrefix("."), !name.hasSuffix("."),
            !name.hasPrefix(reservedBackendPrefix)
        else {
            throw IPCMethodDescriptorError.invalidMethodName
        }
    }

    private static func validateCommandRelationship(
        _ relationship: IPCCommandRelationship
    ) throws {
        guard case .appCommand(let identifier) = relationship else { return }
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IPCMethodDescriptorError.invalidCommandIdentifier
        }
    }

    private static func validateDocumentedErrors(
        _ documentedErrors: [IPCMethodErrorCase]
    ) throws {
        for errorCase in documentedErrors {
            guard !errorCase.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !errorCase.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw IPCMethodDescriptorError.invalidDocumentedError
            }
        }
        guard Set(documentedErrors.map(\.reason)).count == documentedErrors.count else {
            throw IPCMethodDescriptorError.duplicateDocumentedErrorReason
        }
    }

    private static func validateRequiredCorrelationField(
        in parameterSchema: IPCJSONSchema
    ) throws {
        let alternatives = try rootObjectAlternatives(
            in: parameterSchema,
            invalidShapeError: .invalidCorrelationField
        )
        for fields in alternatives {
            guard
                let correlationField = fields.first(where: { $0.name == "correlationId" }),
                case .required = correlationField.presence,
                correlationField.schema == IPCSchemaScalars.uuid
            else {
                throw IPCMethodDescriptorError.invalidCorrelationField
            }
        }
    }

    private static func validateModelCalls(
        _ modelCalls: [IPCModelCallProjection],
        parameterSchema: IPCJSONSchema
    ) throws {
        guard Set(modelCalls.map(\.variant)).count == modelCalls.count else {
            throw IPCMethodDescriptorError.duplicateModelCallVariant
        }
        guard !modelCalls.isEmpty else { return }
        let alternatives = try rootObjectAlternatives(
            in: parameterSchema,
            invalidShapeError: .parametersMustBeAnObjectForModelCalls
        )

        for modelCall in modelCalls {
            guard !modelCall.successReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                Set(modelCall.selectors.map(\.parameterField)).count == modelCall.selectors.count,
                Set(modelCall.scalarArguments.map(\.name)).count == modelCall.scalarArguments.count,
                Set(modelCall.scalarArguments.map(\.parameterField)).count == modelCall.scalarArguments.count
            else {
                throw IPCMethodDescriptorError.invalidModelCallMetadata
            }
            for selector in modelCall.selectors {
                let candidateFields = alternatives.compactMap { fields in
                    fields.first(where: { $0.name == selector.parameterField })
                }
                guard !candidateFields.isEmpty else {
                    throw IPCMethodDescriptorError.unknownModelParameterField(selector.parameterField)
                }
                guard
                    candidateFields.contains(where: { field in
                        (try? field.schema.normalize(JSONEncoder().encode(selector.equals))) != nil
                    })
                else {
                    throw IPCMethodDescriptorError.invalidModelSelectorValue(selector.parameterField)
                }
            }
            let matchingAlternatives = alternatives.filter { fields in
                let fieldsByName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
                return modelCall.selectors.allSatisfy { selector in
                    guard let field = fieldsByName[selector.parameterField] else { return false }
                    return (try? field.schema.normalize(JSONEncoder().encode(selector.equals))) != nil
                }
            }
            guard matchingAlternatives.count == 1, let selectedFields = matchingAlternatives.first else {
                throw IPCMethodDescriptorError.modelSelectorsMustMatchOneAlternative
            }
            let selectedFieldsByName = Dictionary(
                uniqueKeysWithValues: selectedFields.map { ($0.name, $0) }
            )
            for argument in modelCall.scalarArguments {
                guard !argument.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    !argument.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw IPCMethodDescriptorError.invalidModelCallMetadata
                }
                guard selectedFieldsByName[argument.parameterField] != nil else {
                    throw IPCMethodDescriptorError.unknownModelParameterField(argument.parameterField)
                }
            }
        }
    }

    private static func rootObjectAlternatives(
        in schema: IPCJSONSchema,
        invalidShapeError: IPCMethodDescriptorError
    ) throws -> [[IPCObjectField]] {
        switch schema {
        case .object(let fields):
            return [fields]
        case .oneOf(let schemas):
            return try schemas.map { alternative in
                guard case .object(let fields) = alternative else { throw invalidShapeError }
                return fields
            }
        case .dictionary, .array, .string, .integer, .number, .boolean, .booleanConstant, .literalValue, .null,
            .schemaDocument:
            throw invalidShapeError
        }
    }

    private static func validateOfflineEligibility(
        _ eligibility: IPCMethodOfflineEligibility,
        modelCalls: [IPCModelCallProjection]
    ) throws {
        guard case .modelCallVariants(let eligibleVariants) = eligibility else { return }
        let projectedVariants = Set(modelCalls.map(\.variant))
        guard !eligibleVariants.isEmpty,
            !eligibleVariants.contains(.needsYouClear),
            eligibleVariants.isSubset(of: projectedVariants)
        else {
            throw IPCMethodDescriptorError.invalidOfflineEligibility
        }
    }
}
