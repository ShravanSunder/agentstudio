import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

public struct AgentStudioIPCSubjectToken: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AgentStudioIPCAuthenticationError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case unauthenticated
        case runtimeMismatch
        case peerUserMismatch
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

package protocol AgentStudioIPCCredentialResolving: Sendable {
    func resolveCredential(
        _ credential: AgentStudioIPCSubjectToken,
        serverRuntimeID: UUID
    ) async throws -> AgentStudioIPCCredentialResolution
}

package enum AgentStudioIPCCredentialNamespace: Equatable, Hashable, Sendable {
    case pane(paneID: UUID, workspaceID: UUID)
    case diagnostic(runtimeID: UUID)
}

package enum AgentStudioIPCCredentialStatus: Equatable, Sendable {
    case active
    case superseded
    case revoked
}

package enum AgentStudioIPCAuthorityDisposition: Equatable, Sendable {
    case current
    case lateReportOnly
}

package struct AgentStudioIPCCredentialResolution: Equatable, Sendable {
    package let namespace: AgentStudioIPCCredentialNamespace
    package let generationID: UUID
    package let status: AgentStudioIPCCredentialStatus

    package init(
        namespace: AgentStudioIPCCredentialNamespace,
        generationID: UUID,
        status: AgentStudioIPCCredentialStatus
    ) {
        self.namespace = namespace
        self.generationID = generationID
        self.status = status
    }
}

package struct AgentStudioIPCAuthenticatedContext: Equatable, Sendable {
    package let principal: IPCPrincipal
    package let generationID: UUID
    package let authorityDisposition: AgentStudioIPCAuthorityDisposition

    package init(
        principal: IPCPrincipal,
        generationID: UUID,
        authorityDisposition: AgentStudioIPCAuthorityDisposition
    ) {
        self.principal = principal
        self.generationID = generationID
        self.authorityDisposition = authorityDisposition
    }
}

public final class AgentStudioIPCPrincipalRegistry: @unchecked Sendable {
    public let runtimeId: UUID

    private struct LeaseKey: Hashable, Sendable {
        let namespace: AgentStudioIPCCredentialNamespace
        let generationID: UUID
    }

    private let lock = NSLock()
    private let credentialResolver: any AgentStudioIPCCredentialResolving
    private let grantLedger: GrantLedger?
    private var lifetimeEpoch: UInt64 = 0
    private var invalidationSequence: UInt64 = 0
    private var paneInvalidationSequences: [UUID: UInt64] = [:]
    private var retiredLeaseSequences: [LeaseKey: UInt64] = [:]
    private var activeLeases: [LeaseKey: Set<UUID>] = [:]
    private var isShutdown = false

    package init(
        runtimeId: UUID,
        credentialResolver: any AgentStudioIPCCredentialResolving,
        grantLedger: GrantLedger? = nil
    ) {
        self.runtimeId = runtimeId
        self.credentialResolver = credentialResolver
        self.grantLedger = grantLedger
    }

    package func authenticate(
        subjectToken: AgentStudioIPCSubjectToken
    ) async throws -> AgentStudioIPCAuthenticatedContext {
        let observation = lock.withLock {
            AuthObservation(
                lifetimeEpoch: lifetimeEpoch,
                invalidationSequence: invalidationSequence,
                isShutdown: isShutdown
            )
        }
        guard !observation.isShutdown else {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }

        let resolution = try await credentialResolver.resolveCredential(
            subjectToken,
            serverRuntimeID: runtimeId
        )
        let context = try makeAuthenticatedContext(from: resolution)
        let leaseKey = LeaseKey(namespace: resolution.namespace, generationID: resolution.generationID)

        let accepted = lock.withLock {
            guard !isShutdown, lifetimeEpoch == observation.lifetimeEpoch else { return false }
            if case .pane(let paneID, _) = resolution.namespace {
                guard paneInvalidationSequences[paneID, default: 0] <= observation.invalidationSequence else {
                    return false
                }
            }
            guard retiredLeaseSequences[leaseKey] == nil else {
                return false
            }
            activeLeases[leaseKey, default: []].insert(context.principal.principalId)
            return true
        }
        guard accepted else {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        return context
    }

    package func rotateTokens() {
        invalidateAllLeases()
    }

    package func shutdown() {
        let principalIDs = lock.withLock {
            isShutdown = true
            lifetimeEpoch &+= 1
            let principalIDs = Set(activeLeases.values.joined())
            activeLeases.removeAll(keepingCapacity: false)
            return principalIDs
        }
        revokeGrants(for: principalIDs)
    }

    package func revokeAllGrants() {
        grantLedger?.revokeAll()
    }

    package func invalidatePrincipals(boundToPaneId paneId: String) {
        guard let paneUUID = UUID(uuidString: paneId) else { return }
        let principalIDs = lock.withLock {
            invalidationSequence &+= 1
            paneInvalidationSequences[paneUUID] = invalidationSequence
            let matchingKeys = activeLeases.keys.filter { key in
                guard case .pane(let boundPaneID, _) = key.namespace else { return false }
                return boundPaneID == paneUUID
            }
            let principalIDs = Set(matchingKeys.flatMap { activeLeases[$0] ?? [] })
            for key in matchingKeys {
                activeLeases.removeValue(forKey: key)
            }
            return principalIDs
        }
        revokeGrants(for: principalIDs)
    }

    package func releaseLease(_ context: AgentStudioIPCAuthenticatedContext) {
        guard let namespace = namespace(for: context.principal) else { return }
        let leaseKey = LeaseKey(namespace: namespace, generationID: context.generationID)
        let released = lock.withLock {
            guard var principalIDs = activeLeases[leaseKey],
                principalIDs.remove(context.principal.principalId) != nil
            else {
                return false
            }
            if principalIDs.isEmpty {
                activeLeases.removeValue(forKey: leaseKey)
            } else {
                activeLeases[leaseKey] = principalIDs
            }
            return true
        }
        if released {
            grantLedger?.revokeAll(for: context.principal.principalId)
        }
    }

    package func retireLease(_ context: AgentStudioIPCAuthenticatedContext) {
        guard let namespace = namespace(for: context.principal) else { return }
        let leaseKey = LeaseKey(namespace: namespace, generationID: context.generationID)
        let principalIDs = lock.withLock {
            invalidationSequence &+= 1
            retiredLeaseSequences[leaseKey] = invalidationSequence
            let principalIDs = activeLeases.removeValue(forKey: leaseKey) ?? []
            return principalIDs
        }
        revokeGrants(for: principalIDs)
    }

    private func invalidateAllLeases() {
        let principalIDs = lock.withLock {
            lifetimeEpoch &+= 1
            let principalIDs = Set(activeLeases.values.joined())
            activeLeases.removeAll(keepingCapacity: false)
            return principalIDs
        }
        revokeGrants(for: principalIDs)
    }

    private func revokeGrants(for principalIDs: Set<UUID>) {
        for principalID in principalIDs {
            grantLedger?.revokeAll(for: principalID)
        }
    }

    private func namespace(for principal: IPCPrincipal) -> AgentStudioIPCCredentialNamespace? {
        switch principal.kind {
        case .spawnedPaneAgent(let paneID, let workspaceID):
            guard let paneUUID = UUID(uuidString: paneID), let workspaceID else {
                return nil
            }
            return .pane(paneID: paneUUID, workspaceID: workspaceID)
        case .automationClient, .futureMCPClient, .unsafeDebugClient:
            return .diagnostic(runtimeID: runtimeId)
        }
    }

    private func makeAuthenticatedContext(
        from resolution: AgentStudioIPCCredentialResolution
    ) throws -> AgentStudioIPCAuthenticatedContext {
        let principal: IPCPrincipal
        let authorityDisposition: AgentStudioIPCAuthorityDisposition
        switch (resolution.namespace, resolution.status) {
        case (.pane(let paneID, let workspaceID), .active):
            principal = IPCPrincipal(
                principalId: UUIDv7.generate(),
                runtimeId: runtimeId,
                accessMode: .agentStudioOnly,
                kind: .spawnedPaneAgent(
                    boundPaneId: paneID.uuidString,
                    boundWorkspaceId: workspaceID
                ),
                approvalAuthority: .noApprovalAuthority
            )
            authorityDisposition = .current
        case (.pane(let paneID, let workspaceID), .superseded):
            principal = IPCPrincipal(
                principalId: UUIDv7.generate(),
                runtimeId: runtimeId,
                accessMode: .agentStudioOnly,
                kind: .spawnedPaneAgent(
                    boundPaneId: paneID.uuidString,
                    boundWorkspaceId: workspaceID
                ),
                approvalAuthority: .noApprovalAuthority
            )
            authorityDisposition = .lateReportOnly
        case (.diagnostic(let credentialRuntimeID), .active):
            guard credentialRuntimeID == runtimeId else {
                throw AgentStudioIPCAuthenticationError(reason: .runtimeMismatch)
            }
            principal = IPCPrincipal(
                principalId: UUIDv7.generate(),
                runtimeId: runtimeId,
                accessMode: .unsafeDebug,
                kind: .automationClient,
                approvalAuthority: .noApprovalAuthority
            )
            authorityDisposition = .current
        default:
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        return AgentStudioIPCAuthenticatedContext(
            principal: principal,
            generationID: resolution.generationID,
            authorityDisposition: authorityDisposition
        )
    }

    private struct AuthObservation: Sendable {
        let lifetimeEpoch: UInt64
        let invalidationSequence: UInt64
        let isShutdown: Bool
    }
}

package struct AgentStudioIPCLoginResult: Equatable, Sendable {
    package let authenticatedContext: AgentStudioIPCAuthenticatedContext
    package var principal: IPCPrincipal { authenticatedContext.principal }

    package init(authenticatedContext: AgentStudioIPCAuthenticatedContext) {
        self.authenticatedContext = authenticatedContext
    }
}

public struct AgentStudioIPCAuthenticator: Sendable {
    private let registry: AgentStudioIPCPrincipalRegistry

    public init(registry: AgentStudioIPCPrincipalRegistry) {
        self.registry = registry
    }

    package func login(
        subjectToken: AgentStudioIPCSubjectToken
    ) async throws -> AgentStudioIPCLoginResult {
        let authenticatedContext = try await registry.authenticate(subjectToken: subjectToken)
        return AgentStudioIPCLoginResult(authenticatedContext: authenticatedContext)
    }
}

public enum AgentStudioIPCPreAuthMethods {
    private static let allowedMethods: Set<String> = [
        "auth.login",
        "auth.status",
        "system.ping",
    ]

    public static func isAllowed(_ method: String) -> Bool {
        allowedMethods.contains(method)
    }
}

public struct AgentStudioIPCPeerCredentialGate: Sendable {
    public let currentUserIdentifier: uid_t

    public init(currentUserIdentifier: uid_t) {
        self.currentUserIdentifier = currentUserIdentifier
    }

    public func validate(_ peerCredentials: PeerCredentials) throws {
        guard peerCredentials.userIdentifier == currentUserIdentifier else {
            throw AgentStudioIPCAuthenticationError(reason: .peerUserMismatch)
        }
    }
}

public struct AgentStudioIPCSpawnEnvironment: Equatable, Sendable {
    public let variables: [String: String]

    public init(socketPath: String, runtimeId: UUID) {
        self.variables = [
            "AGENTSTUDIO_IPC_SOCKET": socketPath,
            "AGENTSTUDIO_IPC_RUNTIME_ID": runtimeId.uuidString,
        ]
    }
}

public struct AgentStudioIPCRedactor: Sendable {
    private let subjectTokens: Set<AgentStudioIPCSubjectToken>

    public init(subjectTokens: Set<AgentStudioIPCSubjectToken>) {
        self.subjectTokens = subjectTokens
    }

    public func redact(_ value: String) -> String {
        subjectTokens.reduce(value) { redacted, token in
            redacted.replacingOccurrences(of: token.rawValue, with: "<redacted>")
        }
    }
}
