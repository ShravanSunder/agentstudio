import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC finite catalog self-description")
struct IPCCatalogSelfDescriptionTests {
    @Test("capabilities catalog validates an actual catalog containing its own entry")
    func capabilitiesCatalogContainsItselfWithoutSchemaRecursion() throws {
        let pingDescriptor = try IPCAnyMethodDescriptor(erasing: makePingDescriptor())
        let illustrativeExample = IPCMethodExample(
            description: "Catalog with one ping method",
            parameters: IPCEmptyParams(),
            result: IPCDynamicCapabilitiesResult(methods: [pingDescriptor.metadata])
        )
        let capabilitiesEntrySchema = try IPCMethodCatalogEntry.schemaForExamples(
            methodName: "system.capabilities",
            examples: [illustrativeExample]
        )
        let completeResultSchema = IPCDynamicCapabilitiesResult.schema(
            methodSchemas: [pingDescriptor.catalogEntrySchema, capabilitiesEntrySchema]
        )
        let capabilitiesDescriptor = try IPCAnyMethodDescriptor(
            erasing: makeCapabilitiesDescriptor(
                resultSchema: completeResultSchema,
                illustrativeExample: illustrativeExample
            )
        )
        let actualCatalog = IPCDynamicCapabilitiesResult(
            methods: [pingDescriptor.metadata, capabilitiesDescriptor.metadata]
        )
        let encodedCatalog = try JSONEncoder().encode(actualCatalog)

        _ = try capabilitiesDescriptor.metadata.resultSchema.decode(
            IPCDynamicCapabilitiesResult.self,
            from: encodedCatalog
        )
        #expect(try capabilitiesDescriptor.catalogEntrySchema.jsonSchemaData().count < 131_072)
    }

    @Test("capabilities example schema admits only the validated illustrative object")
    func capabilitiesExamplesAreExactFiniteLiterals() throws {
        let pingDescriptor = try IPCAnyMethodDescriptor(erasing: makePingDescriptor())
        let example = IPCMethodExample(
            description: "Catalog with one ping method",
            parameters: IPCEmptyParams(),
            result: IPCDynamicCapabilitiesResult(methods: [pingDescriptor.metadata])
        )
        let schema = try IPCMethodCatalogEntry.schemaForExamples(
            methodName: "system.capabilities",
            examples: [example]
        )
        guard case .object(let fields) = schema,
            case .array(let exampleSchema, _, _) = fields.first(where: { $0.name == "examples" })?.schema
        else {
            Issue.record("Expected finite literal examples")
            return
        }
        let projection = try #require(
            JSONSerialization.jsonObject(with: exampleSchema.jsonSchemaData()) as? [String: Any]
        )
        #expect(projection["const"] is [String: Any])

        var encodedExample = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(example)) as? [String: Any]
        )
        encodedExample["untyped"] = true
        #expect(throws: IPCSchemaValidationError.self) {
            try exampleSchema.normalize(
                JSONSerialization.data(withJSONObject: encodedExample)
            )
        }
    }

    private func makePingDescriptor() throws -> IPCMethodDescriptor<IPCEmptyParams, IPCSystemPingResult> {
        let runtimeId = UUIDv7.generate()
        return try IPCMethodDescriptor(
            name: "system.ping",
            description: "Confirm the selected runtime is reachable.",
            examples: [
                .init(
                    description: "Reachable runtime",
                    parameters: IPCEmptyParams(),
                    result: IPCSystemPingResult(runtimeId: runtimeId)
                )
            ],
            exposure: .allChannels,
            requiredPrivileges: [.systemRead],
            dataScope: .unspecified,
            allowedTargetKinds: [],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .queryReader,
            principalAvailability: .preAuthentication,
            resultSemantics: .applied,
            documentedErrors: [],
            isMutating: false,
            correlationPolicy: .notAccepted
        )
    }

    private func makeCapabilitiesDescriptor(
        resultSchema: IPCJSONSchema,
        illustrativeExample: IPCMethodExample<IPCEmptyParams, IPCDynamicCapabilitiesResult>
    ) throws -> IPCMethodDescriptor<IPCEmptyParams, IPCDynamicCapabilitiesResult> {
        try IPCMethodDescriptor(
            name: "system.capabilities",
            description: "Return the complete available typed method catalog.",
            parameterSchema: try IPCEmptyParams.ipcSchema(),
            resultSchema: resultSchema,
            examples: [illustrativeExample],
            exposure: .allChannels,
            requiredPrivileges: [.systemRead],
            dataScope: .unspecified,
            allowedTargetKinds: [],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .queryReader,
            principalAvailability: .authenticated,
            resultSemantics: .applied,
            documentedErrors: [],
            isMutating: false,
            correlationPolicy: .notAccepted
        )
    }
}

private struct IPCDynamicCapabilitiesResult: Codable, Equatable, Sendable {
    let methods: [IPCMethodCatalogEntry]

    static func schema(methodSchemas: [IPCJSONSchema]) -> IPCJSONSchema {
        let methodSchema =
            methodSchemas.count == 1
            ? methodSchemas[0]
            : .oneOf(methodSchemas)
        return .object(fields: [
            .init(
                name: "methods",
                description: "Complete available method catalog",
                schema: .array(items: methodSchema, minimumCount: 1)
            )
        ])
    }
}
