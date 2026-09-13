import AgentStudioAppIPC
import AgentStudioIPCClientCore
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Dispatch
import Foundation
import Testing

@Suite("Live dynamic command ClientCore integration", .serialized)
struct AppIPCDynamicCommandClientTests {
    @Test("ClientCore discovers lists and executes one live typed command")
    func clientDiscoversListsAndExecutesTypedCommand() throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: scenario.fixture.paths.socketURL.path),
            descriptors: []
        )

        let methodCatalog = try client.discoverCatalog(requestID: 10)
        let discovery = try IPCCommandDiscovery(methodCatalog: methodCatalog)
        let listResponse = try requireSuccess(try client.call(discovery.commandListInvocation, requestID: 20))
        let commandCatalog = try discovery.decodeCommandCatalog(from: listResponse.normalizedResult)
        let invocation = try commandCatalog.makeInvocation(
            commandId: scenario.commandId,
            correlationId: scenario.correlationId,
            arguments: .noArguments
        )
        let executeResponse = try requireSuccess(try client.call(invocation, requestID: 30))
        let result = try commandCatalog.decodeResult(executeResponse.normalizedResult, for: invocation)

        #expect(methodCatalog.methods.contains { $0.name == "command.list" })
        #expect(methodCatalog.methods.contains { $0.name == "command.execute" })
        #expect(result.commandId == scenario.commandId)
        #expect(result.correlationId == scenario.correlationId)
        #expect(scenario.commandPort.receivedExecutionRequests.count == 1)
        #expect(scenario.commandPort.receivedExecutionRequests.first?.commandId == scenario.commandId)
        #expect(scenario.commandPort.receivedExecutionRequests.first?.correlationId == scenario.correlationId)
    }

    @Test("unknown identity and wrong variant are refused before the command port")
    func discoveryRefusesUnknownIdentityAndWrongVariantBeforePort() throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: scenario.fixture.paths.socketURL.path),
            descriptors: []
        )
        let discovery = try IPCCommandDiscovery(methodCatalog: client.discoverCatalog())
        let listResponse = try requireSuccess(try client.call(discovery.commandListInvocation, requestID: 10))
        let commandCatalog = try discovery.decodeCommandCatalog(from: listResponse.normalizedResult)

        #expect(throws: IPCCommandDiscoveryError.self) {
            _ = try commandCatalog.makeInvocation(
                commandId: IPCCommandIdentifier(rawValue: "futureCommand"),
                correlationId: UUIDv7.generate(),
                arguments: .noArguments
            )
        }
        #expect(throws: IPCCommandDiscoveryError.self) {
            _ = try commandCatalog.makeInvocation(
                commandId: scenario.commandId,
                correlationId: UUIDv7.generate(),
                arguments: .repository(IPCRepositoryCommandArguments(repoId: UUIDv7.generate()))
            )
        }
        #expect(scenario.commandPort.receivedExecutionRequests.isEmpty)
    }

    @Test("server rejects a command result whose correlation differs from its request")
    func serverRejectsMismatchedCommandResultIdentity() throws {
        let scenario = try DynamicCommandScenario.make(resultCorrelationId: UUIDv7.generate())
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: scenario.fixture.paths.socketURL.path),
            descriptors: []
        )
        let discovery = try IPCCommandDiscovery(methodCatalog: client.discoverCatalog())
        let listResponse = try requireSuccess(try client.call(discovery.commandListInvocation))
        let commandCatalog = try discovery.decodeCommandCatalog(from: listResponse.normalizedResult)
        let invocation = try commandCatalog.makeInvocation(
            commandId: scenario.commandId,
            correlationId: scenario.correlationId,
            arguments: .noArguments
        )

        switch try client.call(invocation, requestID: 40) {
        case .success:
            Issue.record("Mismatched command result must not cross the server boundary")
        case .remoteFailure(let failure):
            #expect(failure.code == -32_602)
        }
        #expect(scenario.commandPort.receivedExecutionRequests.count == 1)
    }

    @Test("raw server requests reject unknown identity and wrong variant before execution")
    func rawServerRequestsRejectInvalidCommandSelectionBeforePort() throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()

        let unknownResponse = try sendRequest(
            socketPath: scenario.fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(45),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecutionRequest(
                        commandId: IPCCommandIdentifier(rawValue: "futureCommand"),
                        correlationId: UUIDv7.generate(),
                        arguments: .noArguments
                    )
                )
            )
        )
        #expect(unknownResponse.error?.code == -32_003)
        #expect(unknownResponse.error?.message == "unsupported capability")
        #expect(scenario.commandPort.receivedExecutionRequests.isEmpty)

        let wrongVariantResponse = try sendRequest(
            socketPath: scenario.fixture.paths.socketURL.path,
            request: JSONRPCClientRequest(
                id: .number(46),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(
                    IPCCommandExecutionRequest(
                        commandId: scenario.commandId,
                        correlationId: UUIDv7.generate(),
                        arguments: .repository(
                            IPCRepositoryCommandArguments(repoId: UUIDv7.generate())
                        )
                    )
                )
            )
        )
        #expect(wrongVariantResponse.error?.code == -32_602)
        #expect(wrongVariantResponse.error?.message == "invalid params")
        #expect(scenario.commandPort.receivedExecutionRequests.isEmpty)
    }

    @Test("one authenticated socket can list and execute after its single login")
    func oneAuthenticatedConnectionSupportsMultipleCommandCalls() throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let principal = IPCPrincipal(
            principalId: UUIDv7.generate(),
            runtimeId: scenario.fixture.runtimeId,
            accessMode: .unsafeDebug,
            kind: .automationClient,
            approvalAuthority: .noApprovalAuthority
        )
        let token = try scenario.fixture.server.principalRegistry.issueSubjectToken(for: principal)
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: scenario.fixture.paths.socketURL.path))
        defer { connection.close() }
        var reader = TestFrameReader()
        try login(connection: connection, token: token, requestId: 50, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(id: .number(51), method: "command.list", params: .object([:]))
        )
        let listResponse = try reader.receiveResponse(connection: connection)
        let catalog = try decodeResponseResult(IPCCommandCatalogResult.self, from: listResponse)
        #expect(catalog.commands.map(\.id) == [scenario.commandId])

        let request = IPCCommandExecutionRequest(
            commandId: scenario.commandId,
            correlationId: scenario.correlationId,
            arguments: .noArguments
        )
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(52),
                method: "command.execute",
                params: try JSONRPCCodec.encodeJSONValue(request)
            )
        )
        let executeResponse = try reader.receiveResponse(connection: connection)
        let result = try decodeResponseResult(IPCCommandExecutionResult.self, from: executeResponse)

        #expect(result.commandId == scenario.commandId)
        #expect(result.correlationId == scenario.correlationId)
        #expect(scenario.commandPort.receivedExecutionRequests == [request])
    }

    @Test("built CLI lists and executes through the live dynamic registry")
    func builtCLIListsAndExecutesLiveCommand() throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let executableURL = try cliExecutableURL()
        var environment = ProcessInfo.processInfo.environment
        environment["AGENTSTUDIO_IPC_SOCKET"] = scenario.fixture.paths.socketURL.path
        environment.removeValue(forKey: "AGENTSTUDIO_PANE_TOKEN")

        let list = try runCLI(
            executableURL: executableURL,
            arguments: ["command.list"],
            environment: environment
        )
        #expect(list.exitCode == 0)
        #expect(list.standardError.isEmpty)
        let commandCatalog = try JSONDecoder().decode(IPCCommandCatalogResult.self, from: list.standardOutput)
        #expect(commandCatalog.commands.map(\.id) == [scenario.commandId])

        let request = IPCCommandExecutionRequest(
            commandId: scenario.commandId,
            correlationId: scenario.correlationId,
            arguments: .noArguments
        )
        let requestJSON = try #require(String(data: JSONEncoder().encode(request), encoding: .utf8))
        let execute = try runCLI(
            executableURL: executableURL,
            arguments: ["command.execute", "--json", requestJSON],
            environment: environment
        )
        #expect(execute.exitCode == 0)
        #expect(execute.standardError.isEmpty)
        let result = try JSONDecoder().decode(IPCCommandExecutionResult.self, from: execute.standardOutput)
        #expect(result.commandId == scenario.commandId)
        #expect(result.correlationId == scenario.correlationId)
        #expect(scenario.commandPort.receivedExecutionRequests == [request])
    }
}

private struct DynamicCommandScenario {
    let commandId: IPCCommandIdentifier
    let correlationId: UUID
    let commandPort: FakeCommandPort
    let fixture: LiveServerFixture

    static func make(resultCorrelationId: UUID? = nil) throws -> Self {
        let commandId = IPCCommandIdentifier(rawValue: "fixture.liveCommand")
        let correlationId = UUIDv7.generate()
        let descriptorResult = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(commandId: commandId, correlationId: correlationId))
        let descriptor = try makeFakeCommandDescriptor(
            FakeCommandDescriptorInput(
                id: commandId,
                executionMode: .headless,
                arguments: .noArguments,
                requiredPrivileges: [.appCommandExecute],
                dataScope: .unspecified,
                allowedTargetKinds: [],
                result: descriptorResult
            )
        )
        let runtimeResult = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(
                commandId: commandId,
                correlationId: resultCorrelationId ?? correlationId
            ))
        let commandPort = FakeCommandPort(
            commands: [descriptor],
            executionResultsByCommandId: [commandId.rawValue: runtimeResult]
        )
        let composition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: [descriptor]
        )
        return try Self(
            commandId: commandId,
            correlationId: correlationId,
            commandPort: commandPort,
            fixture: LiveServerFixture(
                accessMode: .unsafeDebug,
                channel: .debug,
                commandPort: commandPort,
                commandComposition: composition
            )
        )
    }
}

private func requireSuccess(
    _ result: IPCDescriptorClientCallResult
) throws -> IPCDescriptorClientResponse {
    switch result {
    case .success(let response):
        return response
    case .remoteFailure(let failure):
        Issue.record("Expected successful live ClientCore call, received \(failure.code)")
        throw DynamicCommandClientTestError.remoteFailure
    }
}

private enum DynamicCommandClientTestError: Error {
    case remoteFailure
    case subprocessTimedOut
}

private struct CLIProcessResult {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

private func cliExecutableURL() throws -> URL {
    let buildDirectory = try #require(ProcessInfo.processInfo.environment["SWIFT_BUILD_DIR"])
    let testFileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let resolvedBuildDirectory =
        buildDirectory.hasPrefix("/")
        ? URL(fileURLWithPath: buildDirectory)
        : projectRoot.appending(path: buildDirectory)
    return resolvedBuildDirectory.appending(path: "debug/agentstudio-ipc")
}

private func runCLI(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]
) throws -> CLIProcessResult {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    let completion = DispatchSemaphore(value: 0)
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.terminationHandler = { _ in completion.signal() }
    try process.run()
    guard completion.wait(timeout: .now() + 10) == .success else {
        process.terminate()
        process.waitUntilExit()
        throw DynamicCommandClientTestError.subprocessTimedOut
    }
    process.waitUntilExit()
    return CLIProcessResult(
        exitCode: process.terminationStatus,
        standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        standardError: standardError.fileHandleForReading.readDataToEndOfFile()
    )
}
