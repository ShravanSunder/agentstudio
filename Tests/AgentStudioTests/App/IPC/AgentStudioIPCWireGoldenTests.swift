import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Agent Studio IPC wire goldens")
struct AgentStudioIPCWireGoldenTests {
    @Test("stable capabilities and command method schemas match the captured wire bytes")
    func stableIPCWireOutputMatchesGolden() throws {
        let actualBytes = try Self.makeStableWireSnapshot()
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "w3a-wire-baseline",
                withExtension: "json",
                subdirectory: "IPC"
            )
        )
        let expectedBytes = try Data(contentsOf: fixtureURL)
        let matchesGoldenBytes = actualBytes == expectedBytes
        #expect(matchesGoldenBytes)
    }

    private static func makeStableWireSnapshot() throws -> Data {
        let channel = AgentStudioIPCChannel.stable
        let exampleContext = try makeStableExampleContext()
        let builtInCatalog = try IPCBuiltInMethodCatalog(
            inputs: IPCBuiltInMethodCatalogInputs(
                terminalWaitMaximumSeconds: AppPolicies.IPC.maximumTerminalWaitSeconds,
                relationships: IPCBuiltInMethodRelationshipInputs(
                    paneFocus: .appCommand(identifier: AppCommand.focusPane.rawValue),
                    paneClose: .appCommand(identifier: AppCommand.closePane.rawValue),
                    drawerToggle: .appCommand(identifier: AppCommand.toggleDrawer.rawValue),
                    drawerAddPane: .appCommand(identifier: AppCommand.addDrawerPane.rawValue),
                    bridgeDiffLoad: .appCommand(identifier: AppCommand.showBridgeReview.rawValue),
                    bridgeFileViewOpen: .appCommand(identifier: AppCommand.showBridgeFiles.rawValue)
                ),
                examples: exampleContext
            )
        )
        let commandDescriptors =
            try AgentStudioIPCCommandCatalogProjection
            .admittedCommands(on: channel)
            .map { try AgentStudioIPCCommandCatalogProjection.makeDescriptor(for: $0) }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        let commandComposition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: commandDescriptors,
            recognizedUnexposedCommands:
                AgentStudioIPCCommandCatalogProjection
                .recognizedUnexposedCommands(on: channel)
        )
        let commandListMethod: IPCMethodDescriptor<IPCEmptyParams, IPCCommandCatalogResult> =
            commandComposition.list
        let commandExecuteMethod: IPCMethodDescriptor<IPCCommandExecutionRequest, IPCCommandExecutionResult> =
            commandComposition.execute
        let commandMethodDescriptors: [IPCAnyMethodDescriptor] = try [
            IPCAnyMethodDescriptor(erasing: commandListMethod),
            IPCAnyMethodDescriptor(erasing: commandExecuteMethod),
        ]
        let allMethodDescriptors = builtInCatalog.erasedDescriptors + commandMethodDescriptors
        let availableDescriptors: [IPCAnyMethodDescriptor] = allMethodDescriptors.filter {
            $0.metadata.exposure == IPCMethodExposure.allChannels || channel == AgentStudioIPCChannel.debug
        }
        let availableMethodNames = Set(availableDescriptors.map(\.metadata.name))
        let recognizedUnexposedMethods =
            allMethodDescriptors
            .filter { !availableMethodNames.contains($0.metadata.name) }
            .map {
                IPCRecognizedUnexposedName(
                    name: $0.metadata.name,
                    agentEligibility: $0.metadata.agentEligibility ?? .notYetAllowed
                )
            }
        let illustrativePing = try #require(
            availableDescriptors.first { $0.metadata.name == "system.ping" }
        )
        let capabilities = try IPCSystemCapabilitiesDescriptorFactory.compose(
            compatibility: .current,
            availableDescriptors: availableDescriptors,
            illustrativeDescriptor: illustrativePing,
            recognizedUnexposedMethods: recognizedUnexposedMethods
        )
        let methodNames = capabilities.result.methods.map(\.name)
        #expect(methodNames == methodNames.sorted())
        #expect(Set(methodNames).count == methodNames.count)

        let snapshot = StableIPCWireSnapshot(
            systemCapabilitiesResult: try capabilities.descriptor.encodeResult(capabilities.result),
            commandListMethod: commandComposition.list.metadata,
            commandExecuteMethod: commandComposition.execute.metadata
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    private static func makeStableExampleContext() throws -> IPCBuiltInMethodExampleContext {
        func fixedUUID(_ ordinal: Int) throws -> UUID {
            let suffix = String(format: "%012x", ordinal)
            return try #require(UUID(uuidString: "00000000-0000-7000-8000-\(suffix)"))
        }

        return IPCBuiltInMethodExampleContext(
            runtimeId: try fixedUUID(1),
            windowId: try fixedUUID(2),
            workspaceId: try fixedUUID(3),
            repositoryId: try fixedUUID(4),
            worktreeId: try fixedUUID(5),
            tabId: try fixedUUID(6),
            paneId: try fixedUUID(7),
            commandId: try fixedUUID(8),
            correlationId: try fixedUUID(9),
            subscriptionId: try fixedUUID(10)
        )
    }
}

private struct StableIPCWireSnapshot: Encodable {
    let systemCapabilitiesResult: Data
    let commandListMethod: IPCMethodDescriptorMetadata<IPCEmptyParams, IPCCommandCatalogResult>
    let commandExecuteMethod: IPCMethodDescriptorMetadata<IPCCommandExecutionRequest, IPCCommandExecutionResult>
}
