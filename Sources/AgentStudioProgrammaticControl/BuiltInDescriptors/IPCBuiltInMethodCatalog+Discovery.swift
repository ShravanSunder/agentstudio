import Foundation

extension IPCBuiltInMethodExampleContext {
    package init(illustrativeIdentifier: UUID) {
        self.init(
            runtimeId: illustrativeIdentifier, windowId: illustrativeIdentifier, workspaceId: illustrativeIdentifier,
            repositoryId: illustrativeIdentifier, worktreeId: illustrativeIdentifier, tabId: illustrativeIdentifier,
            paneId: illustrativeIdentifier, commandId: illustrativeIdentifier, correlationId: illustrativeIdentifier,
            subscriptionId: illustrativeIdentifier
        )
    }
}

extension IPCBuiltInMethodCatalog {
    package static func bootstrapDescriptors(examples: IPCBuiltInMethodExampleContext) throws
        -> [IPCAnyMethodDescriptor]
    {
        try IPCSystemAndAuthMethodDescriptors(examples: examples).erased
    }

    /// Offline classification cannot read the live catalog, so an unreachable
    /// app is answered from the compiled notification descriptors. Only these
    /// methods carry offline eligibility, so no other descriptor is needed.
    package static func offlineNotificationDescriptors(
        examples: IPCBuiltInMethodExampleContext
    ) throws -> [IPCAnyMethodDescriptor] {
        try IPCSessionMethodDescriptors(examples: examples).erased
    }

    package static func matchingDiscoveredMethods(
        _ catalog: IPCMethodCatalogResult,
        examples: IPCBuiltInMethodExampleContext
    ) throws -> [IPCAnyMethodDescriptor] {
        guard catalog.compatibility == .current,
            Set(catalog.methods.map(\.name)).count == catalog.methods.count
        else { throw incompatibleCatalog() }
        let methods = Dictionary(uniqueKeysWithValues: catalog.methods.map { ($0.name, $0) })
        let maximumWait: Double
        if let wait = methods["terminal.wait"] {
            guard case .object(let fields) = wait.parameterSchema,
                case .number(_, let maximum) = fields.first(where: { $0.name == "timeoutSeconds" })?.schema,
                let maximum
            else { throw incompatibleCatalog() }
            maximumWait = maximum
        } else {
            // This descriptor is filtered out below; no absent method supplies invocation policy.
            maximumWait = 0
        }
        let inputs = IPCBuiltInMethodCatalogInputs(
            terminalWaitMaximumSeconds: maximumWait,
            relationships: .init(
                paneFocus: methods["pane.focus"]?.commandRelationship ?? .noInteractiveIdentity,
                paneClose: methods["pane.close"]?.commandRelationship ?? .noInteractiveIdentity,
                drawerToggle: methods["drawer.toggle"]?.commandRelationship ?? .noInteractiveIdentity,
                drawerAddPane: methods["drawer.addPane"]?.commandRelationship ?? .noInteractiveIdentity,
                bridgeDiffLoad: methods["bridge.diff.load"]?.commandRelationship ?? .noInteractiveIdentity,
                bridgeFileViewOpen: methods["bridge.fileView.open"]?.commandRelationship ?? .noInteractiveIdentity
            ), examples: examples
        )
        return try IPCBuiltInMethodCatalog(inputs: inputs).erasedDescriptors.compactMap { descriptor in
            guard let advertised = methods[descriptor.metadata.name] else { return nil }
            let compiled = descriptor.metadata
            guard compiled.parameterSchema == advertised.parameterSchema,
                compiled.resultSchema == advertised.resultSchema,
                compiled.responseDelivery == advertised.responseDelivery,
                compiled.correlationPolicy == advertised.correlationPolicy,
                compiled.commandRelationship == advertised.commandRelationship,
                compiled.offlineEligibility == advertised.offlineEligibility,
                compiled.modelCalls == advertised.modelCalls,
                compiled.requiredPrivileges == advertised.requiredPrivileges,
                compiled.allowedTargetKinds == advertised.allowedTargetKinds,
                compiled.dataScope == advertised.dataScope,
                compiled.exposure == advertised.exposure
            else { throw incompatibleCatalog() }
            return descriptor
        }
    }

    private static func incompatibleCatalog() -> IPCSchemaValidationError {
        IPCSchemaValidationError(
            fieldPath: "$.methods", reason: .invalidDefinition, expected: "compatible compiled method contracts")
    }
}
