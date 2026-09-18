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
    func clientDiscoversListsAndExecutesTypedCommand() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: scenario.fixture.paths.socketURL.path),
            descriptors: []
        )

        let methodCatalog = try await client.discoverCatalogWithoutBlockingCooperativePool(requestID: 10)
        let discovery = try IPCCommandDiscovery(methodCatalog: methodCatalog)
        let listResponse = try requireSuccess(
            try await client.callWithoutBlockingCooperativePool(
                discovery.commandListInvocation, requestID: 20))
        let commandCatalog = try discovery.decodeCommandCatalog(from: listResponse.normalizedResult)
        let invocation = try commandCatalog.makeInvocation(
            commandId: scenario.commandId,
            correlationId: scenario.correlationId,
            arguments: .noArguments
        )
        let executeResponse = try requireSuccess(
            try await client.callWithoutBlockingCooperativePool(invocation, requestID: 30))
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
    func discoveryRefusesUnknownIdentityAndWrongVariantBeforePort() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: scenario.fixture.paths.socketURL.path),
            descriptors: []
        )
        let discovery = try IPCCommandDiscovery(
            methodCatalog: try await client.discoverCatalogWithoutBlockingCooperativePool())
        let listResponse = try requireSuccess(
            try await client.callWithoutBlockingCooperativePool(
                discovery.commandListInvocation, requestID: 10))
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
    func serverRejectsMismatchedCommandResultIdentity() async throws {
        let scenario = try DynamicCommandScenario.make(resultCorrelationId: UUIDv7.generate())
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: scenario.fixture.paths.socketURL.path),
            descriptors: []
        )
        let discovery = try IPCCommandDiscovery(
            methodCatalog: try await client.discoverCatalogWithoutBlockingCooperativePool())
        let listResponse = try requireSuccess(
            try await client.callWithoutBlockingCooperativePool(discovery.commandListInvocation))
        let commandCatalog = try discovery.decodeCommandCatalog(from: listResponse.normalizedResult)
        let invocation = try commandCatalog.makeInvocation(
            commandId: scenario.commandId,
            correlationId: scenario.correlationId,
            arguments: .noArguments
        )

        switch try await client.callWithoutBlockingCooperativePool(invocation, requestID: 40) {
        case .success:
            Issue.record("Mismatched command result must not cross the server boundary")
        case .remoteFailure(let failure):
            #expect(failure.code == -32_602)
        }
        #expect(scenario.commandPort.receivedExecutionRequests.count == 1)
    }

    @Test("raw server requests reject unknown identity and wrong variant before execution")
    func rawServerRequestsRejectInvalidCommandSelectionBeforePort() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()

        let unknownResponse = try await sendRequestWithoutBlockingCooperativePool(
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

        let wrongVariantResponse = try await sendRequestWithoutBlockingCooperativePool(
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
    func oneAuthenticatedConnectionSupportsMultipleCommandCalls() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let token = scenario.fixture.installDebugCredential()
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: scenario.fixture.paths.socketURL.path))
        defer { connection.close() }
        var reader = TestFrameReader()
        try await loginWithoutBlockingMainActor(
            connection: connection, token: token, requestId: 50, reader: &reader)

        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(id: .number(51), method: "command.list", params: .object([:]))
        )
        let listResponse = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
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
        let executeResponse = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        let result = try decodeResponseResult(IPCCommandExecutionResult.self, from: executeResponse)

        #expect(result.commandId == scenario.commandId)
        #expect(result.correlationId == scenario.correlationId)
        #expect(scenario.commandPort.receivedExecutionRequests == [request])
    }

    @Test("built CLI lists and executes through the live dynamic registry")
    func builtCLIListsAndExecutesLiveCommand() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let executableURL = try cliExecutableURL()
        var environment = ProcessInfo.processInfo.environment
        environment["AGENTSTUDIO_IPC_SOCKET"] = scenario.fixture.paths.socketURL.path
        environment.removeValue(forKey: "AGENTSTUDIO_PANE_TOKEN")

        let list = try await runCLI(
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
        let execute = try await runCLI(
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

    @Test("built CLI renders an unknown dynamic command correction without reflecting its identifier")
    func builtCLIRendersUnknownDynamicCommandCorrection() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let executableURL = try cliExecutableURL()
        let environment = makeCLIEnvironment(for: scenario)
        let privateMarker = "PRIVATE-COMMAND-ID-MUST-NOT-REFLECT"

        let unknown = try await runCLI(
            executableURL: executableURL,
            arguments: [
                "command.execute", "--json",
                try commandRequestJSON(
                    commandId: IPCCommandIdentifier(rawValue: privateMarker),
                    correlationId: UUIDv7.generate(),
                    arguments: .noArguments
                ),
            ],
            environment: environment
        )
        let unknownError = try requireStructuredCLIError(unknown)
        #expect(unknownError.reason == "unknownCommand")
        #expect(unknownError.fieldPath == "$.commandId")
        #expect(unknownError.catalogMethod == "command.list")
        #expect(unknownError.expected == "an identifier advertised by command.list")
        let standardError = try #require(String(data: unknown.standardError, encoding: .utf8))
        #expect(!standardError.contains(privateMarker))
    }

    @Test("built CLI renders a selected-command argument correction without reflecting argument values")
    func builtCLIRendersWrongDynamicCommandVariantCorrection() async throws {
        let scenario = try DynamicCommandScenario.make(includesRepositoryAlternative: true)
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let executableURL = try cliExecutableURL()
        let privateRepositoryIdentifier = UUIDv7.generate()
        let wrongVariant = try await runCLI(
            executableURL: executableURL,
            arguments: [
                "command.execute", "--json",
                try commandRequestJSON(
                    commandId: scenario.commandId,
                    correlationId: UUIDv7.generate(),
                    arguments: .repository(IPCRepositoryCommandArguments(repoId: privateRepositoryIdentifier))
                ),
            ],
            environment: makeCLIEnvironment(for: scenario)
        )
        let wrongVariantError = try requireStructuredCLIError(wrongVariant)
        #expect(wrongVariantError.reason == "invalidParams")
        #expect(wrongVariantError.fieldPath == "$.arguments.kind")
        #expect(wrongVariantError.expected == "an argument variant advertised for the selected command")
        #expect(wrongVariantError.catalogMethod == "command.list")
        let standardError = try #require(String(data: wrongVariant.standardError, encoding: .utf8))
        #expect(!standardError.contains(privateRepositoryIdentifier.uuidString))
    }

    @Test("built CLI renders known unavailable command correction")
    func builtCLIRendersUnavailableDynamicCommandCorrection() async throws {
        let unavailableScenario = try DynamicCommandScenario.make(resultAvailable: false)
        defer { unavailableScenario.fixture.cleanup() }
        try unavailableScenario.fixture.server.start()
        let executableURL = try cliExecutableURL()
        let unavailable = try await runCLI(
            executableURL: executableURL,
            arguments: [
                "command.execute", "--json",
                try commandRequestJSON(
                    commandId: unavailableScenario.commandId,
                    correlationId: unavailableScenario.correlationId,
                    arguments: .noArguments
                ),
            ],
            environment: makeCLIEnvironment(for: unavailableScenario)
        )
        let unavailableError = try requireStructuredCLIError(unavailable)
        #expect(unavailableError.reason == "stateUnavailable")
        #expect(unavailableError.fieldPath == "$.commandId")
        #expect(unavailableError.expected == nil)
        #expect(unavailableError.catalogMethod == nil)
    }

    @Test("built CLI renders foreign capabilities as unsupported version")
    func builtCLIRendersUnsupportedVersionFromLiveSocket() async throws {
        let endpoint = UnixSocketEndpoint(path: temporaryDynamicCommandSocketPath())
        let listener = UnixSocketListener(endpoint: endpoint)
        let privateCompatibilityMarker = "PRIVATE-FOREIGN-CATALOG-MUST-NOT-REFLECT"
        let foreignCatalog = IPCMethodCatalogResult(
            compatibility: IPCProtocolCatalogCompatibility(
                wireProtocolIdentifier: "foreign-wire-\(privateCompatibilityMarker)",
                catalogIdentifier: "foreign-catalog-\(privateCompatibilityMarker)"
            ),
            methods: []
        )
        try listener.start { connection in
            defer { connection.close() }
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 1_048_576)
            let request = try receiveListenerHandlerRequest(connection: connection, decoder: &decoder)
            #expect(request.method == "system.capabilities")
            try connection.send(
                dynamicCommandResponseFrame(id: request.id, result: foreignCatalog)
            )
        }
        defer { listener.stop() }

        let result = try await runCLI(
            executableURL: cliExecutableURL(),
            arguments: ["system.capabilities"],
            environment: makeCLIEnvironment(socketPath: endpoint.path)
        )
        let structuredError = try requireStructuredCLIError(result)
        #expect(structuredError.reason == "unsupportedVersion")
        #expect(structuredError.fieldPath == "$.compatibility")
        #expect(structuredError.expected?.isEmpty == false)
        let standardError = try #require(String(data: result.standardError, encoding: .utf8))
        #expect(!standardError.contains(privateCompatibilityMarker))
    }

    @Test("built CLI renders a missing required method parameter as invalid params")
    func builtCLIRendersMissingRequiredParameter() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()

        let result = try await runCLI(
            executableURL: cliExecutableURL(),
            arguments: ["terminal.send", "--handle", "self"],
            environment: makeCLIEnvironment(for: scenario)
        )
        let structuredError = try requireStructuredCLIError(result)
        #expect(structuredError.reason == "invalidParams")
        #expect(structuredError.fieldPath == "$.input")
        #expect(structuredError.expected?.isEmpty == false)
        #expect(structuredError.catalogMethod == nil)
    }

    @Test("built CLI preserves an App IPC missing grant scope")
    func builtCLIRendersCanonicalMissingGrantScope() async throws {
        let scenario = try MissingGrantCredentialScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()

        let result = try await runCLI(
            executableURL: cliExecutableURL(),
            arguments: [
                "command.execute", "--json",
                try commandRequestJSON(
                    commandId: scenario.commandId,
                    correlationId: scenario.correlationId,
                    arguments: .noArguments
                ),
            ],
            environment: scenario.cliEnvironment
        )
        let structuredError = try requireStructuredCLIError(result)
        #expect(structuredError.reason == "missingGrant")
        #expect(structuredError.fieldPath == "$.authorization")
        #expect(structuredError.requiredScope == scenario.requiredScope)
        #expect(structuredError.catalogMethod == nil)
        #expect(scenario.commandPort.receivedExecutionRequests.isEmpty)
    }

    @Test("built CLI renders an unknown method correction without reflecting its identifier")
    func builtCLIRendersUnknownMethodCorrection() async throws {
        let scenario = try DynamicCommandScenario.make()
        defer { scenario.fixture.cleanup() }
        try scenario.fixture.server.start()
        let privateMethodMarker = "private.future.method.DO_NOT_REFLECT"

        let result = try await runCLI(
            executableURL: cliExecutableURL(),
            arguments: [privateMethodMarker],
            environment: makeCLIEnvironment(for: scenario)
        )
        let structuredError = try requireStructuredCLIError(result)
        #expect(structuredError.reason == "unknownMethod")
        #expect(structuredError.fieldPath == "$.method")
        #expect(structuredError.catalogMethod == "system.capabilities")
        let standardError = try #require(String(data: result.standardError, encoding: .utf8))
        #expect(!standardError.contains(privateMethodMarker))
    }
}

private struct DynamicCommandScenario {
    let commandId: IPCCommandIdentifier
    let correlationId: UUID
    let commandPort: FakeCommandPort
    let fixture: LiveServerFixture

    static func make(
        resultCorrelationId: UUID? = nil,
        resultAvailable: Bool = true,
        includesRepositoryAlternative: Bool = false
    ) throws -> Self {
        let commandId = IPCCommandIdentifier(rawValue: "fixture.liveCommand")
        let repositoryCommandId = IPCCommandIdentifier(rawValue: "fixture.repositoryCommand")
        let correlationId = UUIDv7.generate()
        let descriptorResult = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(commandId: commandId, correlationId: correlationId))
        let repositoryDescriptorResult = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(commandId: repositoryCommandId, correlationId: correlationId))
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
        let commands: [IPCCommandDescriptor]
        if includesRepositoryAlternative {
            let repositoryDescriptor = try makeFakeCommandDescriptor(
                FakeCommandDescriptorInput(
                    id: repositoryCommandId,
                    executionMode: .headless,
                    arguments: .repository(IPCRepositoryCommandArguments(repoId: UUIDv7.generate())),
                    requiredPrivileges: [.appCommandExecute],
                    dataScope: .unspecified,
                    allowedTargetKinds: [],
                    result: repositoryDescriptorResult
                )
            )
            commands = [descriptor, repositoryDescriptor]
        } else {
            commands = [descriptor]
        }
        let runtimeResult = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(
                commandId: commandId,
                correlationId: resultCorrelationId ?? correlationId
            ))
        let commandPort = FakeCommandPort(
            commands: commands,
            executionResultsByCommandId: resultAvailable ? [commandId.rawValue: runtimeResult] : [:]
        )
        let composition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: commands
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

private struct MissingGrantCredentialScenario {
    let commandId: IPCCommandIdentifier
    let correlationId: UUID
    let requiredScope: IPCPermissionScope
    let commandPort: FakeCommandPort
    let fixture: LiveServerFixture
    let authenticationToken: String

    var cliEnvironment: [String: String] {
        var environment = makeCLIEnvironment(socketPath: fixture.paths.socketURL.path)
        environment["AGENTSTUDIO_PANE_TOKEN"] = authenticationToken
        return environment
    }

    static func make() throws -> Self {
        let commandId = IPCCommandIdentifier(rawValue: "fixture.missingGrantCommand")
        let correlationId = UUIDv7.generate()
        let descriptorResult = IPCCommandExecutionResult.applied(
            IPCCommandAppliedResult(commandId: commandId, correlationId: correlationId)
        )
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
        let commandPort = FakeCommandPort(commands: [descriptor])
        let composition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: [descriptor]
        )
        let requiredScope = IPCPermissionScope(
            privilege: .appCommandExecute,
            target: .app,
            dataScope: .unspecified
        )
        let fixture = try LiveServerFixture(
            commandPort: commandPort,
            commandComposition: composition
        )
        let authenticationToken = try fixture.issueTestCredential(
            for: .pane(
                paneId: fixture.boundPaneId,
                credentialRecordId: UUIDv7.generate(),
                status: .registered
            )
        )
        return Self(
            commandId: commandId,
            correlationId: correlationId,
            requiredScope: requiredScope,
            commandPort: commandPort,
            fixture: fixture,
            authenticationToken: authenticationToken.rawValue
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

struct CLIProcessResult {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

private struct StructuredCLIError: Decodable {
    let reason: String
    let fieldPath: String?
    let expected: String?
    let catalogMethod: String?
    let requiredScope: IPCPermissionScope?
}

private func makeCLIEnvironment(for scenario: DynamicCommandScenario) -> [String: String] {
    makeCLIEnvironment(socketPath: scenario.fixture.paths.socketURL.path)
}

private func makeCLIEnvironment(socketPath: String) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["AGENTSTUDIO_IPC_SOCKET"] = socketPath
    environment.removeValue(forKey: "AGENTSTUDIO_PANE_TOKEN")
    return environment
}

private func commandRequestJSON(
    commandId: IPCCommandIdentifier,
    correlationId: UUID,
    arguments: IPCCommandArguments
) throws -> String {
    let request = IPCCommandExecutionRequest(
        commandId: commandId,
        correlationId: correlationId,
        arguments: arguments
    )
    return try #require(String(data: JSONEncoder().encode(request), encoding: .utf8))
}

private func requireStructuredCLIError(_ result: CLIProcessResult) throws -> StructuredCLIError {
    #expect(result.exitCode != 0)
    #expect(result.standardOutput.isEmpty)
    return try JSONDecoder().decode(StructuredCLIError.self, from: result.standardError)
}

private func temporaryDynamicCommandSocketPath() -> String {
    "/tmp/asipc-cli-errors-\(UUIDv7.generate().uuidString).sock"
}

private func dynamicCommandResponseFrame<Result: Encodable>(
    id: JSONRPCIdentifier?,
    result: Result
) throws -> Data {
    try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeResponse(
            .success(id: id, result: try JSONRPCCodec.encodeJSONValue(result))
        ),
        maxFrameBytes: 1_048_576
    )
}

func cliExecutableURL() throws -> URL {
    let buildDirectory = try #require(ProcessInfo.processInfo.environment["SWIFT_BUILD_DIR"])
    let testFileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let resolvedBuildDirectory =
        buildDirectory.hasPrefix("/")
        ? URL(fileURLWithPath: buildDirectory)
        : projectRoot.appending(path: buildDirectory)
    return resolvedBuildDirectory.appending(path: "debug/agentstudio-cli")
}

/// A hang guard, not a performance assertion.
///
/// Ten seconds was close enough to what a CLI subprocess and a real server
/// harness take under the fully parallel fast lane that it failed the run
/// rather than catching anything. No case here asserts elapsed time, so the
/// only job left is to end a process that will never exit.
private let cliSubprocessTimeout = DispatchTimeInterval.seconds(120)

/// How long a stranded child gets to honour SIGTERM before it is killed.
private let cliSubprocessTerminationGrace = DispatchTimeInterval.seconds(5)

/// Runs the built CLI off the cooperative pool and writes both streams to files.
///
/// Two hazards shape this, and both have already cost a CI run:
///
/// - Swift Testing runs each test body as a task on the cooperative executor,
///   whose width is the machine's core count, and `AgentStudioAppIPCServer`
///   answers every accepted connection from a `Task` on that same pool. Waiting
///   for the child on the test's own thread starves the server the child is
///   waiting on, so a three-core runner deadlocks the whole lane once enough
///   blocking cases run at once. The wait happens on a libdispatch thread,
///   which grows on demand, and the caller suspends instead of blocking.
/// - `command.list` returns more than a pipe buffer holds. Reading a pipe only
///   after the child exits deadlocks as soon as the child fills that buffer, so
///   both channels go to files the way the App-target runner does.
func runCLI(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]
) async throws -> CLIProcessResult {
    let standardOutputURL = FileManager.default.temporaryDirectory
        .appending(path: "as-cli-out-\(UUIDv7.generate().uuidString)")
    let standardErrorURL = FileManager.default.temporaryDirectory
        .appending(path: "as-cli-err-\(UUIDv7.generate().uuidString)")
    FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
    FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
    defer {
        try? FileManager.default.removeItem(at: standardOutputURL)
        try? FileManager.default.removeItem(at: standardErrorURL)
    }

    let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
                let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
                defer {
                    try? standardOutputHandle.close()
                    try? standardErrorHandle.close()
                }
                let process = Process()
                let completion = DispatchSemaphore(value: 0)
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = standardOutputHandle
                process.standardError = standardErrorHandle
                process.terminationHandler = { _ in completion.signal() }
                try process.run()
                guard completion.wait(timeout: .now() + cliSubprocessTimeout) == .success else {
                    endStrandedCLISubprocess(process, completion: completion)
                    continuation.resume(throwing: DynamicCommandClientTestError.subprocessTimedOut)
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    return CLIProcessResult(
        exitCode: exitCode,
        standardOutput: (try? Data(contentsOf: standardOutputURL)) ?? Data(),
        standardError: (try? Data(contentsOf: standardErrorURL)) ?? Data()
    )
}

/// SIGTERM first, SIGKILL if that is ignored, and a bounded reap either way.
///
/// `waitUntilExit()` on its own is unbounded: a child that ignores termination
/// would hold this thread, and its own process, for the rest of the run. The
/// timed-out case is exactly the case that must not leak.
private func endStrandedCLISubprocess(_ process: Process, completion: DispatchSemaphore) {
    process.terminate()
    guard completion.wait(timeout: .now() + cliSubprocessTerminationGrace) != .success else { return }
    kill(process.processIdentifier, SIGKILL)
    _ = completion.wait(timeout: .now() + cliSubprocessTerminationGrace)
}
