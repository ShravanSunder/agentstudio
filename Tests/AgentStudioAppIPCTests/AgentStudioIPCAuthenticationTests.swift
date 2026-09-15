import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudioAppIPC

@Suite("AgentStudio IPC authentication")
struct AgentStudioIPCAuthenticationTests {
    @Test("the same active credential authenticates repeatedly with one durable lease identity")
    func sameActiveCredentialAuthenticatesRepeatedly() async throws {
        let runtimeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generationID = UUIDv7.generate()
        let token = AgentStudioIPCSubjectToken(rawValue: "active-pane-token")
        let registry = makeRegistry(
            runtimeID: runtimeID,
            outcomes: [
                token.rawValue: .resolved(
                    paneResolution(
                        paneID: paneID,
                        workspaceID: workspaceID,
                        generationID: generationID,
                        status: .active
                    )
                )
            ]
        )

        let first = try await registry.authenticate(subjectToken: token)
        let second = try await registry.authenticate(subjectToken: token)

        #expect(first.generationID == generationID)
        #expect(second.generationID == generationID)
        #expect(first.principal.principalId != second.principal.principalId)
        #expect(first.authorityDisposition == .current)
        #expect(
            first.principal.kind
                == .spawnedPaneAgent(boundPaneId: paneID.uuidString, boundWorkspaceId: workspaceID)
        )
    }

    @Test("disconnect release revokes only the exact ephemeral principal lease")
    func disconnectReleaseKeepsSiblingLeaseGrant() async throws {
        let runtimeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let token = AgentStudioIPCSubjectToken(rawValue: "reconnect-token")
        let ledger = GrantLedger()
        let registry = makeRegistry(
            runtimeID: runtimeID,
            outcomes: [
                token.rawValue: .resolved(
                    paneResolution(
                        paneID: paneID,
                        workspaceID: workspaceID,
                        generationID: UUIDv7.generate(),
                        status: .active
                    )
                )
            ],
            grantLedger: ledger
        )
        let first = try await registry.authenticate(subjectToken: token)
        let second = try await registry.authenticate(subjectToken: token)
        let firstScope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane(paneID.uuidString),
            dataScope: .terminalInput
        )
        let secondScope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane(paneID.uuidString),
            dataScope: .terminalInput
        )
        ledger.grant(firstScope, to: first.principal.principalId)
        ledger.grant(secondScope, to: second.principal.principalId)

        registry.releaseLease(first)

        #expect(!ledger.contains(firstScope, for: first.principal.principalId))
        #expect(ledger.contains(secondScope, for: second.principal.principalId))
    }

    @Test("login ignores caller hints and returns the full authenticated context")
    func loginReturnsContextWithoutCallerHints() async throws {
        let runtimeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generationID = UUIDv7.generate()
        let token = AgentStudioIPCSubjectToken(rawValue: "login-token")
        let registry = makeRegistry(
            runtimeID: runtimeID,
            outcomes: [
                token.rawValue: .resolved(
                    paneResolution(
                        paneID: paneID,
                        workspaceID: workspaceID,
                        generationID: generationID,
                        status: .active
                    )
                )
            ]
        )

        let login = try await AgentStudioIPCAuthenticator(registry: registry).login(subjectToken: token)

        #expect(login.authenticatedContext.generationID == generationID)
        #expect(
            login.principal.kind
                == .spawnedPaneAgent(
                    boundPaneId: paneID.uuidString,
                    boundWorkspaceId: workspaceID
                ))
    }

    @Test("forged and missing credentials are rejected without a registry fallback")
    func forgedAndMissingCredentialsAreRejected() async {
        let registry = makeRegistry(runtimeID: UUIDv7.generate(), outcomes: [:])

        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await registry.authenticate(
                subjectToken: AgentStudioIPCSubjectToken(rawValue: "missing-token")
            )
        }
        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await registry.authenticate(
                subjectToken: AgentStudioIPCSubjectToken(rawValue: "forged-token")
            )
        }
    }

    @Test("prepared and revoked credential resolutions cannot authenticate")
    func preparedAndRevokedCredentialsCannotAuthenticate() async {
        let runtimeID = UUIDv7.generate()
        let preparedToken = AgentStudioIPCSubjectToken(rawValue: "prepared-token")
        let revokedToken = AgentStudioIPCSubjectToken(rawValue: "revoked-token")
        let registry = makeRegistry(
            runtimeID: runtimeID,
            outcomes: [
                preparedToken.rawValue: .rejected(.init(reason: .unauthenticated)),
                revokedToken.rawValue: .resolved(
                    paneResolution(
                        paneID: UUIDv7.generate(),
                        workspaceID: UUIDv7.generate(),
                        generationID: UUIDv7.generate(),
                        status: .revoked
                    )
                ),
            ]
        )

        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await registry.authenticate(subjectToken: preparedToken)
        }
        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await registry.authenticate(subjectToken: revokedToken)
        }
    }

    @Test("diagnostic credentials require the matching runtime and active status")
    func diagnosticCredentialsRequireMatchingRuntime() async throws {
        let runtimeID = UUIDv7.generate()
        let foreignRuntimeID = UUIDv7.generate()
        let activeToken = AgentStudioIPCSubjectToken(rawValue: "diagnostic-active")
        let foreignToken = AgentStudioIPCSubjectToken(rawValue: "diagnostic-foreign")
        let supersededToken = AgentStudioIPCSubjectToken(rawValue: "diagnostic-superseded")
        let registry = makeRegistry(
            runtimeID: runtimeID,
            outcomes: [
                activeToken.rawValue: .resolved(
                    diagnosticResolution(runtimeID: runtimeID, status: .active)
                ),
                foreignToken.rawValue: .resolved(
                    diagnosticResolution(runtimeID: foreignRuntimeID, status: .active)
                ),
                supersededToken.rawValue: .resolved(
                    diagnosticResolution(runtimeID: runtimeID, status: .superseded)
                ),
            ]
        )

        let activeContext = try await registry.authenticate(subjectToken: activeToken)
        #expect(activeContext.principal.accessMode == .unsafeDebug)
        #expect(activeContext.principal.kind == .automationClient)
        #expect(activeContext.authorityDisposition == .current)
        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await registry.authenticate(subjectToken: foreignToken)
        }
        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await registry.authenticate(subjectToken: supersededToken)
        }
    }

    @Test("superseded pane credentials authenticate only as late reports")
    func supersededPaneCredentialIsLateReportOnly() async throws {
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let token = AgentStudioIPCSubjectToken(rawValue: "superseded-pane-token")
        let registry = makeRegistry(
            runtimeID: UUIDv7.generate(),
            outcomes: [
                token.rawValue: .resolved(
                    paneResolution(
                        paneID: paneID,
                        workspaceID: workspaceID,
                        generationID: UUIDv7.generate(),
                        status: .superseded
                    )
                )
            ]
        )

        let context = try await registry.authenticate(subjectToken: token)

        #expect(context.authorityDisposition == .lateReportOnly)
        #expect(context.principal.accessMode == .agentStudioOnly)
        #expect(
            context.principal.kind
                == .spawnedPaneAgent(
                    boundPaneId: paneID.uuidString,
                    boundWorkspaceId: workspaceID
                ))
    }

    @Test("rotation during credential lookup rejects the suspended authentication")
    func rotationDuringLookupRejectsAuthentication() async {
        let runtimeID = UUIDv7.generate()
        let token = AgentStudioIPCSubjectToken(rawValue: "rotating-token")
        let resolver = SuspendedCredentialResolver()
        let registry = AgentStudioIPCPrincipalRegistry(
            runtimeId: runtimeID,
            credentialResolver: resolver
        )
        let authenticationTask = Task {
            try await registry.authenticate(subjectToken: token)
        }
        await resolver.waitUntilLookupStarted()

        registry.rotateTokens()
        await resolver.resume(with: diagnosticResolution(runtimeID: runtimeID, status: .active))

        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await authenticationTask.value
        }
    }

    @Test("pane invalidation during credential lookup rejects the suspended authentication")
    func paneInvalidationDuringLookupRejectsAuthentication() async {
        let paneID = UUIDv7.generate()
        let runtimeID = UUIDv7.generate()
        let resolver = SuspendedCredentialResolver()
        let registry = AgentStudioIPCPrincipalRegistry(
            runtimeId: runtimeID,
            credentialResolver: resolver
        )
        let authenticationTask = Task {
            try await registry.authenticate(
                subjectToken: AgentStudioIPCSubjectToken(rawValue: "invalidated-pane-token")
            )
        }
        await resolver.waitUntilLookupStarted()

        registry.invalidatePrincipals(boundToPaneId: paneID.uuidString)
        await resolver.resume(
            with: paneResolution(
                paneID: paneID,
                workspaceID: UUIDv7.generate(),
                generationID: UUIDv7.generate(),
                status: .active
            ))

        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await authenticationTask.value
        }
    }

    @Test("shutdown during credential lookup rejects the suspended authentication")
    func shutdownDuringLookupRejectsAuthentication() async {
        let runtimeID = UUIDv7.generate()
        let resolver = SuspendedCredentialResolver()
        let registry = AgentStudioIPCPrincipalRegistry(
            runtimeId: runtimeID,
            credentialResolver: resolver
        )
        let authenticationTask = Task {
            try await registry.authenticate(
                subjectToken: AgentStudioIPCSubjectToken(rawValue: "shutdown-token")
            )
        }
        await resolver.waitUntilLookupStarted()

        registry.shutdown()
        await resolver.resume(with: diagnosticResolution(runtimeID: runtimeID, status: .active))

        await #expect(throws: AgentStudioIPCAuthenticationError.self) {
            try await authenticationTask.value
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
    func spawnEnvironmentCarriesRoutingMetadataWithoutBearerTokens() {
        let runtimeID = UUIDv7.generate()
        let environment = AgentStudioIPCSpawnEnvironment(
            socketPath: "/tmp/asipc.sock",
            runtimeId: runtimeID
        )

        #expect(environment.variables["AGENTSTUDIO_IPC_SOCKET"] == "/tmp/asipc.sock")
        #expect(environment.variables["AGENTSTUDIO_IPC_RUNTIME_ID"] == runtimeID.uuidString)
        #expect(!environment.variables.keys.contains("AGENTSTUDIO_IPC_TOKEN"))
        #expect(!environment.variables.values.contains("secret-token"))
    }

    @Test("redacts subject tokens from public strings")
    func redactsSubjectTokensFromPublicStrings() {
        let redactor = AgentStudioIPCRedactor(
            subjectTokens: [AgentStudioIPCSubjectToken(rawValue: "secret-token")]
        )

        #expect(redactor.redact("token=secret-token") == "token=<redacted>")
    }
}

private enum CredentialResolutionOutcome: Sendable {
    case resolved(AgentStudioIPCCredentialResolution)
    case rejected(AgentStudioIPCAuthenticationError)
}

private actor StaticCredentialResolver: AgentStudioIPCCredentialResolving {
    private let outcomes: [String: CredentialResolutionOutcome]

    init(outcomes: [String: CredentialResolutionOutcome]) {
        self.outcomes = outcomes
    }

    func resolveCredential(
        _ credential: AgentStudioIPCSubjectToken,
        serverRuntimeID _: UUID
    ) async throws -> AgentStudioIPCCredentialResolution {
        switch outcomes[credential.rawValue] {
        case .resolved(let resolution):
            return resolution
        case .rejected(let error):
            throw error
        case nil:
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
    }
}

private actor SuspendedCredentialResolver: AgentStudioIPCCredentialResolving {
    private var lookupStarted = false
    private var lookupStartedContinuation: CheckedContinuation<Void, Never>?
    private var resolutionContinuation:
        CheckedContinuation<
            AgentStudioIPCCredentialResolution,
            Error
        >?

    func resolveCredential(
        _: AgentStudioIPCSubjectToken,
        serverRuntimeID _: UUID
    ) async throws -> AgentStudioIPCCredentialResolution {
        try await withCheckedThrowingContinuation { continuation in
            resolutionContinuation = continuation
            lookupStarted = true
            lookupStartedContinuation?.resume()
            lookupStartedContinuation = nil
        }
    }

    func waitUntilLookupStarted() async {
        guard !lookupStarted else { return }
        await withCheckedContinuation { continuation in
            lookupStartedContinuation = continuation
        }
    }

    func resume(with resolution: AgentStudioIPCCredentialResolution) {
        resolutionContinuation?.resume(returning: resolution)
        resolutionContinuation = nil
    }
}

private func makeRegistry(
    runtimeID: UUID,
    outcomes: [String: CredentialResolutionOutcome],
    grantLedger: GrantLedger? = nil
) -> AgentStudioIPCPrincipalRegistry {
    AgentStudioIPCPrincipalRegistry(
        runtimeId: runtimeID,
        credentialResolver: StaticCredentialResolver(outcomes: outcomes),
        grantLedger: grantLedger
    )
}

private func paneResolution(
    paneID: UUID,
    workspaceID: UUID,
    generationID: UUID,
    status: AgentStudioIPCCredentialStatus
) -> AgentStudioIPCCredentialResolution {
    AgentStudioIPCCredentialResolution(
        namespace: .pane(paneID: paneID, workspaceID: workspaceID),
        generationID: generationID,
        status: status
    )
}

private func diagnosticResolution(
    runtimeID: UUID,
    status: AgentStudioIPCCredentialStatus
) -> AgentStudioIPCCredentialResolution {
    AgentStudioIPCCredentialResolution(
        namespace: .diagnostic(runtimeID: runtimeID),
        generationID: UUIDv7.generate(),
        status: status
    )
}
