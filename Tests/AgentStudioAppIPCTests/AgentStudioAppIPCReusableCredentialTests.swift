import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("App IPC reusable persisted credentials", .serialized)
struct AgentStudioAppIPCReusableCredentialTests {
    @Test("active pane verifier authenticates two sequential Unix connections without persisting its bearer")
    func activePaneVerifierAuthenticatesSequentialConnections() async throws {
        let fixture = try ReusableCredentialFixture()
        defer { fixture.cleanup() }
        let rawCredential = Data(repeating: 0xA5, count: 32)
        let token = AgentStudioIPCSubjectToken(rawValue: rawCredential.base64EncodedString())
        let verifier = Data(SHA256.hash(data: Data(token.rawValue.utf8)))
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generation = UUIDv7.generate()
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        try await repository.persistPreparedPaneCredential(
            paneID: paneID, workspaceID: workspaceID, generation: generation, verifier: verifier
        )
        try await repository.activatePreparedPaneCredential(paneID: paneID, generation: generation)
        let resolver = IPCContinuityCredentialResolver(repository: repository)
        let serverFixture = try fixture.makeServer(credentialResolver: resolver)
        defer { serverFixture.cleanup() }
        try serverFixture.server.start()

        let firstLogin = try await fixture.loginAndReadSystemVersion(
            fixture: serverFixture, token: token, requestID: 10
        )
        let secondLogin = try await fixture.loginAndReadSystemVersion(
            fixture: serverFixture, token: token, requestID: 20
        )
        #expect(firstLogin.runtimeID == serverFixture.runtimeId)
        #expect(firstLogin.accessMode == .agentStudioOnly)
        #expect(secondLogin.runtimeID == serverFixture.runtimeId)

        let forged = AgentStudioIPCSubjectToken(rawValue: Data(repeating: 0x5A, count: 32).base64EncodedString())
        let rejected = try await fixture.loginResponse(fixture: serverFixture, token: forged, requestID: 30)
        #expect(rejected.error?.code == -32_001)
        let stored = try #require(try await repository.credential(for: paneID, generation: generation))
        #expect(stored.verifier == verifier)
        #expect(stored.verifier != Data(token.rawValue.utf8))
    }

    @Test("prepared pane credential cannot authenticate")
    func preparedPaneCredentialIsRejectedBeforeMethodAdmission() async throws {
        let fixture = try ReusableCredentialFixture()
        defer { fixture.cleanup() }
        let token = AgentStudioIPCSubjectToken(rawValue: Data(repeating: 0xA5, count: 32).base64EncodedString())
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        try await repository.persistPreparedPaneCredential(
            paneID: UUIDv7.generate(),
            workspaceID: UUIDv7.generate(),
            generation: UUIDv7.generate(),
            verifier: Data(SHA256.hash(data: Data(token.rawValue.utf8)))
        )
        let serverFixture = try fixture.makeServer(
            credentialResolver: IPCContinuityCredentialResolver(repository: repository)
        )
        defer { serverFixture.cleanup() }
        try serverFixture.server.start()
        let response = try await fixture.loginResponse(fixture: serverFixture, token: token, requestID: 40)
        #expect(response.error?.code == -32_001)
    }
}

private struct ReusableCredentialFixture {
    let rootURL: URL
    let localDatabaseURL: URL
    let coreDatabaseURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-ipc-reusable-credential-\(UUIDv7.generate())")
        localDatabaseURL = rootURL.appending(path: "local.sqlite")
        coreDatabaseURL = rootURL.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func makeDatastore() -> WorkspaceSQLiteDatastoreActor {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
    }

    func makeServer(
        credentialResolver: any AgentStudioIPCCredentialResolving
    ) throws -> LiveServerFixture {
        try LiveServerFixture(credentialResolver: credentialResolver)
    }

    func loginAndReadSystemVersion(
        fixture: LiveServerFixture,
        token: AgentStudioIPCSubjectToken,
        requestID: Int
    ) async throws -> ReusableCredentialLoginResult {
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer { connection.close() }
        var reader = TestFrameReader()
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(requestID), method: "auth.login", params: .object(["token": .string(token.rawValue)])
            )
        )
        let loginResponse = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        let loginStatus = try decodeResponseResult(IPCAuthStatusResult.self, from: loginResponse)
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(id: .number(requestID + 1), method: "system.version", params: .object([:]))
        )
        let response = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        let version = try decodeResponseResult(IPCSystemVersionResult.self, from: response)
        #expect(!version.appVersion.isEmpty)
        guard case .authenticated(let principalID, let runtimeID, let accessMode) = loginStatus else {
            throw ReusableCredentialTestError.unauthenticated
        }
        return .init(principalID: principalID, runtimeID: runtimeID, accessMode: accessMode)
    }

    func loginResponse(
        fixture: LiveServerFixture,
        token: AgentStudioIPCSubjectToken,
        requestID: Int
    ) async throws -> JSONRPCResponseMessage {
        let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: fixture.paths.socketURL.path))
        defer { connection.close() }
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(requestID), method: "auth.login", params: .object(["token": .string(token.rawValue)])
            )
        )
        var reader = TestFrameReader()
        return try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct ReusableCredentialLoginResult: Equatable {
    let principalID: UUID
    let runtimeID: UUID
    let accessMode: IPCAccessMode
}

private enum ReusableCredentialTestError: Error {
    case unauthenticated
}
