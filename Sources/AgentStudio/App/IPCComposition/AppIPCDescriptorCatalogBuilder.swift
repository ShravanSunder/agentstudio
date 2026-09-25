import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

/// Immutable command-spec values captured on MainActor. Empty examples mark the
/// boundary: request examples, schemas, and descriptor validation are built by
/// the nonisolated catalog builder.
package struct AppIPCCommandCatalogProjectionInputs: Sendable {
    package let channel: AgentStudioIPCChannel
    package let commandDescriptorInputs: [IPCCommandDescriptorInput]
    package let recognizedCommands: [AppIPCRecognizedEntry]
    package let recognizedUnexposedCommands: [IPCRecognizedUnexposedName]

    package init(
        channel: AgentStudioIPCChannel,
        commandDescriptorInputs: [IPCCommandDescriptorInput],
        recognizedCommands: [AppIPCRecognizedEntry],
        recognizedUnexposedCommands: [IPCRecognizedUnexposedName]
    ) {
        self.channel = channel
        self.commandDescriptorInputs = commandDescriptorInputs
        self.recognizedCommands = recognizedCommands
        self.recognizedUnexposedCommands = recognizedUnexposedCommands
    }
}

package struct AppIPCDescriptorCatalogBuildInputs: Sendable {
    package let builtInCatalogInputs: IPCBuiltInMethodCatalogInputs
    package let commandCatalogProjectionInputs: AppIPCCommandCatalogProjectionInputs

    package init(
        builtInCatalogInputs: IPCBuiltInMethodCatalogInputs,
        commandCatalogProjectionInputs: AppIPCCommandCatalogProjectionInputs
    ) {
        self.builtInCatalogInputs = builtInCatalogInputs
        self.commandCatalogProjectionInputs = commandCatalogProjectionInputs
    }
}

package struct AppIPCDescriptorCatalogBuildResult: Sendable {
    package let builtInCatalog: IPCBuiltInMethodCatalog
    package let commandComposition: IPCCommandMethodComposition
    package let systemCapabilities: IPCSystemCapabilitiesComposition

    package init(
        builtInCatalog: IPCBuiltInMethodCatalog,
        commandComposition: IPCCommandMethodComposition,
        systemCapabilities: IPCSystemCapabilitiesComposition
    ) {
        self.builtInCatalog = builtInCatalog
        self.commandComposition = commandComposition
        self.systemCapabilities = systemCapabilities
    }
}

package enum AppIPCDescriptorCatalogBuilder {
    package enum BuildError: Error, Equatable, Sendable {
        case systemPingMissing
    }

    /// Projects captured command metadata into validated descriptors and their
    /// composed command methods. The complete operation runs off MainActor.
    @concurrent
    nonisolated
        package static func buildCommandCompositionOffMain(
            inputs: AppIPCCommandCatalogProjectionInputs
        ) async throws -> IPCCommandMethodComposition
    {
        try makeCommandComposition(inputs: inputs)
    }

    /// Builds immutable descriptor and schema values away from MainActor.
    /// Every input is captured before the hop; this function reads no app state.
    @concurrent
    nonisolated package static func buildOffMain(
        inputs: AppIPCDescriptorCatalogBuildInputs
    ) async throws -> AppIPCDescriptorCatalogBuildResult {
        let builtInCatalog = try IPCBuiltInMethodCatalog(inputs: inputs.builtInCatalogInputs)
        let commandComposition = try makeCommandComposition(inputs: inputs.commandCatalogProjectionInputs)
        let allDescriptors =
            builtInCatalog.erasedDescriptors + [
                commandComposition.listRepresentations.erasedDescriptor,
                commandComposition.executeRepresentations.erasedDescriptor,
            ]
        let availableDescriptors = allDescriptors.filter {
            $0.metadata.exposure == .allChannels || inputs.commandCatalogProjectionInputs.channel == .debug
        }
        let availableNames = Set(availableDescriptors.map(\.metadata.name))
        let recognizedUnexposedMethods =
            allDescriptors
            .filter { !availableNames.contains($0.metadata.name) }
            .map {
                IPCRecognizedUnexposedName(
                    name: $0.metadata.name,
                    agentEligibility: $0.metadata.agentEligibility ?? .notYetAllowed
                )
            }
        guard let illustrativePing = availableDescriptors.first(where: { $0.metadata.name == "system.ping" }) else {
            throw BuildError.systemPingMissing
        }
        let systemCapabilities = try IPCSystemCapabilitiesDescriptorFactory.compose(
            compatibility: .current,
            availableDescriptors: availableDescriptors,
            illustrativeDescriptor: illustrativePing,
            recognizedUnexposedMethods: recognizedUnexposedMethods
        )

        return AppIPCDescriptorCatalogBuildResult(
            builtInCatalog: builtInCatalog,
            commandComposition: commandComposition,
            systemCapabilities: systemCapabilities
        )
    }

    nonisolated private static func makeCommandComposition(
        inputs: AppIPCCommandCatalogProjectionInputs
    ) throws -> IPCCommandMethodComposition {
        let commands = try inputs.commandDescriptorInputs.map {
            try AgentStudioIPCCommandCatalogProjection.makeDescriptor(from: $0)
        }
        return try IPCCommandMethodComposition(
            compatibility: .current,
            commands: commands,
            recognizedUnexposedCommands: inputs.recognizedUnexposedCommands
        )
    }
}
