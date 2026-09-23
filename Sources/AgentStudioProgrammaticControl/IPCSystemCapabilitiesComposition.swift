import Foundation

package enum IPCSystemCapabilitiesCompositionError: Error, Equatable, Sendable {
    case incompatibleIdentity
    case duplicateMethodName(String)
    case capabilitiesAlreadyPresent
    case invalidIllustrativeDescriptor
    case illustrativeDescriptorMissing
}

package struct IPCSystemCapabilitiesComposition: Sendable {
    package let descriptor: IPCMethodDescriptor<IPCEmptyParams, IPCMethodCatalogResult>
    package let erasedDescriptor: IPCAnyMethodDescriptor
    package let result: IPCMethodCatalogResult
}

package enum IPCSystemCapabilitiesDescriptorFactory {
    package static func compose(
        compatibility: IPCProtocolCatalogCompatibility,
        availableDescriptors: [IPCAnyMethodDescriptor],
        illustrativeDescriptor: IPCAnyMethodDescriptor
    ) throws -> IPCSystemCapabilitiesComposition {
        guard compatibility == .current else {
            throw IPCSystemCapabilitiesCompositionError.incompatibleIdentity
        }
        try validateAvailableDescriptors(
            availableDescriptors,
            illustrativeDescriptor: illustrativeDescriptor
        )
        let sortedAvailableDescriptors = availableDescriptors.sorted {
            $0.metadata.name < $1.metadata.name
        }

        let illustrativeExample = IPCMethodExample(
            description: "Catalog containing the runtime identity method",
            parameters: IPCEmptyParams(),
            result: IPCMethodCatalogResult(
                compatibility: compatibility,
                methods: [illustrativeDescriptor.metadata]
            )
        )
        let selfEntrySchema = try IPCMethodCatalogEntry.schemaForExamples(
            methodName: "system.capabilities",
            examples: [illustrativeExample]
        )
        let resultSchema = try IPCMethodCatalogResult.schema(
            compatibility: compatibility,
            methodSchemas: sortedAvailableDescriptors.map(\.catalogEntrySchema) + [selfEntrySchema]
        )
        let descriptor = try IPCMethodDescriptor(
            name: "system.capabilities",
            description: "Return compatibility identity and the complete available typed method catalog.",
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
            documentedErrors: [
                .init(
                    reason: "unsupportedVersion",
                    description: "The client and runtime compatibility identities do not match."
                )
            ],
            isMutating: false,
            correlationPolicy: .notAccepted
        )
        let erasedDescriptor = try IPCAnyMethodDescriptor(erasing: descriptor)
        let result = IPCMethodCatalogResult(
            compatibility: compatibility,
            methods: (sortedAvailableDescriptors.map(\.metadata) + [erasedDescriptor.metadata])
                .sorted { $0.name < $1.name }
        )

        _ = try descriptor.encodeResult(result)
        _ = try erasedDescriptor.catalogEntrySchema.decode(
            IPCMethodCatalogEntry.self,
            from: JSONEncoder().encode(erasedDescriptor.metadata)
        )
        return IPCSystemCapabilitiesComposition(
            descriptor: descriptor,
            erasedDescriptor: erasedDescriptor,
            result: result
        )
    }

    private static func validateAvailableDescriptors(
        _ availableDescriptors: [IPCAnyMethodDescriptor],
        illustrativeDescriptor: IPCAnyMethodDescriptor
    ) throws {
        var observedNames: Set<String> = []
        for descriptor in availableDescriptors {
            guard descriptor.metadata.name != "system.capabilities" else {
                throw IPCSystemCapabilitiesCompositionError.capabilitiesAlreadyPresent
            }
            guard observedNames.insert(descriptor.metadata.name).inserted else {
                throw IPCSystemCapabilitiesCompositionError.duplicateMethodName(
                    descriptor.metadata.name
                )
            }
        }
        guard illustrativeDescriptor.metadata.name == "system.ping" else {
            throw IPCSystemCapabilitiesCompositionError.invalidIllustrativeDescriptor
        }
        guard
            availableDescriptors.filter({ $0.metadata == illustrativeDescriptor.metadata }).count == 1
        else {
            throw IPCSystemCapabilitiesCompositionError.illustrativeDescriptorMissing
        }
    }
}
