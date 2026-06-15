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
    private let authorizationService: AuthorizationService
    private let permissionBroker: PermissionBroker
    private let peerCredentialProvider: any PeerCredentialProviding
    private let peerCredentialGate: AgentStudioIPCPeerCredentialGate
    private let maxFrameBytes: Int
    private let lifecycleLock = NSLock()
    private let debugEscrowLock = NSLock()
    private var isRunning = false
    private var activeConnections: [Int32: UnixSocketConnection] = [:]
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
        self.methodRegistry = AppIPCMethodRegistry(definitions: service.configuration.methodDefinitions)
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
                Task {
                    await self.handle(connection)
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

    private func handle(_ connection: UnixSocketConnection) async {
        guard registerConnection(connection) else {
            connection.close()
            return
        }
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
                let data = try connection.receive(maxBytes: min(maxFrameBytes, 16_384))
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
        connectionState: inout AgentStudioAppIPCConnectionState,
        socketSubscriber: any IPCEventSubscriber
    ) async throws -> JSONValue {
        guard serverIsRunning() else {
            throw AgentStudioAppIPCRequestError.unauthenticated
        }

        if connectionState.principal == nil, allowsUnsafeDebugNoAuthentication {
            connectionState.principal = IPCPrincipal(
                principalId: UUID(),
                runtimeId: service.configuration.runtimeId,
                accessMode: .unsafeDebug,
                kind: .unsafeDebugClient,
                approvalAuthority: .noApprovalAuthority
            )
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
            let result = try authenticator.login(
                subjectToken: AgentStudioIPCSubjectToken(rawValue: params.token),
                callerSuppliedPaneHint: params.paneHint
            )
            connectionState.principal = result.principal
            consumeDebugEscrowIfNeeded(for: result.principal)
            return principalResult(result.principal)

        case "auth.status":
            if let principal = connectionState.principal {
                return principalResult(principal)
            }
            return .object(["authenticated": .bool(false)])

        default:
            let principal = try requirePrincipal(connectionState.principal)
            let target = try await authorizationTarget(for: request, principal: principal)
            try authorizationService.authorize(
                principal: principal,
                methodName: request.method,
                requestedTarget: target,
                activePaneId: nil
            )
            return try await processAuthenticated(
                request,
                principal: principal,
                socketSubscriber: socketSubscriber
            )
        }
    }

    private func processAuthenticated(
        _ request: JSONRPCRequest,
        principal: IPCPrincipal,
        socketSubscriber: any IPCEventSubscriber
    ) async throws -> JSONValue {
        switch request.method {
        case "system.identify":
            return try await encodeResult(service.ports.queryPort.systemIdentify())
        case "system.version":
            return try await encodeResult(service.ports.queryPort.systemVersion())
        case "system.capabilities":
            return try await encodeResult(service.ports.queryPort.systemCapabilities())
        case "window.list":
            return try await encodeResult(service.ports.queryPort.listWindows())
        case "window.current":
            return try await encodeResult(service.ports.queryPort.currentWindow())
        case "workspace.list":
            return try await encodeResult(service.ports.queryPort.listWorkspaces())
        case "workspace.current":
            return try await encodeResult(service.ports.queryPort.currentWorkspace())
        case "pane.list":
            return try await encodeResult(service.ports.queryPort.listPanes())
        case "pane.current":
            return try await encodeResult(service.ports.queryPort.currentPane())
        case "pane.snapshot":
            let params = try decodeParams(HandleParams.self, from: request.params)
            let paneId = try uuidFromPaneHandle(params.handle)
            return try await encodeResult(service.ports.queryPort.snapshotPane(paneId))
        case "pane.focus":
            let params = try decodeParams(HandleParams.self, from: request.params)
            let handle = try IPCHandle.parse(params.handle)
            return try await encodeResult(service.ports.layoutPort.focusPane(handle))
        case "terminal.status":
            let handle = try decodeHandle(from: request.params)
            return try await encodeResult(service.ports.runtimePort.terminalStatus(handle))
        case "terminal.snapshot":
            let handle = try decodeHandle(from: request.params)
            return try await encodeResult(service.ports.runtimePort.terminalSnapshot(handle))
        case "terminal.send":
            let params = try decodeParams(TerminalSendParams.self, from: request.params)
            let handle = try IPCHandle.parse(params.handle)
            let result = try await service.ports.runtimePort.sendTerminalInput(
                to: handle,
                input: params.input,
                correlationId: params.correlationId
            )
            return try encodeResult(result)
        case "terminal.wait":
            let params = try decodeParams(TerminalWaitParams.self, from: request.params)
            let handle = try IPCHandle.parse(params.handle)
            let timeout = Duration.milliseconds(Int64((params.timeoutSeconds * 1000).rounded(.up)))
            let result = try await service.ports.runtimePort.waitForTerminal(
                handle,
                condition: params.condition,
                timeout: timeout
            )
            return try encodeResult(result)
        case "command.list":
            let result = try await MainActor.run {
                try service.ports.commandPort.listCommands()
            }
            return try encodeResult(result)
        case "command.execute":
            let params = try decodeParams(IPCCommandExecuteParams.self, from: request.params)
            let result = try await MainActor.run {
                try service.ports.commandPort.executeCommand(params)
            }
            return try encodeResult(result)
        case "permission.request":
            let params = try decodeParams(IPCPermissionRequestParams.self, from: request.params)
            let result = try permissionBroker.requestPermission(params, requester: principal)
            return try encodeResult(result)
        case "permission.requestStatus":
            let params = try decodeParams(RequestIdParams.self, from: request.params)
            return try encodeResult(permissionBroker.requestStatus(params.requestId, requester: principal))
        case "permission.grantStatus":
            let params = try decodeParams(RequestIdParams.self, from: request.params)
            return try encodeResult(permissionBroker.grantStatus(params.requestId, requester: principal))
        case "permission.pendingApprovals":
            let results = try permissionBroker.pendingApprovals(for: principal).map(\.result)
            return try JSONRPCCodec.encodeJSONValue(["requests": results])
        case "permission.resolveRequest":
            let params = try decodeParams(ResolvePermissionParams.self, from: request.params)
            return try encodeResult(
                permissionBroker.resolveRequest(params.requestId, approver: principal, decision: params.decision))
        case "events.subscribe":
            let params = try decodeParams(EventsSubscribeParams.self, from: request.params)
            let result = try await service.eventBroker.subscribe(
                eventNames: Set(params.eventNames),
                principal: principal,
                subscriber: socketSubscriber
            )
            return try encodeResult(result)
        case "events.unsubscribe":
            let params = try decodeParams(SubscriptionIdParams.self, from: request.params)
            try await service.eventBroker.unsubscribe(params.subscriptionId, principal: principal)
            return .object(["unsubscribed": .bool(true), "subscriptionId": .string(params.subscriptionId.uuidString)])
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func authorizationTarget(for request: JSONRPCRequest, principal: IPCPrincipal) async throws
        -> IPCTargetScope
    {
        switch request.method {
        case "system.identify", "system.version", "system.capabilities", "auth.status":
            return principal.boundPaneTarget ?? .app
        case "terminal.status", "terminal.snapshot", "terminal.send", "terminal.wait", "pane.focus", "pane.snapshot":
            let params = try decodeParams(HandleParams.self, from: request.params)
            return try await targetScope(fromHandle: params.handle)
        case "permission.request":
            return principal.boundPaneTarget ?? .app
        case "permission.requestStatus", "permission.grantStatus", "permission.pendingApprovals",
            "permission.resolveRequest", "events.subscribe", "events.unsubscribe", "command.list", "command.execute":
            return principal.boundPaneTarget ?? .app
        default:
            return .app
        }
    }

    private func targetScope(fromHandle rawHandle: String) async throws -> IPCTargetScope {
        let handle = try IPCHandle.parse(rawHandle)
        switch (handle.kind, handle.reference) {
        case (.pane, .canonicalUUID(let paneId)):
            return .pane(paneId.uuidString)
        case (.pane, .friendlyOrdinal(let ordinal)):
            let panes = try await service.ports.queryPort.listPanes().panes
            guard let pane = panes[safe: ordinal - 1] else {
                throw AppIPCQueryError(reason: .targetNotFound)
            }
            return .pane(pane.id.uuidString)
        case (.workspace, .canonicalUUID(let workspaceId)):
            return .workspace(workspaceId)
        default:
            throw AgentStudioAppIPCRequestError.invalidParams
        }
    }

    private func decodeHandle(from params: JSONValue?) throws -> IPCHandle {
        let params = try decodeParams(HandleParams.self, from: params)
        return try IPCHandle.parse(params.handle)
    }

    private func uuidFromPaneHandle(_ rawHandle: String) throws -> UUID {
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

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: JSONValue?) throws -> T {
        let value = params ?? .object([:])
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
    }

    private func encodeResult<T: Encodable>(_ value: T) throws -> JSONValue {
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
        }
    }

    private func stopListenerAndConnections() {
        let connections = lifecycleLock.withLock {
            isRunning = false
            let connections = Array(activeConnections.values)
            activeConnections.removeAll(keepingCapacity: false)
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

private struct AgentStudioAppIPCRequestError: Error, Equatable, Sendable {
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

private struct HandleParams: Decodable {
    let handle: String
}

private struct TerminalSendParams: Decodable {
    let handle: String
    let input: String
    let correlationId: UUID?
}

private struct TerminalWaitParams: Decodable {
    let handle: String
    let condition: IPCTerminalWaitCondition
    let timeoutSeconds: Double
}

private struct RequestIdParams: Decodable {
    let requestId: UUID
}

private struct ResolvePermissionParams: Decodable {
    let requestId: UUID
    let decision: ApprovalPolicyDecision
}

private struct EventsSubscribeParams: Decodable {
    let eventNames: [IPCEventName]
}

private struct SubscriptionIdParams: Decodable {
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
        case let authError as AgentStudioIPCAuthenticationError:
            self.init(authError.reason)
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
