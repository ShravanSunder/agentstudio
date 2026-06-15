import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

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

public protocol AgentStudioIPCSubjectTokenGenerating: Sendable {
    func makeSubjectToken() -> AgentStudioIPCSubjectToken
}

public struct AgentStudioIPCSecureSubjectTokenGenerator: AgentStudioIPCSubjectTokenGenerating {
    public init() {}

    public func makeSubjectToken() -> AgentStudioIPCSubjectToken {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        let rawValue = bytes.map { String(format: "%02x", $0) }.joined()
        return AgentStudioIPCSubjectToken(rawValue: rawValue)
    }
}

public final class AgentStudioIPCPrincipalRegistry: @unchecked Sendable {
    public let runtimeId: UUID

    private let lock = NSLock()
    private let tokenGenerator: any AgentStudioIPCSubjectTokenGenerating
    private let grantLedger: GrantLedger?
    private var principalsByToken: [AgentStudioIPCSubjectToken: IPCPrincipal] = [:]
    private var activePrincipalsById: [UUID: IPCPrincipal] = [:]

    public init(
        runtimeId: UUID,
        tokenGenerator: any AgentStudioIPCSubjectTokenGenerating = AgentStudioIPCSecureSubjectTokenGenerator(),
        grantLedger: GrantLedger? = nil
    ) {
        self.runtimeId = runtimeId
        self.tokenGenerator = tokenGenerator
        self.grantLedger = grantLedger
    }

    public func issueSubjectToken(for principal: IPCPrincipal) throws -> AgentStudioIPCSubjectToken {
        guard principal.runtimeId == runtimeId else {
            throw AgentStudioIPCAuthenticationError(reason: .runtimeMismatch)
        }

        let token = tokenGenerator.makeSubjectToken()
        lock.withLock {
            principalsByToken[token] = principal
        }
        return token
    }

    public func authenticate(subjectToken: AgentStudioIPCSubjectToken) throws -> IPCPrincipal {
        try lock.withLock {
            guard let principal = principalsByToken[subjectToken] else {
                throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
            }
            guard principal.runtimeId == runtimeId else {
                throw AgentStudioIPCAuthenticationError(reason: .runtimeMismatch)
            }
            principalsByToken.removeValue(forKey: subjectToken)
            activePrincipalsById[principal.principalId] = principal
            return principal
        }
    }

    public func rotateTokens() {
        let revokedPrincipalIds = lock.withLock {
            let principalIds = Set(principalsByToken.values.map(\.principalId))
                .union(activePrincipalsById.keys)
            principalsByToken.removeAll()
            activePrincipalsById.removeAll()
            return principalIds
        }
        for principalId in revokedPrincipalIds {
            grantLedger?.revokeAll(for: principalId)
        }
    }

    public func revokeAllGrants() {
        grantLedger?.revokeAll()
    }

    public func invalidatePrincipals(boundToPaneId paneId: String) {
        let revokedPrincipalIds = lock.withLock {
            let tokenPrincipalIds = Set(
                principalsByToken.values
                    .filter { $0.boundPaneId == paneId }
                    .map(\.principalId)
            )
            let activePrincipalIds = Set(
                activePrincipalsById.values
                    .filter { $0.boundPaneId == paneId }
                    .map(\.principalId)
            )
            principalsByToken = principalsByToken.filter { _, principal in
                principal.boundPaneId != paneId
            }
            activePrincipalsById = activePrincipalsById.filter { _, principal in
                principal.boundPaneId != paneId
            }
            return tokenPrincipalIds.union(activePrincipalIds)
        }
        for principalId in revokedPrincipalIds {
            grantLedger?.revokeAll(for: principalId)
        }
    }
}

public struct AgentStudioIPCLoginResult: Equatable, Sendable {
    public let principal: IPCPrincipal

    public init(principal: IPCPrincipal) {
        self.principal = principal
    }
}

public struct AgentStudioIPCAuthenticator: Sendable {
    private let registry: AgentStudioIPCPrincipalRegistry

    public init(registry: AgentStudioIPCPrincipalRegistry) {
        self.registry = registry
    }

    public func login(
        subjectToken: AgentStudioIPCSubjectToken,
        callerSuppliedPaneHint _: String?
    ) throws -> AgentStudioIPCLoginResult {
        AgentStudioIPCLoginResult(principal: try registry.authenticate(subjectToken: subjectToken))
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

    public init(socketPath: String, runtimeId: UUID, bootstrapFileDescriptor: Int32? = nil) {
        var variables = [
            "AGENTSTUDIO_IPC_SOCKET": socketPath,
            "AGENTSTUDIO_IPC_RUNTIME_ID": runtimeId.uuidString,
        ]
        if let bootstrapFileDescriptor {
            variables["AGENTSTUDIO_IPC_BOOTSTRAP_FD"] = String(bootstrapFileDescriptor)
        }
        self.variables = variables
    }
}

public struct AgentStudioIPCPaneBootstrapDescriptor: Equatable, Sendable {
    public let environment: AgentStudioIPCSpawnEnvironment
    public let tokenReadFileDescriptor: Int32

    public init(environment: AgentStudioIPCSpawnEnvironment, tokenReadFileDescriptor: Int32) {
        self.environment = environment
        self.tokenReadFileDescriptor = tokenReadFileDescriptor
    }
}

public struct AgentStudioIPCPaneBootstrapError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case unsupportedPlatform
        case pipeCreationFailed
        case pipeConfigurationFailed
        case tokenWriteFailed
    }

    public let reason: Reason
    public let errnoCode: Int32

    public init(reason: Reason, errnoCode: Int32 = 0) {
        self.reason = reason
        self.errnoCode = errnoCode
    }
}

public final class AgentStudioIPCPaneBootstrap: @unchecked Sendable {
    public let descriptor: AgentStudioIPCPaneBootstrapDescriptor

    private let readFileDescriptor: Int32
    private let writeFileDescriptor: Int32
    private let lock = NSLock()
    private var isReadClosed = false
    private var isWriteClosed = false

    public init(descriptor: AgentStudioIPCPaneBootstrapDescriptor, writeFileDescriptor: Int32) {
        self.descriptor = descriptor
        self.readFileDescriptor = descriptor.tokenReadFileDescriptor
        self.writeFileDescriptor = writeFileDescriptor
    }

    deinit {
        close()
        closeTokenReadFileDescriptor()
    }

    public func writeTokenAndClose(_ token: AgentStudioIPCSubjectToken) throws {
        #if canImport(Darwin)
            let bytes = Array(token.rawValue.utf8) + [UInt8(ascii: "\n")]
            try bytes.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var writtenByteCount = 0
                while writtenByteCount < rawBuffer.count {
                    let result = Darwin.write(
                        writeFileDescriptor,
                        baseAddress.advanced(by: writtenByteCount),
                        rawBuffer.count - writtenByteCount
                    )
                    if result < 0 {
                        if errno == EINTR {
                            continue
                        }
                        throw AgentStudioIPCPaneBootstrapError(reason: .tokenWriteFailed, errnoCode: errno)
                    }
                    writtenByteCount += result
                }
            }
            close()
        #else
            throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
        #endif
    }

    public func close() {
        #if canImport(Darwin)
            lock.withLock {
                guard !isWriteClosed else { return }
                _ = Darwin.close(writeFileDescriptor)
                isWriteClosed = true
            }
        #endif
    }

    public func closeTokenReadFileDescriptor() {
        #if canImport(Darwin)
            lock.withLock {
                guard !isReadClosed else { return }
                _ = Darwin.close(readFileDescriptor)
                isReadClosed = true
            }
        #endif
    }
}

public struct AgentStudioIPCPaneBootstrapFactory: Sendable {
    private let registry: AgentStudioIPCPrincipalRegistry
    private let socketPath: String
    private let runtimeId: UUID

    public init(registry: AgentStudioIPCPrincipalRegistry, socketPath: String, runtimeId: UUID) {
        self.registry = registry
        self.socketPath = socketPath
        self.runtimeId = runtimeId
    }

    public func makePaneBootstrap(
        boundPaneId: String,
        boundWorkspaceId: UUID?,
        approvalAuthority: IPCApprovalAuthority = .noApprovalAuthority
    ) throws -> AgentStudioIPCPaneBootstrap {
        #if canImport(Darwin)
            var fileDescriptors: [Int32] = [0, 0]
            guard pipe(&fileDescriptors) == 0 else {
                throw AgentStudioIPCPaneBootstrapError(reason: .pipeCreationFailed, errnoCode: errno)
            }

            let readFileDescriptor = fileDescriptors[0]
            let writeFileDescriptor = fileDescriptors[1]
            do {
                try configureCloseOnExec(fileDescriptor: readFileDescriptor)
                try configureCloseOnExec(fileDescriptor: writeFileDescriptor)
                let principal = IPCPrincipal(
                    principalId: UUID(),
                    runtimeId: runtimeId,
                    accessMode: .agentStudioOnly,
                    kind: .spawnedPaneAgent(boundPaneId: boundPaneId, boundWorkspaceId: boundWorkspaceId),
                    approvalAuthority: approvalAuthority
                )
                let token = try registry.issueSubjectToken(for: principal)
                let bootstrap = AgentStudioIPCPaneBootstrap(
                    descriptor: AgentStudioIPCPaneBootstrapDescriptor(
                        environment: AgentStudioIPCSpawnEnvironment(
                            socketPath: socketPath,
                            runtimeId: runtimeId,
                            bootstrapFileDescriptor: readFileDescriptor
                        ),
                        tokenReadFileDescriptor: readFileDescriptor
                    ),
                    writeFileDescriptor: writeFileDescriptor
                )
                try bootstrap.writeTokenAndClose(token)
                return bootstrap
            } catch {
                _ = Darwin.close(readFileDescriptor)
                _ = Darwin.close(writeFileDescriptor)
                throw error
            }
        #else
            throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
        #endif
    }

    private func configureCloseOnExec(fileDescriptor: Int32) throws {
        #if canImport(Darwin)
            let flags = fcntl(fileDescriptor, F_GETFD)
            guard flags >= 0 else {
                throw AgentStudioIPCPaneBootstrapError(reason: .pipeConfigurationFailed, errnoCode: errno)
            }
            guard fcntl(fileDescriptor, F_SETFD, flags | FD_CLOEXEC) == 0 else {
                throw AgentStudioIPCPaneBootstrapError(reason: .pipeConfigurationFailed, errnoCode: errno)
            }
        #else
            throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
        #endif
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

extension IPCPrincipal {
    fileprivate var boundPaneId: String? {
        switch kind {
        case .spawnedPaneAgent(let boundPaneId, _):
            boundPaneId
        case .automationClient, .futureMCPClient, .unsafeDebugClient:
            nil
        }
    }
}
