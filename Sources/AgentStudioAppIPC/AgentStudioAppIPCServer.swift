import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public struct AgentStudioAppIPCServerError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case accessModeOff
        case liveSocketAlreadyExists
        case socketUnlinkFailed
        case socketPermissionFailed
        case invalidParams
        case unauthenticated
    }

    public let reason: Reason
    public let errnoCode: Int32

    public init(reason: Reason, errnoCode: Int32 = 0) {
        self.reason = reason
        self.errnoCode = errnoCode
    }
}

public struct StaticApprovalPolicyStore: ApprovalPolicyStore {
    private let defaultDecision: ApprovalPolicyDecision

    public init(defaultDecision: ApprovalPolicyDecision = .ask) {
        self.defaultDecision = defaultDecision
    }

    public func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        defaultDecision
    }
}

public final class AgentStudioAppIPCServer: @unchecked Sendable {
    public let service: AgentStudioAppIPCService
    public let paths: AgentStudioIPCPaths
    public let channel: AgentStudioIPCChannel
    public let principalRegistry: AgentStudioIPCPrincipalRegistry
    public let grantLedger: GrantLedger
    public let bootstrapFactory: AgentStudioIPCPaneBootstrapFactory

    private let listener: UnixSocketListener
    private let methodRegistry: AppIPCMethodRegistry
    private let authenticator: AgentStudioIPCAuthenticator
    let authorizationService: AuthorizationService
    let permissionBroker: PermissionBroker
    private let peerCredentialProvider: any PeerCredentialProviding
    private let peerCredentialGate: AgentStudioIPCPeerCredentialGate
    private let maxFrameBytes: Int
    private let lifecycleLock = NSLock()
    private let debugEscrowLock = NSLock()
    private var isRunning = false
    private var activeConnections: [ObjectIdentifier: UnixSocketConnection] = [:]
    private var activeConnectionPrincipals: [ObjectIdentifier: IPCPrincipal] = [:]
    private var debugEscrowPrincipalId: UUID?

    public init(
        service: AgentStudioAppIPCService,
        paths: AgentStudioIPCPaths,
        channel: AgentStudioIPCChannel,
        approvalPolicyStore: any ApprovalPolicyStore = StaticApprovalPolicyStore(),
        peerCredentialProvider: any PeerCredentialProviding = DarwinPeerCredentialProvider(),
        currentUserIdentifier: uid_t = getuid(),
        maxFrameBytes: Int = 1_048_576
    ) {
        self.service = service
        self.paths = paths
        self.channel = channel
        self.methodRegistry = service.methodRegistry
        self.grantLedger = GrantLedger()
        self.principalRegistry = AgentStudioIPCPrincipalRegistry(
            runtimeId: service.configuration.runtimeId,
            grantLedger: grantLedger
        )
        self.authenticator = AgentStudioIPCAuthenticator(registry: principalRegistry)
        self.authorizationService = AuthorizationService(
            methodRegistry: methodRegistry,
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        self.permissionBroker = PermissionBroker(
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: approvalPolicyStore,
            humanApprovalPort: service.ports.permissionApprovalPort
        )
        self.listener = UnixSocketListener(endpoint: UnixSocketEndpoint(path: paths.socketURL.path))
        self.peerCredentialProvider = peerCredentialProvider
        self.peerCredentialGate = AgentStudioIPCPeerCredentialGate(currentUserIdentifier: currentUserIdentifier)
        self.maxFrameBytes = maxFrameBytes
        self.bootstrapFactory = AgentStudioIPCPaneBootstrapFactory(
            registry: principalRegistry,
            socketPath: paths.socketURL.path,
            runtimeId: service.configuration.runtimeId
        )
    }

    public func start(
        processIdentifier: Int32 = Int32(ProcessInfo.processInfo.processIdentifier),
        startedAt: Date = Date()
    ) throws {
        guard service.configuration.accessMode != .off else {
            throw AgentStudioAppIPCServerError(reason: .accessModeOff)
        }

        try AgentStudioIPCFilesystem.prepare(paths: paths)
        try resolveExistingSocketBeforeBind()
        try installDebugTokenEscrowIfNeeded()
        setRunning(true)
        do {
            try listener.start { [self] connection in
                guard self.registerConnection(connection) else {
                    connection.close()
                    return
                }
                Task {
                    await self.handleRegisteredConnection(connection)
                }
            }
            try secureSocketFile()
            let metadata = AgentStudioIPCRuntimeMetadata(
                runtimeId: service.configuration.runtimeId,
                processIdentifier: processIdentifier,
                channel: channel,
                socketPath: paths.socketURL.path,
                startedAt: startedAt
            )
            try AgentStudioIPCFilesystem.writeMetadata(metadata, paths: paths)
        } catch {
            stopListenerAndConnections()
            AgentStudioIPCFilesystem.removeDebugToken(paths: paths)
            throw error
        }
    }

    public func stop() {
        stopListenerAndConnections()
        principalRegistry.rotateTokens()
        principalRegistry.revokeAllGrants()
        try? FileManager.default.removeItem(at: paths.metadataURL)
        AgentStudioIPCFilesystem.removeDebugToken(paths: paths)
        debugEscrowLock.withLock {
            debugEscrowPrincipalId = nil
        }
    }

    public func makePaneBootstrap(
        boundPaneId: String,
        boundWorkspaceId: UUID?,
        approvalAuthority: IPCApprovalAuthority = .noApprovalAuthority
    ) throws -> AgentStudioIPCPaneBootstrap {
        try bootstrapFactory.makePaneBootstrap(
            boundPaneId: boundPaneId,
            boundWorkspaceId: boundWorkspaceId,
            approvalAuthority: approvalAuthority
        )
    }

    public func cancelPaneBootstrap(_ bootstrap: AgentStudioIPCPaneBootstrap) {
        bootstrap.cancel(in: principalRegistry)
    }

    public func invalidatePrincipals(boundToPaneId paneId: String) {
        principalRegistry.invalidatePrincipals(boundToPaneId: paneId)
        let connections = lifecycleLock.withLock {
            let matchingConnectionIdentifiers =
                activeConnectionPrincipals
                .filter { _, principal in principal.isBound(toPaneId: paneId) }
                .map(\.key)
            for connectionIdentifier in matchingConnectionIdentifiers {
                activeConnectionPrincipals.removeValue(forKey: connectionIdentifier)
            }
            return matchingConnectionIdentifiers.compactMap { connectionIdentifier in
                activeConnections.removeValue(forKey: connectionIdentifier)
            }
        }
        for connection in connections {
            connection.close()
        }
    }

    private func handleRegisteredConnection(_ connection: UnixSocketConnection) async {
        defer {
            unregisterConnection(connection)
            connection.close()
        }

        let connectionId = UUIDv7.generate()
        await handleConnectionRequests(connection, connectionId: connectionId)
        await service.eventBroker.removeSubscriptions(connectionId: connectionId)
    }

    private func handleConnectionRequests(_ connection: UnixSocketConnection, connectionId: UUID) async {

        do {
            let credentials = try connection.peerCredentials(using: peerCredentialProvider)
            try peerCredentialGate.validate(credentials)
        } catch {
            return
        }

        let writer = AgentStudioAppIPCConnectionWriter(connection: connection, maxFrameBytes: maxFrameBytes)
        let socketSubscriber = AgentStudioAppIPCSocketEventSubscriber(writer: writer)
        var decoder = NDJSONFrameDecoder(maxFrameBytes: maxFrameBytes)
        let connectionState = AgentStudioAppIPCConnectionState()

        while true {
            do {
                let data = try await receiveFrameData(from: connection)
                guard !data.isEmpty else { return }
                let frames = try decoder.append(data)
                for frame in frames {
                    let request: JSONRPCRequest
                    do {
                        request = try JSONRPCCodec.decodeRequest(frame, maxBytes: maxFrameBytes)
                        try IPCEventBroker.validateInboundClientNotification(method: request.method)
                    } catch {
                        try await writer.sendError(
                            id: nil,
                            code: -32_600,
                            message: "invalid request"
                        )
                        continue
                    }

                    guard let id = request.id else {
                        continue
                    }

                    do {
                        let result = try await process(
                            request,
                            connection: connection,
                            connectionId: connectionId,
                            connectionState: connectionState,
                            socketSubscriber: socketSubscriber
                        )
                        try await writer.sendResponse(JSONRPCResponse.success(id: id, result: result))
                    } catch let error as AgentStudioAppIPCRequestError {
                        try await writer.sendError(id: id, code: error.code, message: error.message, data: error.data)
                    } catch {
                        let mappedError = AgentStudioAppIPCRequestError(error)
                        try await writer.sendError(
                            id: id, code: mappedError.code, message: mappedError.message, data: mappedError.data)
                    }
                }
            } catch {
                return
            }
        }
    }

    private func process(
        _ request: JSONRPCRequest,
        connection: UnixSocketConnection,
        connectionId: UUID,
        connectionState: AgentStudioAppIPCConnectionState,
        socketSubscriber: any IPCEventSubscriber
    ) async throws -> JSONValue {
        guard serverIsRunning() else { throw AgentStudioAppIPCRequestError.unauthenticated }
        guard let registration = methodRegistry.registration(named: request.method) else {
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
        if connectionState.principal == nil, !connectionState.authenticationFailed,
            request.method != "auth.login", allowsUnsafeDebugNoAuthentication
        {
            let principal = IPCPrincipal(
                principalId: UUIDv7.generate(), runtimeId: service.configuration.runtimeId,
                accessMode: .unsafeDebug, kind: .unsafeDebugClient, approvalAuthority: .noApprovalAuthority
            )
            connectionState.setPrincipal(principal)
            recordPrincipal(principal, for: connection)
        }
        let context = AppIPCConnectionContext(
            contextId: connectionId, channel: channel, principal: connectionState.principal,
            authenticate: { [self] params in
                do {
                    let principal = try authenticator.login(
                        subjectToken: AgentStudioIPCSubjectToken(rawValue: params.token), callerSuppliedPaneHint: nil
                    ).principal
                    connectionState.setPrincipal(principal)
                    recordPrincipal(principal, for: connection)
                    consumeDebugEscrowIfNeeded(for: principal)
                    return .authenticated(
                        principalId: principal.principalId, runtimeId: principal.runtimeId,
                        accessMode: principal.accessMode)
                } catch {
                    connectionState.rejectAuthentication()
                    throw error
                }
            },
            authenticationStatus: {
                guard let principal = connectionState.principal else { return .unauthenticated }
                return .authenticated(
                    principalId: principal.principalId, runtimeId: principal.runtimeId, accessMode: principal.accessMode
                )
            }, eventSubscriber: socketSubscriber
        )
        let tools = AppIPCTargetResolutionTools { [self] rawHandle in
            try await canonicalHandle(fromRawHandle: rawHandle, principal: context.principal)
        }
        return try await registration.invoke(
            parameters: request.params ?? .object([:]), connectionContext: context, targetResolutionTools: tools,
            authorize: { [self] principal, authorization in
                try authorizationService.authorize(principal: principal, request: authorization)
            }
        )
    }

    private func canonicalHandle(fromRawHandle rawHandle: String, principal: IPCPrincipal?) async throws -> IPCHandle {
        let selector: IPCTargetSelector
        do { selector = try IPCTargetSelector.parse(rawHandle, expectedKind: .pane) } catch {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
        let paneId: UUID
        switch selector {
        case .selfPane:
            guard let principal, case .spawnedPaneAgent(let rawId, _) = principal.kind,
                let boundId = UUID(uuidString: rawId)
            else {
                throw AgentStudioAppIPCRequestError.unauthorized
            }
            paneId = boundId
        case .paneOrdinal(let ordinal):
            let panes = try await service.ports.queryPort.listPanes().panes
            guard panes.indices.contains(ordinal - 1) else { throw AppIPCQueryError(reason: .targetNotFound) }
            paneId = panes[ordinal - 1].id
        case .canonical(let kind, let id):
            guard kind == .pane else { throw AgentStudioAppIPCRequestError.invalidParams }
            paneId = id
        }
        _ = try await service.ports.queryPort.snapshotPane(paneId)
        return IPCHandle(kind: .pane, reference: .canonicalUUID(paneId))
    }

    private func resolveExistingSocketBeforeBind() throws {
        guard FileManager.default.fileExists(atPath: paths.socketURL.path) else {
            return
        }

        do {
            let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: paths.socketURL.path))
            connection.close()
            throw AgentStudioAppIPCServerError(reason: .liveSocketAlreadyExists)
        } catch let error as AgentStudioAppIPCServerError {
            throw error
        } catch {
            #if canImport(Darwin)
                guard unlink(paths.socketURL.path) == 0 else {
                    throw AgentStudioAppIPCServerError(reason: .socketUnlinkFailed, errnoCode: errno)
                }
            #else
                throw AgentStudioAppIPCServerError(reason: .socketUnlinkFailed)
            #endif
        }
    }

    private func secureSocketFile() throws {
        #if canImport(Darwin)
            guard chmod(paths.socketURL.path, 0o600) == 0 else {
                throw AgentStudioAppIPCServerError(reason: .socketPermissionFailed, errnoCode: errno)
            }
        #else
            throw AgentStudioAppIPCServerError(reason: .socketPermissionFailed)
        #endif
    }

    private func setRunning(_ running: Bool) {
        lifecycleLock.withLock {
            isRunning = running
        }
    }

    private func serverIsRunning() -> Bool {
        lifecycleLock.withLock {
            isRunning
        }
    }

    private var allowsUnsafeDebugNoAuthentication: Bool {
        service.configuration.accessMode == .unsafeDebug && channel == .debug
    }

    private var allowsDebugTokenEscrow: Bool {
        service.configuration.debugTokenEscrowEnabled && channel == .debug
    }

    private func installDebugTokenEscrowIfNeeded() throws {
        AgentStudioIPCFilesystem.removeDebugToken(paths: paths)
        let stalePrincipalId = debugEscrowLock.withLock {
            let stalePrincipalId = debugEscrowPrincipalId
            debugEscrowPrincipalId = nil
            return stalePrincipalId
        }
        if let stalePrincipalId {
            grantLedger.revokeAll(for: stalePrincipalId)
        }

        guard allowsDebugTokenEscrow else {
            return
        }

        let principal = IPCPrincipal(
            principalId: UUID(),
            runtimeId: service.configuration.runtimeId,
            accessMode: .unsafeDebug,
            kind: .automationClient,
            approvalAuthority: .noApprovalAuthority
        )
        for scope in service.configuration.debugTokenEscrowPermissionScopes {
            grantLedger.grant(scope, to: principal.principalId)
        }
        let token = try principalRegistry.issueSubjectToken(for: principal)
        do {
            try AgentStudioIPCFilesystem.writeDebugToken(token, paths: paths)
        } catch {
            principalRegistry.revokeSubjectToken(token)
            throw error
        }
        debugEscrowLock.withLock {
            debugEscrowPrincipalId = principal.principalId
        }
    }

    private func consumeDebugEscrowIfNeeded(for principal: IPCPrincipal) {
        let shouldRemove = debugEscrowLock.withLock {
            guard debugEscrowPrincipalId == principal.principalId else {
                return false
            }
            debugEscrowPrincipalId = nil
            return true
        }
        if shouldRemove {
            AgentStudioIPCFilesystem.removeDebugToken(paths: paths)
        }
    }

    private func registerConnection(_ connection: UnixSocketConnection) -> Bool {
        lifecycleLock.withLock {
            guard isRunning else {
                return false
            }
            activeConnections[ObjectIdentifier(connection)] = connection
            return true
        }
    }

    private func unregisterConnection(_ connection: UnixSocketConnection) {
        lifecycleLock.withLock {
            let connectionIdentifier = ObjectIdentifier(connection)
            guard activeConnections[connectionIdentifier] === connection else { return }
            _ = activeConnections.removeValue(forKey: connectionIdentifier)
            _ = activeConnectionPrincipals.removeValue(forKey: connectionIdentifier)
        }
    }

    private func receiveFrameData(from connection: UnixSocketConnection) async throws -> Data {
        let readLimit = min(maxFrameBytes, 16_384)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try connection.receive(maxBytes: readLimit))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func recordPrincipal(_ principal: IPCPrincipal, for connection: UnixSocketConnection) {
        lifecycleLock.withLock {
            let connectionIdentifier = ObjectIdentifier(connection)
            guard activeConnections[connectionIdentifier] === connection else { return }
            activeConnectionPrincipals[connectionIdentifier] = principal
        }
    }

    private func stopListenerAndConnections() {
        let connections = lifecycleLock.withLock {
            isRunning = false
            let connections = Array(activeConnections.values)
            activeConnections.removeAll(keepingCapacity: false)
            activeConnectionPrincipals.removeAll(keepingCapacity: false)
            return connections
        }
        listener.stop()
        for connection in connections {
            connection.close()
        }
    }
}

private final class AgentStudioAppIPCConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPrincipal: IPCPrincipal?
    private var storedAuthenticationFailed = false

    var principal: IPCPrincipal? { lock.withLock { storedPrincipal } }
    var authenticationFailed: Bool { lock.withLock { storedAuthenticationFailed } }

    func setPrincipal(_ principal: IPCPrincipal) {
        lock.withLock {
            storedPrincipal = principal
            storedAuthenticationFailed = false
        }
    }

    func rejectAuthentication() {
        lock.withLock {
            storedPrincipal = nil
            storedAuthenticationFailed = true
        }
    }
}

private actor AgentStudioAppIPCConnectionWriter {
    private let connection: UnixSocketConnection
    private let maxFrameBytes: Int

    init(connection: UnixSocketConnection, maxFrameBytes: Int) {
        self.connection = connection
        self.maxFrameBytes = maxFrameBytes
    }

    func sendResponse(_ response: JSONRPCResponse) throws {
        try sendFrame(JSONRPCCodec.encodeResponse(response))
    }

    func sendError(id: JSONRPCIdentifier?, code: Int, message: String, data: JSONValue? = nil) throws {
        try sendResponse(
            JSONRPCResponse.failure(
                id: id,
                error: JSONRPCErrorPayload(code: code, message: message, data: data)
            ))
    }

    func sendFrame(_ frame: String) throws {
        try connection.send(try NDJSONFrameEncoder.encode(frame, maxFrameBytes: maxFrameBytes))
    }
}

private actor AgentStudioAppIPCSocketEventSubscriber: IPCEventSubscriber {
    private let writer: AgentStudioAppIPCConnectionWriter

    init(writer: AgentStudioAppIPCConnectionWriter) {
        self.writer = writer
    }

    func deliver(_ frame: String) async throws -> IPCEventDeliveryResult {
        try await writer.sendFrame(frame)
        return .delivered
    }
}

struct AgentStudioAppIPCRequestError: Error, Equatable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    static let unauthenticated = Self(code: -32_001, message: "unauthenticated")
    static let unauthorized = Self(code: -32_002, message: "unauthorized")
    static let methodNotFound = Self(code: -32_603, message: "method not found")
    static let invalidParams = Self(code: -32_602, message: "invalid params")
    static let responseEncodingFailed = Self(code: -32_603, message: "response encoding failed")
}

extension IPCPrincipal {
    fileprivate func isBound(toPaneId paneId: String) -> Bool {
        switch kind {
        case .spawnedPaneAgent(let boundPaneId, _):
            boundPaneId == paneId
        case .automationClient, .futureMCPClient, .unsafeDebugClient:
            false
        }
    }
}

extension AgentStudioAppIPCRequestError {
    fileprivate init(_ error: Error) {
        switch error {
        case let authorizationError as AuthorizationError:
            self.init(authorizationError.reason)
        case let queryError as AppIPCQueryError:
            self.init(queryError.reason)
        case let layoutError as AppIPCLayoutError:
            self.init(layoutError.reason)
        case let runtimeError as AppIPCRuntimeError:
            self.init(runtimeError.reason)
        case let commandError as AppIPCCommandError:
            self.init(commandError.reason)
        case let bridgeError as AppIPCBridgeError:
            self.init(bridgeError.reason)
        case let uiPresentationError as AppIPCUIPresentationError:
            self.init(uiPresentationError.reason)
        case let authError as AgentStudioIPCAuthenticationError:
            self.init(authError.reason)
        case let registrationError as AppIPCTypedMethodRegistrationError:
            switch registrationError {
            case .authenticationRequired: self = .unauthenticated
            case .methodNotExposed: self = .methodNotFound
            default: self = .invalidParams
            }
        case let schemaError as IPCSchemaValidationError:
            self.init(
                code: -32_602, message: "invalid params",
                data: .object([
                    "fieldPath": .string(schemaError.fieldPath),
                    "reason": .string(schemaError.reason.rawValue),
                    "expected": .string(schemaError.expected),
                ]))
        case is IPCTargetSelectorError:
            self = .invalidParams
        case is PermissionBrokerError, is IPCEventBrokerError:
            self = .unauthorized
        case is IPCHandleError:
            self = Self(code: -32_004, message: "target not found")
        default:
            self = Self(code: -32_603, message: "internal error")
        }
    }

    private init(_ reason: AuthorizationError.Reason) {
        switch reason {
        case .methodNotFound:
            self = .methodNotFound
        case .unauthorized, .noBoundPane:
            self = .unauthorized
        }
    }

    private init(_ reason: AppIPCQueryError.Reason) {
        switch reason {
        case .noActiveWindow:
            self = Self(code: -32_006, message: "no active window")
        case .targetNotFound:
            self = Self(code: -32_004, message: "target not found")
        }
    }

    private init(_ reason: AppIPCLayoutError.Reason) {
        switch reason {
        case .noActiveWindow:
            self = Self(code: -32_006, message: "no active window")
        case .targetNotFound:
            self = Self(code: -32_004, message: "target not found")
        case .validationRejected:
            self = Self(code: -32_007, message: "validation rejected")
        }
    }

    private init(_ reason: AppIPCRuntimeError.Reason) {
        switch reason {
        case .targetNotFound:
            self = Self(code: -32_004, message: "target not found")
        case .noRuntime, .runtimeNotReady:
            self = Self(code: -32_005, message: "runtime not ready")
        case .unsupportedCommand:
            self = Self(code: -32_003, message: "unsupported capability")
        case .backendUnavailable:
            self = Self(code: -32_005, message: "backend unavailable")
        case .validationRejected:
            self = Self(code: -32_007, message: "validation rejected")
        case .timeout:
            self = Self(code: -32_009, message: "timeout")
        case .replayGap:
            self = Self(code: -32_010, message: "replay gap")
        }
    }

    private init(_ reason: AppIPCCommandError.Reason) {
        switch reason {
        case .noActiveWindow:
            self = Self(code: -32_006, message: "no active window")
        case .targetNotFound:
            self = Self(code: -32_004, message: "target not found")
        case .unsupportedCommand:
            self = Self(code: -32_003, message: "unsupported capability")
        case .requiresPresentation:
            self = Self(code: -32_003, message: "requires presentation")
        case .requiresTarget:
            self = Self(code: -32_004, message: "target required")
        case .requiresParameters:
            self = Self(code: -32_007, message: "parameters required")
        case .validationRejected:
            self = Self(code: -32_007, message: "validation rejected")
        case .stateUnavailable:
            self = Self(code: -32_005, message: "state unavailable")
        }
    }

    private init(_ reason: AppIPCBridgeError.Reason) {
        switch reason {
        case .noActiveWindow:
            self = Self(code: -32_006, message: "no active window")
        case .targetNotFound:
            self = Self(code: -32_004, message: "target not found")
        case .unsupportedTarget:
            self = Self(code: -32_003, message: "unsupported target")
        case .packageUnavailable:
            self = Self(code: -32_005, message: "package unavailable")
        case .itemNotFound:
            self = Self(code: -32_004, message: "item not found")
        case .contentUnavailable:
            self = Self(code: -32_005, message: "content unavailable")
        case .payloadTooLarge:
            self = Self(code: -32_008, message: "payload too large")
        case .validationRejected:
            self = Self(code: -32_007, message: "validation rejected")
        }
    }

    private init(_ reason: AppIPCUIPresentationError.Reason) {
        switch reason {
        case .noActiveWindow:
            self = Self(code: -32_006, message: "no active window")
        case .targetNotFound:
            self = Self(code: -32_004, message: "target not found")
        case .validationRejected:
            self = Self(code: -32_007, message: "validation rejected")
        }
    }

    private init(_ reason: AgentStudioIPCAuthenticationError.Reason) {
        switch reason {
        case .unauthenticated, .runtimeMismatch, .peerUserMismatch:
            self = .unauthenticated
        }
    }
}
