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
    @Test("current RAM and older durable pane verifiers authenticate sequential Unix connections")
    func currentRAMAndOlderDurableVerifiersAuthenticateSequentialConnections() async throws {
        let fixture = try ReusableCredentialFixture()
        defer { fixture.cleanup() }
        let durableToken = AgentStudioIPCSubjectToken(
            rawValue: Data(repeating: 0xA5, count: 32).base64EncodedString())
        let currentToken = AgentStudioIPCSubjectToken(
            rawValue: Data(repeating: 0xB4, count: 32).base64EncodedString())
        let durableVerifier = Data(SHA256.hash(data: Data(durableToken.rawValue.utf8)))
        let currentVerifier = Data(SHA256.hash(data: Data(currentToken.rawValue.utf8)))
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        let serverFixture = try fixture.makeServer(
            credentialResolver: IPCContinuityCredentialResolver(repository: repository)
        )
        defer { serverFixture.cleanup() }
        let paneID = serverFixture.boundPaneId
        let durableRecordID = UUIDv7.generate()
        let currentRecordID = UUIDv7.generate()
        try await repository.registerPaneCredential(
            IPCPaneCredential(
                paneID: paneID,
                workspaceID: serverFixture.workspaceId,
                credentialRecordID: durableRecordID,
                verifierSHA256: durableVerifier,
                status: .registered
            )
        )
        try serverFixture.server.principalRegistry.registerIssuedPaneCredential(
            paneID: paneID,
            workspaceID: serverFixture.workspaceId,
            credentialRecordID: currentRecordID,
            verifierSHA256: currentVerifier
        )
        try serverFixture.server.start()

        for (index, token) in [currentToken, durableToken, currentToken, durableToken].enumerated() {
            let login = try await fixture.loginAndReadSystemVersion(
                fixture: serverFixture,
                token: token,
                requestID: 10 + (index * 10)
            )
            #expect(login.runtimeID == serverFixture.runtimeId)
            #expect(login.accessMode == .agentStudioOnly)
        }

        let forged = AgentStudioIPCSubjectToken(rawValue: Data(repeating: 0x5A, count: 32).base64EncodedString())
        let rejected = try await fixture.loginResponse(fixture: serverFixture, token: forged, requestID: 30)
        #expect(rejected.error?.code == -32_001)
        let stored = try #require(
            try await repository.paneCredential(paneID: paneID, credentialRecordID: durableRecordID))
        #expect(stored.verifierSHA256 == durableVerifier)
        #expect(stored.verifierSHA256 != Data(durableToken.rawValue.utf8))
        #expect(try await repository.paneCredential(paneID: paneID, credentialRecordID: currentRecordID) == nil)
    }

    @Test("revoked durable pane credential cannot authenticate")
    func revokedPaneCredentialIsRejectedBeforeMethodAdmission() async throws {
        let fixture = try ReusableCredentialFixture()
        defer { fixture.cleanup() }
        let token = AgentStudioIPCSubjectToken(rawValue: Data(repeating: 0xA5, count: 32).base64EncodedString())
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        let serverFixture = try fixture.makeServer(
            credentialResolver: IPCContinuityCredentialResolver(repository: repository)
        )
        defer { serverFixture.cleanup() }
        try await repository.registerPaneCredential(
            IPCPaneCredential(
                paneID: serverFixture.boundPaneId,
                workspaceID: serverFixture.workspaceId,
                credentialRecordID: UUIDv7.generate(),
                verifierSHA256: Data(SHA256.hash(data: Data(token.rawValue.utf8))),
                status: .revoked
            )
        )
        try serverFixture.server.start()
        let response = try await fixture.loginResponse(fixture: serverFixture, token: token, requestID: 40)
        #expect(response.error?.code == -32_001)
    }

    @Test("canonical close denial and final revocation refuse existing pane credential without a result")
    func canonicalCloseAndFinalRevocationRefuseCredential() async throws {
        let fixture = try ReusableCredentialFixture()
        defer { fixture.cleanup() }
        let membership = ReusableCredentialMembershipGate()
        let token = AgentStudioIPCSubjectToken(rawValue: Data(repeating: 0xC3, count: 32).base64EncodedString())
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        let serverFixture = try fixture.makeServer(
            credentialResolver: IPCContinuityCredentialResolver(repository: repository),
            canonicalPaneMembership: { _, _ in membership.isMember }
        )
        defer { serverFixture.cleanup() }
        try await repository.registerPaneCredential(
            IPCPaneCredential(
                paneID: serverFixture.boundPaneId,
                workspaceID: serverFixture.workspaceId,
                credentialRecordID: UUIDv7.generate(),
                verifierSHA256: Data(SHA256.hash(data: Data(token.rawValue.utf8))),
                status: .registered
            )
        )
        try serverFixture.server.start()
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: serverFixture.paths.socketURL.path)
        )
        defer { connection.close() }
        var reader = TestFrameReader()
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(
                id: .number(50), method: "auth.login", params: .object(["token": .string(token.rawValue)]))
        )
        let initialLoginResponse = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        let initialLoginStatus = try decodeResponseResult(IPCAuthStatusResult.self, from: initialLoginResponse)
        guard case .authenticated = initialLoginStatus else {
            Issue.record("Expected initial credential login to authenticate")
            return
        }

        membership.setMember(false)
        try sendRequest(
            connection: connection,
            request: JSONRPCClientRequest(id: .number(51), method: "system.version", params: .object([:]))
        )
        let closedResponse = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
        #expect(closedResponse.result == nil)
        #expect(closedResponse.error?.code == -32_001)

        serverFixture.server.invalidatePrincipals(boundToPaneId: serverFixture.boundPaneId.uuidString)
        try await repository.revokeAllPaneCredentials(paneID: serverFixture.boundPaneId)
        membership.setMember(true)
        let finalResponse = try await fixture.loginResponse(fixture: serverFixture, token: token, requestID: 52)
        #expect(finalResponse.result == nil)
        #expect(finalResponse.error?.code == -32_001)
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
        credentialResolver: any AgentStudioIPCCredentialResolving,
        canonicalPaneMembership: (@MainActor @Sendable (UUID, UUID) -> Bool)? = nil
    ) throws -> LiveServerFixture {
        try LiveServerFixture(
            credentialResolver: credentialResolver,
            canonicalPaneMembership: canonicalPaneMembership
        )
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

private final class ReusableCredentialMembershipGate: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIsMember = true

    var isMember: Bool { lock.withLock { storedIsMember } }

    func setMember(_ isMember: Bool) {
        lock.withLock { storedIsMember = isMember }
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
