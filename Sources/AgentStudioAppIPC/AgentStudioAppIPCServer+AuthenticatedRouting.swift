import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

extension AgentStudioAppIPCServer {
    func processAuthenticated(
        _ request: JSONRPCRequest,
        principal: IPCPrincipal,
        socketSubscriber: any IPCEventSubscriber
    ) async throws -> JSONValue {
        if let contribution = service.methodRegistry.contribution(named: request.method) {
            let dispatchContext = AppIPCContributionDispatchContext(
                paneSnapshotReader: { [self] paneId in
                    try await service.ports.queryPort.snapshotPane(paneId)
                },
                paneHandleDecoder: { [self] rawHandle in
                    try uuidFromPaneHandle(rawHandle)
                }
            )
            return try await contribution.dispatch(request, principal, dispatchContext) ?? .null
        }

        switch request.method {
        case "system.identify", "system.version", "system.capabilities", "window.list", "window.current",
            "workspace.list", "workspace.current", "pane.list", "pane.current":
            return try await processQueryRequest(request)
        case "pane.focus", "pane.split", "pane.close", "drawer.addPane", "drawer.toggle":
            return try await processLayoutRequest(request)
        case "terminal.status", "terminal.snapshot", "terminal.send", "terminal.wait":
            return try await processRuntimeRequest(request)
        case "command.list", "command.execute", "ui.commandBar.open":
            return try await processCommandOrUIRequest(request, principal: principal)
        case "sidebar.grouping.get", "sidebar.surface.get":
            return try await processSidebarRequest(request)
        case "permission.request", "permission.requestStatus", "permission.grantStatus",
            "permission.pendingApprovals", "permission.resolveRequest":
            return try processPermissionRequest(request, principal: principal)
        case "events.subscribe", "events.unsubscribe":
            return try await processEventRequest(
                request,
                principal: principal,
                socketSubscriber: socketSubscriber
            )
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func processQueryRequest(_ request: JSONRPCRequest) async throws -> JSONValue {
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
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func processLayoutRequest(_ request: JSONRPCRequest) async throws -> JSONValue {
        switch request.method {
        case "pane.focus":
            let params = try decodeParams(HandleParams.self, from: request.params)
            let handle = try IPCHandle.parse(params.handle)
            return try await encodeResult(service.ports.layoutPort.focusPane(handle))
        case "pane.split":
            let params = try decodeParams(IPCPaneSplitParams.self, from: request.params)
            return try await encodeResult(service.ports.layoutPort.splitPane(params))
        case "pane.close":
            let params = try decodeParams(IPCPaneCloseParams.self, from: request.params)
            return try await encodeResult(service.ports.layoutPort.closePane(params))
        case "drawer.addPane":
            let params = try decodeParams(IPCDrawerAddPaneParams.self, from: request.params)
            return try await encodeResult(service.ports.layoutPort.addDrawerPane(params))
        case "drawer.toggle":
            let params = try decodeParams(IPCDrawerToggleParams.self, from: request.params)
            return try await encodeResult(service.ports.layoutPort.toggleDrawer(params))
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func processRuntimeRequest(_ request: JSONRPCRequest) async throws -> JSONValue {
        switch request.method {
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
            let timeout = try Self.validatedTimeout(from: params.timeoutSeconds)
            let result = try await service.ports.runtimePort.waitForTerminal(
                handle,
                condition: params.condition,
                timeout: timeout,
                afterSequence: params.afterSequence
            )
            return try encodeResult(result)
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private static func validatedTimeout(from timeoutSeconds: Double) throws -> Duration {
        let maxTimeoutMilliseconds: Int64 = 86_400_000
        guard timeoutSeconds.isFinite, timeoutSeconds >= 0 else {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
        let timeoutMilliseconds = (timeoutSeconds * 1000).rounded(.up)
        guard timeoutMilliseconds <= Double(maxTimeoutMilliseconds) else {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
        return .milliseconds(Int64(timeoutMilliseconds))
    }

    private func processCommandOrUIRequest(
        _ request: JSONRPCRequest,
        principal: IPCPrincipal
    ) async throws -> JSONValue {
        switch request.method {
        case "command.list":
            let result = try await MainActor.run {
                try service.ports.commandPort.listCommands()
            }
            return try encodeResult(result)
        case "command.execute":
            let params = try decodeParams(IPCCommandExecuteParams.self, from: request.params)
            let command = try await MainActor.run {
                try service.ports.commandPort.listCommands().commands.first { $0.id == params.commandId }
            }
            guard let command else {
                throw AppIPCCommandError(reason: .unsupportedCommand)
            }
            let requiredScopes = try await MainActor.run {
                try service.ports.commandPort.requiredPermissionScopes(for: command)
            }
            for scope in requiredScopes {
                try authorizationService.authorize(
                    principal: principal,
                    scope: scope
                )
            }
            let result = try await MainActor.run {
                try service.ports.commandPort.executeCommand(params)
            }
            return try encodeResult(result)
        case "ui.commandBar.open":
            let params = try decodeParams(IPCCommandBarOpenParams.self, from: request.params)
            let result = try await MainActor.run {
                try service.ports.uiPresentationPort.openCommandBar(params)
            }
            return try encodeResult(result)
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func processSidebarRequest(_ request: JSONRPCRequest) async throws -> JSONValue {
        switch request.method {
        case "sidebar.grouping.get":
            let params = try decodeParams(IPCSidebarGroupingGetParams.self, from: request.params)
            let result = try await MainActor.run {
                try service.ports.sidebarPort.getGrouping(params)
            }
            return try encodeResult(result)
        case "sidebar.surface.get":
            let params = try decodeParams(IPCSidebarSurfaceGetParams.self, from: request.params)
            let result = try await MainActor.run {
                try service.ports.sidebarPort.getSurface(params)
            }
            return try encodeResult(result)
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func processPermissionRequest(_ request: JSONRPCRequest, principal: IPCPrincipal) throws -> JSONValue {
        switch request.method {
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
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func processEventRequest(
        _ request: JSONRPCRequest,
        principal: IPCPrincipal,
        socketSubscriber: any IPCEventSubscriber
    ) async throws -> JSONValue {
        switch request.method {
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
}
