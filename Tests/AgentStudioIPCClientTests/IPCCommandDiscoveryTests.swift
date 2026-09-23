import AgentStudioIPCClientCore
import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("Live command catalog discovery")
struct IPCCommandDiscoveryTests {
    @Test("validated capabilities and command.list produce a descriptor-bound invocation")
    func validDiscoveryCreatesDescriptorBoundInvocation() throws {
        let fixture = try IPCCommandDiscoveryFixture.make()
        let discovery = try IPCCommandDiscovery(methodCatalog: fixture.methodCatalog)

        #expect(discovery.commandListInvocation.descriptor.metadata.name == "command.list")
        #expect(discovery.commandListInvocation.presentation == .tooling)

        let discoveredCatalog = try discovery.decodeCommandCatalog(
            from: JSONEncoder().encode(fixture.commandComposition.catalogResult)
        )
        let invocation = try discoveredCatalog.makeInvocation(
            commandId: fixture.noArgumentsCommandId,
            correlationId: fixture.correlationId,
            arguments: .noArguments
        )

        #expect(invocation.descriptor.metadata.name == "command.execute")
        #expect(invocation.descriptor.metadata.commandRelationship == .appCommandParameter(field: "commandId"))
        #expect(invocation.descriptor.metadata.correlationPolicy == .required)
        #expect(
            try JSONDecoder().decode(
                IPCCommandExecutionRequest.self,
                from: invocation.normalizedParameters
            )
                == IPCCommandExecutionRequest(
                    commandId: fixture.noArgumentsCommandId,
                    correlationId: fixture.correlationId,
                    arguments: .noArguments
                )
        )
    }

    @Test("open command IDs and closed argument variants are both enforced by the live catalog")
    func commandIdentityAndArgumentVariantMustMatchOneLiveDescriptor() throws {
        let fixture = try IPCCommandDiscoveryFixture.make()
        let catalog = try IPCCommandDiscovery(methodCatalog: fixture.methodCatalog)
            .decodeCommandCatalog(from: JSONEncoder().encode(fixture.commandComposition.catalogResult))

        let unknownIdentifier = try captureIPCCommandDiscoveryError {
            _ = try catalog.makeInvocation(
                commandId: IPCCommandIdentifier(rawValue: "future.private.command"),
                correlationId: fixture.correlationId,
                arguments: .noArguments
            )
        }
        let wrongVariant = try captureIPCCommandDiscoveryError {
            _ = try catalog.makeInvocation(
                commandId: fixture.noArgumentsCommandId,
                correlationId: fixture.correlationId,
                arguments: try fixture.paneArguments()
            )
        }

        #expect(unknownIdentifier.reason == .unknownCommandIdentifier)
        #expect(unknownIdentifier.fieldPath == "$.commandId")
        #expect(wrongVariant.reason == .argumentVariantNotAllowed)
        #expect(wrongVariant.fieldPath == "$.arguments.kind")
    }

    @Test("command result decoding preserves typed identity and correlation")
    func resultIdentityAndCorrelationRemainTyped() throws {
        let fixture = try IPCCommandDiscoveryFixture.make()
        let catalog = try IPCCommandDiscovery(methodCatalog: fixture.methodCatalog)
            .decodeCommandCatalog(from: JSONEncoder().encode(fixture.commandComposition.catalogResult))
        let invocation = try catalog.makeInvocation(
            commandId: fixture.noArgumentsCommandId,
            correlationId: fixture.correlationId,
            arguments: .noArguments
        )
        let expected = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(
                commandId: fixture.noArgumentsCommandId,
                correlationId: fixture.correlationId
            )
        )

        let result = try catalog.decodeResult(
            JSONEncoder().encode(expected),
            for: invocation
        )

        #expect(result == expected)
        #expect(result.commandId == fixture.noArgumentsCommandId)
        #expect(result.correlationId == fixture.correlationId)

        let wrongCorrelation = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(
                commandId: fixture.noArgumentsCommandId,
                correlationId: UUIDv7.generate()
            )
        )
        let error = try captureIPCCommandDiscoveryError {
            _ = try catalog.decodeResult(
                JSONEncoder().encode(wrongCorrelation),
                for: invocation
            )
        }
        #expect(error.reason == .resultCorrelationMismatch)
        #expect(error.fieldPath == "$.correlationId")
    }

    @Test("malformed live command payloads fail with controlled errors and do not echo private input")
    func malformedLivePayloadDoesNotEchoPrivateInput() throws {
        let fixture = try IPCCommandDiscoveryFixture.make()
        let discovery = try IPCCommandDiscovery(methodCatalog: fixture.methodCatalog)
        let privateValue = "PRIVATE-COMMAND-PAYLOAD-\u{1F512}"
        let malformed = Data(
            """
            {"compatibility":{"wireProtocolIdentifier":"agentstudio-ipc-jsonrpc-2","catalogIdentifier":"agentstudio-ipc-v2"},"commands":[{"private":"\(privateValue)"}]}
            """.utf8
        )

        let error = try captureIPCCommandDiscoveryError {
            _ = try discovery.decodeCommandCatalog(from: malformed)
        }

        #expect(error.reason == .invalidCommandCatalog)
        #expect(error.fieldPath == "$.commands")
        #expect(!String(describing: error).contains(privateValue))
        #expect(!String(describing: error).contains("private"))
    }
}

private struct IPCCommandDiscoveryFixture {
    let noArgumentsCommandId: IPCCommandIdentifier
    let paneCommandId: IPCCommandIdentifier
    let correlationId: UUID
    let workspaceWindowId: UUID
    let commandComposition: IPCCommandMethodComposition
    let methodCatalog: IPCMethodCatalogResult

    static func make() throws -> Self {
        let noArgumentsCommandId = IPCCommandIdentifier(rawValue: "fixture.noArguments")
        let paneCommandId = IPCCommandIdentifier(rawValue: "fixture.pane")
        let correlationId = UUIDv7.generate()
        let workspaceWindowId = UUIDv7.generate()
        let paneArguments = IPCCommandArguments.pane(
            IPCPaneCommandArguments(
                workspaceWindowId: workspaceWindowId,
                paneSelector: try IPCPaneSelector(rawValue: "self")
            )
        )
        let noArgumentsRequest = IPCCommandExecutionRequest(
            commandId: noArgumentsCommandId,
            correlationId: correlationId,
            arguments: .noArguments
        )
        let paneRequest = IPCCommandExecutionRequest(
            commandId: paneCommandId,
            correlationId: correlationId,
            arguments: paneArguments
        )
        let commands = try [
            IPCCommandDescriptorFactory.make(
                IPCCommandDescriptorInput(
                    id: noArgumentsCommandId,
                    title: "Fixture No Arguments",
                    description: "Apply a fixture command with no command-specific arguments.",
                    exposure: .allChannels,
                    executionMode: .headless,
                    argumentVariants: [.noArguments],
                    requiredPrivileges: [.appCommandExecute],
                    dataScope: .uiSurface,
                    allowedTargetKinds: [],
                    resultVariants: [.applied],
                    examples: [
                        IPCCommandExample(
                            description: "Apply the no-arguments fixture command.",
                            request: noArgumentsRequest,
                            result: .applied(
                                IPCCommandAppliedResult(
                                    commandId: noArgumentsCommandId,
                                    correlationId: correlationId
                                )
                            )
                        )
                    ],
                    agentEligibility: .notYetAllowed
                )
            ),
            IPCCommandDescriptorFactory.make(
                IPCCommandDescriptorInput(
                    id: paneCommandId,
                    title: "Fixture Pane",
                    description: "Accept a fixture command for one pane.",
                    exposure: .debugTesting,
                    executionMode: .headless,
                    argumentVariants: [.pane],
                    requiredPrivileges: [.appCommandExecute],
                    dataScope: .terminalInput,
                    allowedTargetKinds: [.pane],
                    resultVariants: [.accepted],
                    examples: [
                        IPCCommandExample(
                            description: "Accept the pane fixture command.",
                            request: paneRequest,
                            result: .accepted(
                                IPCCommandAcceptedResult(
                                    commandId: paneCommandId,
                                    correlationId: correlationId,
                                    operationId: UUIDv7.generate()
                                )
                            )
                        )
                    ],
                    agentEligibility: .notYetAllowed
                )
            ),
        ]
        let commandComposition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: commands
        )
        return Self(
            noArgumentsCommandId: noArgumentsCommandId,
            paneCommandId: paneCommandId,
            correlationId: correlationId,
            workspaceWindowId: workspaceWindowId,
            commandComposition: commandComposition,
            methodCatalog: try methodCatalog(advertising: commandComposition)
        )
    }

    private static func methodCatalog(
        advertising commandComposition: IPCCommandMethodComposition
    ) throws -> IPCMethodCatalogResult {
        let examples = IPCBuiltInMethodExampleContext(illustrativeIdentifier: UUIDv7.generate())
        let bootstrap = try IPCBuiltInMethodCatalog.bootstrapDescriptors(examples: examples)
        let ping = try #require(bootstrap.first { $0.metadata.name == "system.ping" })
        let advertised =
            bootstrap + [
                try IPCAnyMethodDescriptor(erasing: commandComposition.list),
                try IPCAnyMethodDescriptor(erasing: commandComposition.execute),
            ]
        return try IPCSystemCapabilitiesDescriptorFactory.compose(
            compatibility: .current,
            availableDescriptors: advertised,
            illustrativeDescriptor: ping
        ).result
    }

    func paneArguments() throws -> IPCCommandArguments {
        .pane(
            IPCPaneCommandArguments(
                workspaceWindowId: workspaceWindowId,
                paneSelector: try IPCPaneSelector(rawValue: "self")
            )
        )
    }
}

private func captureIPCCommandDiscoveryError(
    _ operation: () throws -> Void
) throws -> IPCCommandDiscoveryError {
    do {
        try operation()
    } catch let error as IPCCommandDiscoveryError {
        return error
    } catch {
        Issue.record("Expected IPCCommandDiscoveryError, received \(type(of: error))")
        throw error
    }
    Issue.record("Expected live command discovery to fail")
    throw IPCCommandDiscoveryTestError.expectedFailure
}

private enum IPCCommandDiscoveryTestError: Error {
    case expectedFailure
}
