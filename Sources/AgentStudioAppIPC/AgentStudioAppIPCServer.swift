import AgentStudioIPCTransport
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
    private var activeConnections: [Int32: UnixSocketConnection] = [:]
    private var activeConnectionPrincipals: [Int32: IPCPrincipal] = [:]
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
            let matchingFileDescriptors =
                activeConnectionPrincipals
                .filter { _, principal in principal.isBound(toPaneId: paneId) }
                .map(\.key)
            for fileDescriptor in matchingFileDescriptors {
                activeConnectionPrincipals.removeValue(forKey: fileDescriptor)
            }
            return matchingFileDescriptors.compactMap { fileDescriptor in
                activeConnections.removeValue(forKey: fileDescriptor)
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

        do {
            let credentials = try peerCredentialProvider.credentials(forAcceptedSocket: connection.fileDescriptor)
            try peerCredentialGate.validate(credentials)
        } catch {
            return
        }

        let writer = AgentStudioAppIPCConnectionWriter(connection: connection, maxFrameBytes: maxFrameBytes)
        let socketSubscriber = AgentStudioAppIPCSocketEventSubscriber(writer: writer)
        var decoder = NDJSONFrameDecoder(maxFrameBytes: maxFrameBytes)
        var connectionState = AgentStudioAppIPCConnectionState()

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
                            connectionFileDescriptor: connection.fileDescriptor,
                            connectionState: &connectionState,
                            socketSubscriber: socketSubscriber
                        )
                        try await writer.sendResponse(JSONRPCResponse.success(id: id, result: result))
                    } catch let error as AgentStudioAppIPCRequestError {
                        try await writer.sendError(id: id, code: error.code, message: error.message)
                    } catch {
                        let mappedError = AgentStudioAppIPCRequestError(error)
                        try await writer.sendError(id: id, code: mappedError.code, message: mappedError.message)
                    }
                }
            } catch {
                return
            }
        }
    }

    private func process(
        _ request: JSONRPCRequest,
        connectionFileDescriptor: Int32,
        connectionState: inout AgentStudioAppIPCConnectionState,
        socketSubscriber: any IPCEventSubscriber
    ) async throws -> JSONValue {
        guard serverIsRunning() else {
            throw AgentStudioAppIPCRequestError.unauthenticated
        }

        if connectionState.principal == nil,
            !connectionState.authenticationFailed,
            request.method != "auth.login",
            allowsUnsafeDebugNoAuthentication
        {
            connectionState.principal = IPCPrincipal(
                principalId: UUID(),
                runtimeId: service.configuration.runtimeId,
                accessMode: .unsafeDebug,
                kind: .unsafeDebugClient,
                approvalAuthority: .noApprovalAuthority
            )
            if let principal = connectionState.principal {
                recordPrincipal(principal, forConnectionFileDescriptor: connectionFileDescriptor)
            }
        }

        if !AgentStudioIPCPreAuthMethods.isAllowed(request.method) {
            guard connectionState.principal != nil else {
                throw AgentStudioAppIPCRequestError.unauthenticated
            }
        }

        switch request.method {
        case "system.ping":
            return .object([
                "ok": .bool(true),
                "runtimeId": .string(service.configuration.runtimeId.uuidString),
            ])

        case "auth.login":
            let params = try decodeParams(AuthLoginParams.self, from: request.params)
            let result: AgentStudioIPCLoginResult
            do {
                result = try authenticator.login(
                    subjectToken: AgentStudioIPCSubjectToken(rawValue: params.token),
                    callerSuppliedPaneHint: params.paneHint
                )
            } catch {
                connectionState.principal = nil
                connectionState.authenticationFailed = true
                throw error
            }
            connectionState.principal = result.principal
            connectionState.authenticationFailed = false
            recordPrincipal(result.principal, forConnectionFileDescriptor: connectionFileDescriptor)
            consumeDebugEscrowIfNeeded(for: result.principal)
            return principalResult(result.principal)

        case "auth.status":
            if let principal = connectionState.principal {
                return principalResult(principal)
            }
            return .object(["authenticated": .bool(false)])

        default:
            let principal = try requirePrincipal(connectionState.principal)
            let context = try await authorizationContext(for: request, principal: principal)
            try authorizationService.authorize(
                principal: principal,
                methodName: request.method,
                requestedTarget: context.target,
                activePaneId: nil
            )
            return try await processAuthenticated(
                context.request,
                principal: principal,
                socketSubscriber: socketSubscriber
            )
        }
    }

    private func authorizationContext(for request: JSONRPCRequest, principal: IPCPrincipal) async throws
        -> AuthorizedRequestContext
    {
        if let contribution = methodRegistry.contribution(named: request.method) {
            let tools = AppIPCContributionAuthorizationTools { [self] rawHandle in
                try await canonicalHandle(fromRawHandle: rawHandle)
            }
            let context = try await contribution.authorizationContext(request, principal, tools)
            return AuthorizedRequestContext(request: context.request, target: context.target)
        }

        switch request.method {
        case "system.identify", "system.version", "system.capabilities", "auth.status":
            return AuthorizedRequestContext(request: request, target: principal.boundPaneTarget ?? .app)
        case "terminal.status", "terminal.snapshot", "terminal.send", "terminal.wait", "pane.focus":
            let params = try decodeParams(HandleParams.self, from: request.params)
            let canonicalHandle = try await canonicalHandle(fromRawHandle: params.handle)
            return try AuthorizedRequestContext(
                request: request.replacingHandle(canonicalHandle.rawIPCHandleString),
                target: targetScope(fromCanonicalHandle: canonicalHandle)
            )
        case "pane.split":
            let params = try decodeParams(IPCPaneSplitParams.self, from: request.params)
            let canonicalHandle = try await canonicalHandle(fromRawHandle: params.handle)
            let canonicalParams = IPCPaneSplitParams(
                handle: canonicalHandle.rawIPCHandleString,
                direction: params.direction,
                correlationId: params.correlationId
            )
            return try AuthorizedRequestContext(
                request: request.replacingParams(try JSONRPCCodec.encodeJSONValue(canonicalParams)),
                target: targetScope(fromCanonicalHandle: canonicalHandle)
            )
        case "pane.close":
            let params = try decodeParams(IPCPaneCloseParams.self, from: request.params)
            let canonicalHandle = try await canonicalHandle(fromRawHandle: params.handle)
            let canonicalParams = IPCPaneCloseParams(
                handle: canonicalHandle.rawIPCHandleString, correlationId: params.correlationId)
            return try AuthorizedRequestContext(
                request: request.replacingParams(try JSONRPCCodec.encodeJSONValue(canonicalParams)),
                target: targetScope(fromCanonicalHandle: canonicalHandle)
            )
        case "drawer.addPane":
            let params = try decodeParams(IPCDrawerAddPaneParams.self, from: request.params)
            let canonicalHandle = try await canonicalHandle(fromRawHandle: params.parentPaneHandle)
            let canonicalParams = IPCDrawerAddPaneParams(
                parentPaneHandle: canonicalHandle.rawIPCHandleString,
                correlationId: params.correlationId
            )
            return try AuthorizedRequestContext(
                request: request.replacingParams(try JSONRPCCodec.encodeJSONValue(canonicalParams)),
                target: targetScope(fromCanonicalHandle: canonicalHandle)
            )
        case "drawer.toggle":
            let params = try decodeParams(IPCDrawerToggleParams.self, from: request.params)
            let canonicalHandle = try await canonicalHandle(fromRawHandle: params.parentPaneHandle)
            let canonicalParams = IPCDrawerToggleParams(
                parentPaneHandle: canonicalHandle.rawIPCHandleString,
                correlationId: params.correlationId
            )
            return try AuthorizedRequestContext(
                request: request.replacingParams(try JSONRPCCodec.encodeJSONValue(canonicalParams)),
                target: targetScope(fromCanonicalHandle: canonicalHandle)
            )
        case "permission.request":
            return AuthorizedRequestContext(request: request, target: principal.boundPaneTarget ?? .app)
        case "ui.commandBar.open":
            return AuthorizedRequestContext(request: request, target: .app)
        case "permission.requestStatus", "permission.grantStatus", "permission.pendingApprovals",
            "permission.resolveRequest", "events.subscribe", "events.unsubscribe", "command.list", "command.execute":
            return AuthorizedRequestContext(request: request, target: principal.boundPaneTarget ?? .app)
        default:
            return AuthorizedRequestContext(request: request, target: .app)
        }
    }

    private func canonicalHandle(fromRawHandle rawHandle: String) async throws -> IPCHandle {
        let handle = try IPCHandle.parse(rawHandle)
        switch (handle.kind, handle.reference) {
        case (.pane, .friendlyOrdinal(let ordinal)):
            let panes = try await service.ports.queryPort.listPanes().panes
            guard let pane = panes[safe: ordinal - 1] else {
                throw AppIPCQueryError(reason: .targetNotFound)
            }
            return IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id))
        case (.pane, .canonicalUUID), (.workspace, .canonicalUUID):
            return handle
        default:
            throw AgentStudioAppIPCRequestError.invalidParams
        }
    }

    private func targetScope(fromCanonicalHandle handle: IPCHandle) throws -> IPCTargetScope {
        switch (handle.kind, handle.reference) {
        case (.pane, .canonicalUUID(let paneId)):
            return .pane(paneId.uuidString)
        case (.workspace, .canonicalUUID(let workspaceId)):
            return .workspace(workspaceId)
        default:
            throw AgentStudioAppIPCRequestError.invalidParams
        }
    }

    func decodeHandle(from params: JSONValue?) throws -> IPCHandle {
        let params = try decodeParams(HandleParams.self, from: params)
        return try IPCHandle.parse(params.handle)
    }

    func uuidFromPaneHandle(_ rawHandle: String) throws -> UUID {
        let handle = try IPCHandle.parse(rawHandle)
        guard handle.kind == .pane else {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
        switch handle.reference {
        case .canonicalUUID(let paneId):
            return paneId
        case .friendlyOrdinal:
            throw AgentStudioAppIPCRequestError.invalidParams
        }
    }

    private func requirePrincipal(_ principal: IPCPrincipal?) throws -> IPCPrincipal {
        guard let principal else {
            throw AgentStudioAppIPCRequestError.unauthenticated
        }
        return principal
    }

    func decodeParams<T: Decodable>(_ type: T.Type, from params: JSONValue?) throws -> T {
        let value = params ?? .object([:])
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
    }

    func encodeResult<T: Encodable>(_ value: T) throws -> JSONValue {
        do {
            return try JSONRPCCodec.encodeJSONValue(value)
        } catch {
            throw AgentStudioAppIPCRequestError.responseEncodingFailed
        }
    }

    private func principalResult(_ principal: IPCPrincipal) -> JSONValue {
        .object([
            "authenticated": .bool(true),
            "principalId": .string(principal.principalId.uuidString),
            "runtimeId": .string(principal.runtimeId.uuidString),
            "accessMode": .string(principal.accessMode.rawValue),
        ])
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
        debugEscrowLock.withLock {
            debugEscrowPrincipalId = nil
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
        grantLedger.grant(
            IPCPermissionScope(privilege: .sidebarStateMutate, target: .app, dataScope: .sidebarState),
            to: principal.principalId
        )
        let token = try principalRegistry.issueSubjectToken(for: principal)
        try AgentStudioIPCFilesystem.writeDebugToken(token, paths: paths)
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
            activeConnections[connection.fileDescriptor] = connection
            return true
        }
    }

    private func unregisterConnection(_ connection: UnixSocketConnection) {
        lifecycleLock.withLock {
            _ = activeConnections.removeValue(forKey: connection.fileDescriptor)
            _ = activeConnectionPrincipals.removeValue(forKey: connection.fileDescriptor)
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

    private func recordPrincipal(_ principal: IPCPrincipal, forConnectionFileDescriptor fileDescriptor: Int32) {
        lifecycleLock.withLock {
            guard activeConnections[fileDescriptor] != nil else { return }
            activeConnectionPrincipals[fileDescriptor] = principal
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

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}

private struct AgentStudioAppIPCConnectionState {
    var principal: IPCPrincipal?
    var authenticationFailed = false
}

private struct AuthorizedRequestContext {
    let request: JSONRPCRequest
    let target: IPCTargetScope
}

extension JSONRPCRequest {
    package func replacingHandle(_ handle: String) throws -> JSONRPCRequest {
        guard case .object(var params) = params else {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
        params["handle"] = .string(handle)
        return JSONRPCRequest(id: id, method: method, params: .object(params))
    }

    package func replacingParams(_ params: JSONValue) -> JSONRPCRequest {
        JSONRPCRequest(id: id, method: method, params: params)
    }
}

extension IPCHandle {
    package var rawIPCHandleString: String {
        switch reference {
        case .friendlyOrdinal(let ordinal):
            "\(kind.rawValue):\(ordinal)"
        case .canonicalUUID(let uuid):
            "\(kind.rawValue):\(uuid.uuidString)"
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

    func sendError(id: JSONRPCIdentifier?, code: Int, message: String) throws {
        try sendResponse(
            JSONRPCResponse.failure(
                id: id,
                error: JSONRPCErrorPayload(code: code, message: message)
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

    static let unauthenticated = Self(code: -32_001, message: "unauthenticated")
    static let unauthorized = Self(code: -32_002, message: "unauthorized")
    static let methodNotFound = Self(code: -32_603, message: "method not found")
    static let invalidParams = Self(code: -32_602, message: "invalid params")
    static let responseEncodingFailed = Self(code: -32_603, message: "response encoding failed")
}

private struct AuthLoginParams: Decodable {
    let token: String
    let paneHint: String?
}

struct HandleParams: Decodable {
    let handle: String
}

struct TerminalSendParams: Decodable {
    let handle: String
    let input: String
    let correlationId: UUID?
}

struct TerminalWaitParams: Decodable {
    let handle: String
    let condition: IPCTerminalWaitCondition
    let timeoutSeconds: Double
    let afterSequence: UInt64?
}

struct RequestIdParams: Decodable {
    let requestId: UUID
}

struct ResolvePermissionParams: Decodable {
    let requestId: UUID
    let decision: ApprovalPolicyDecision
}

struct EventsSubscribeParams: Decodable {
    let eventNames: [IPCEventName]
}

struct SubscriptionIdParams: Decodable {
    let subscriptionId: UUID
}

extension IPCPrincipal {
    fileprivate var boundPaneTarget: IPCTargetScope? {
        switch kind {
        case .spawnedPaneAgent(let boundPaneId, _):
            .pane(boundPaneId)
        case .automationClient, .futureMCPClient, .unsafeDebugClient:
            nil
        }
    }

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
        case let uiPresentationError as AppIPCUIPresentationError:
            self.init(uiPresentationError.reason)
        case let authError as AgentStudioIPCAuthenticationError:
            self.init(authError.reason)
        case let contributionError as AppIPCContributionRequestError:
            self.init(contributionError)
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

    private init(_ error: AppIPCContributionRequestError) {
        switch error {
        case .invalidParams:
            self = .invalidParams
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

    private init(_ reason: AppIPCUIPresentationError.Reason) {
        switch reason {
        case .noActiveWindow:
            self = Self(code: -32_006, message: "no active window")
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
