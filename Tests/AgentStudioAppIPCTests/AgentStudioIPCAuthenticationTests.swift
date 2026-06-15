import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC authentication")
struct AgentStudioIPCAuthenticationTests {
    @Test("authenticates only tokens issued by the in-memory registry")
    func authenticatesOnlyIssuedTokens() throws {
        let runtimeId = UUID()
        let registry = AgentStudioIPCPrincipalRegistry(runtimeId: runtimeId)
        let principal = makePanePrincipal(boundPaneId: "pane-1", runtimeId: runtimeId)

        let token = try registry.issueSubjectToken(for: principal)

        #expect(try registry.authenticate(subjectToken: token) == principal)
        #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try registry.authenticate(subjectToken: AgentStudioIPCSubjectToken(rawValue: "caller-pane-1"))
        }
    }

    @Test("ignores caller-supplied pane hints during login")
    func ignoresCallerSuppliedPaneHintsDuringLogin() throws {
        let runtimeId = UUID()
        let registry = AgentStudioIPCPrincipalRegistry(runtimeId: runtimeId)
        let principal = makePanePrincipal(boundPaneId: "pane-1", runtimeId: runtimeId)
        let token = try registry.issueSubjectToken(for: principal)

        let login = try AgentStudioIPCAuthenticator(registry: registry)
            .login(subjectToken: token, callerSuppliedPaneHint: "pane-2")

        #expect(login.principal.kind == .spawnedPaneAgent(boundPaneId: "pane-1", boundWorkspaceId: nil))
    }

    @Test("rotating tokens invalidates prior subject tokens")
    func rotatingTokensInvalidatesPriorSubjectTokens() throws {
        let runtimeId = UUID()
        let registry = AgentStudioIPCPrincipalRegistry(runtimeId: runtimeId)
        let token = try registry.issueSubjectToken(for: makePanePrincipal(boundPaneId: "pane-1", runtimeId: runtimeId))

        registry.rotateTokens()

        #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try registry.authenticate(subjectToken: token)
        }
    }

    @Test("bound pane close invalidates pane principal tokens")
    func boundPaneCloseInvalidatesPanePrincipalTokens() throws {
        let runtimeId = UUID()
        let registry = AgentStudioIPCPrincipalRegistry(runtimeId: runtimeId)
        let token = try registry.issueSubjectToken(for: makePanePrincipal(boundPaneId: "pane-1", runtimeId: runtimeId))

        registry.invalidatePrincipals(boundToPaneId: "pane-1")

        #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try registry.authenticate(subjectToken: token)
        }
    }

    @Test("rejects principals from a different runtime")
    func rejectsPrincipalsFromDifferentRuntime() throws {
        let registry = AgentStudioIPCPrincipalRegistry(runtimeId: UUID())

        #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try registry.issueSubjectToken(for: makePanePrincipal(boundPaneId: "pane-1", runtimeId: UUID()))
        }
    }

    @Test("pre-auth allowlist admits ping status and login only")
    func preAuthAllowlistAdmitsPingStatusAndLoginOnly() {
        #expect(AgentStudioIPCPreAuthMethods.isAllowed("system.ping"))
        #expect(AgentStudioIPCPreAuthMethods.isAllowed("auth.login"))
        #expect(AgentStudioIPCPreAuthMethods.isAllowed("auth.status"))
        #expect(!AgentStudioIPCPreAuthMethods.isAllowed("terminal.send"))
    }

    @Test("peer gate rejects different local users")
    func peerGateRejectsDifferentLocalUsers() throws {
        let gate = AgentStudioIPCPeerCredentialGate(currentUserIdentifier: 501)

        try gate.validate(PeerCredentials(userIdentifier: 501, groupIdentifier: 20))
        #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try gate.validate(PeerCredentials(userIdentifier: 502, groupIdentifier: 20))
        }
    }

    @Test("spawn environment carries routing metadata without bearer tokens")
    func spawnEnvironmentCarriesRoutingMetadataWithoutBearerTokens() throws {
        let runtimeId = UUID()
        let environment = AgentStudioIPCSpawnEnvironment(
            socketPath: "/tmp/asipc.sock",
            runtimeId: runtimeId
        )

        #expect(environment.variables["AGENTSTUDIO_IPC_SOCKET"] == "/tmp/asipc.sock")
        #expect(environment.variables["AGENTSTUDIO_IPC_RUNTIME_ID"] == runtimeId.uuidString)
        #expect(!environment.variables.keys.contains("AGENTSTUDIO_IPC_TOKEN"))
        #expect(!environment.variables.values.contains("secret-token"))
    }

    @Test("redacts subject tokens from public strings")
    func redactsSubjectTokensFromPublicStrings() {
        let redactor = AgentStudioIPCRedactor(subjectTokens: [AgentStudioIPCSubjectToken(rawValue: "secret-token")])

        #expect(redactor.redact("token=secret-token") == "token=<redacted>")
    }
}

private func makePanePrincipal(boundPaneId: String, runtimeId: UUID = UUID()) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: runtimeId,
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: boundPaneId, boundWorkspaceId: nil),
        approvalAuthority: .noApprovalAuthority
    )
}
