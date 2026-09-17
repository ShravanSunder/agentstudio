import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// Starts the real App IPC server over a temporary socket with a real Sessions
/// database, authenticated by a diagnostic credential. Session methods need no
/// window, so the harness stops at what the composition itself requires.
@MainActor
struct SessionsVerticalHarness {
    static let qualifiedProvider = IPCSessionProviderIdentity(
        identifier: "vertical-agent",
        version: "1.2.3",
        mode: "interactive"
    )

    let appDelegate: AppDelegate
    let commandHarness: PaneTabViewControllerCommandHarness
    let rootDirectory: URL
    let socketPath: String
    let token: AgentStudioIPCSubjectToken
    let boundPaneId: UUID
    let sparePaneId: UUID

    /// The profile the default provider identity qualifies against.
    static let qualifiedProviderProfile = SessionsProviderProfile(
        providerIdentifier: qualifiedProvider.identifier,
        exactVersion: qualifiedProvider.version,
        operatingMode: qualifiedProvider.mode,
        qualifiedCapabilities: [.sessionStart, .sessionEnd, .turnStart, .turnDone]
    )

    static func make(
        providerProfiles: [SessionsProviderProfile] = [qualifiedProviderProfile],
        additionalProviderProfiles: [SessionsProviderProfile] = []
    ) async throws -> Self {
        let commandHarness = makeHarness()
        let boundPane = commandHarness.store.createPane(title: "Bound pane")
        let sparePane = commandHarness.store.createPane(title: "Spare pane")
        commandHarness.store.appendTab(Tab(paneId: boundPane.id))
        commandHarness.store.appendTab(Tab(paneId: sparePane.id))
        // Pane handle canonicalization reads the current window before it
        // resolves a pane, so the harness registers exactly one.
        commandHarness.windowLifecycleStore.recordWindowRegistered(UUIDv7.generate())

        let sqliteFixture = try makeWorkspaceSQLiteBridgeFixture(
            workspaceId: commandHarness.store.identityAtom.workspaceId
        )
        let datastore = try preparedWorkspaceSQLiteDatastore(from: sqliteFixture.backend)
        guard case .ready = await datastore.prepareOptionalApplicationLocalSchema() else {
            throw SessionsVerticalHarnessError.optionalSchemaUnavailable
        }

        let appDelegate = AppDelegate()
        appDelegate.store = commandHarness.store
        appDelegate.workspaceSQLiteDatastore = datastore
        appDelegate.windowLifecycleStore = commandHarness.windowLifecycleStore
        appDelegate.atomStore = commandHarness.atomRegistry
        appDelegate.viewRegistry = commandHarness.viewRegistry
        appDelegate.workspaceSurfaceCoordinator = commandHarness.coordinator
        appDelegate.executor = commandHarness.executor
        appDelegate.mainWindowController = SessionsVerticalMainWindowController(window: nil)
        appDelegate.appIPCSessionsProviderProfiles = providerProfiles + additionalProviderProfiles
        appDelegate.installAppIPCIdentityAuthority(datastore: datastore)

        // The tail of the identifier, not its head: a UUIDv7 begins with a
        // millisecond timestamp, so two harnesses built in the same millisecond
        // shared a directory name and the second failed to create it. The tail
        // is cryptographic random. The whole identifier will not do — the
        // socket underneath this root must fit in `sockaddr_un.sun_path`, which
        // is 104 bytes including the temporary directory and `/ipc/agentstudio.sock`.
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "as-ipc-\(UUIDv7.generate().uuidString.suffix(12))")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootDirectory)
        appDelegate.appIPCPaths = paths

        let token = AgentStudioIPCSubjectToken(rawValue: "sessions-vertical-\(UUIDv7.generate().uuidString)")
        let generationID = UUIDv7.generate()
        try await appDelegate.appIPCContinuityRepository.persistPreparedDiagnosticCredential(
            runtimeID: appDelegate.appIPCRuntimeID,
            generation: generationID,
            verifier: Data(SHA256.hash(data: Data(token.rawValue.utf8)))
        )
        try await appDelegate.appIPCContinuityRepository.activatePreparedDiagnosticCredential(
            runtimeID: appDelegate.appIPCRuntimeID,
            generation: generationID
        )
        await appDelegate.startAppIPCServer()
        guard appDelegate.appIPCServer != nil else {
            throw SessionsVerticalHarnessError.serverUnavailable
        }

        return Self(
            appDelegate: appDelegate,
            commandHarness: commandHarness,
            rootDirectory: rootDirectory,
            socketPath: paths.socketURL.path,
            token: token,
            boundPaneId: boundPane.id,
            sparePaneId: sparePane.id
        )
    }

    func tearDown() {
        appDelegate.stopAppIPCServer()
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func bindBoundPane() async throws -> IPCSessionEventResult {
        try await sessionEvent(
            paneId: boundPaneId,
            provider: Self.qualifiedProvider,
            name: "sessionStart",
            conversationId: "conversation-\(boundPaneId.uuidString)"
        )
    }

    func sessionEvent(
        paneId: UUID,
        provider: IPCSessionProviderIdentity,
        name: String,
        conversationId: String,
        correlationId: UUID = UUIDv7.generate()
    ) async throws -> IPCSessionEventResult {
        try await decoded(
            method: "session.event",
            params: .object([
                "handle": .string(paneId.uuidString),
                "provider": .object([
                    "identifier": .string(provider.identifier),
                    "version": .string(provider.version),
                    "mode": .string(provider.mode),
                ]),
                "event": .object([
                    "name": .string(name),
                    "conversationId": .string(conversationId),
                    "occurrenceId": .string(UUIDv7.generate().uuidString),
                ]),
                "correlationId": .string(correlationId.uuidString),
            ])
        )
    }

    /// Sends fully formed parameters, for a caller that built them somewhere
    /// else — a provider hook projection, say — rather than field by field here.
    func sessionEvent(params: IPCSessionEventParams) async throws -> IPCSessionEventResult {
        try await decoded(
            method: "session.event",
            params: try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(params))
        )
    }

    func sessionReport(
        paneId: UUID,
        kind: String,
        explanation: String?,
        correlationId: UUID = UUIDv7.generate()
    ) async throws -> IPCSessionReportResult {
        try await decoded(
            method: "session.report",
            params: Self.reportParams(
                paneId: paneId, kind: kind, explanation: explanation, correlationId: correlationId
            )
        )
    }

    func rawSessionReport(
        paneId: UUID,
        kind: String,
        explanation: String?,
        correlationId: UUID = UUIDv7.generate()
    ) async throws -> JSONRPCResponseMessage {
        try await response(
            method: "session.report",
            params: Self.reportParams(
                paneId: paneId, kind: kind, explanation: explanation, correlationId: correlationId
            )
        )
    }

    func sessionMessage(
        paneId: UUID,
        text: String,
        correlationId: UUID = UUIDv7.generate()
    ) async throws -> IPCSessionMessageResult {
        try await decoded(
            method: "session.message",
            params: .object([
                "handle": .string(paneId.uuidString),
                "text": .string(text),
                "correlationId": .string(correlationId.uuidString),
            ])
        )
    }

    func sessionQuery(paneId: UUID) async throws -> IPCSessionQueryResult {
        try await decoded(
            method: "session.query",
            params: .object(["handle": .string(paneId.uuidString)])
        )
    }

    private static func reportParams(
        paneId: UUID,
        kind: String,
        explanation: String?,
        correlationId: UUID
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "handle": .string(paneId.uuidString),
            "kind": .string(kind),
            "correlationId": .string(correlationId.uuidString),
        ]
        if let explanation { fields["explanation"] = .string(explanation) }
        return .object(fields)
    }

    func decoded<Result: Decodable>(
        method: String,
        params: JSONValue
    ) async throws -> Result {
        let message = try await response(method: method, params: params)
        if let error = message.error {
            throw SessionsVerticalHarnessError.requestFailed(method: method, code: error.code, data: error.data)
        }
        let result = try #require(message.result)
        return try JSONDecoder().decode(Result.self, from: try JSONEncoder().encode(result))
    }

    func response(method: String, params: JSONValue) async throws -> JSONRPCResponseMessage {
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: socketPath))
        defer { connection.close() }
        var reader = SessionsVerticalFrameReader()
        try send(
            connection: connection,
            request: try JSONRPCClientRequest(
                id: .number(1),
                method: "auth.login",
                params: .object(["token": .string(token.rawValue)])
            )
        )
        let loginResponse = try await reader.receiveResponse(connection: connection)
        try #require(loginResponse.error == nil)
        try send(
            connection: connection,
            request: try JSONRPCClientRequest(id: .number(2), method: method, params: params)
        )
        return try await reader.receiveResponse(connection: connection)
    }

    private func send(connection: UnixSocketConnection, request: JSONRPCClientRequest) throws {
        try connection.send(
            try NDJSONFrameEncoder.encode(JSONRPCCodec.encodeRequest(request), maxFrameBytes: 65_536)
        )
    }
}

enum SessionsVerticalHarnessError: Error {
    case optionalSchemaUnavailable
    case serverUnavailable
    case requestFailed(method: String, code: Int, data: JSONValue?)
}

@MainActor
final class SessionsVerticalMainWindowController: MainWindowController {
    override var acceptsIPCCommands: Bool { true }
}

struct SessionsVerticalFrameReader {
    private var decoder = NDJSONFrameDecoder(maxFrameBytes: 1_048_576)
    private var queuedFrames: [String] = []

    mutating func receiveResponse(connection: UnixSocketConnection) async throws -> JSONRPCResponseMessage {
        if !queuedFrames.isEmpty {
            return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
        }
        while true {
            let data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try connection.receive(maxBytes: 4096))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
            }
        }
    }
}
