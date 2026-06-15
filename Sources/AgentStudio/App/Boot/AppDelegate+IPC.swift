import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

extension AppDelegate {
    func startAppIPCServer() {
        guard appIPCServer == nil else { return }

        do {
            let methodRegistry = try AppIPCMethodRegistry.phaseOne()
            let runtimeId = UUID()
            let accessMode = IPCAccessMode.agentStudioOnly
            let rootDirectory = AppDataPaths.rootDirectory()
            let paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootDirectory)
            let windowLifecycleReader = WorkspaceWindowLifecycleReader(lifecycleStore: windowLifecycleStore)
            guard let paneFocusControl = mainWindowController?.makePaneFocusAppControl(store: store) else {
                appLogger.warning("App IPC server skipped: pane focus control is unavailable")
                return
            }

            let service = AgentStudioAppIPCService(
                configuration: AgentStudioAppIPCConfiguration(
                    runtimeId: runtimeId,
                    accessMode: accessMode,
                    methodDefinitions: methodRegistry.definitions
                ),
                ports: AgentStudioAppIPCPorts(
                    queryPort: AgentStudioIPCQueryAdapter(
                        runtimeId: runtimeId,
                        accessMode: accessMode,
                        appVersion: Self.appIPCAppVersion(),
                        methodRegistry: methodRegistry,
                        workspaceStore: store,
                        windowLifecycleReader: windowLifecycleReader
                    ),
                    layoutPort: AgentStudioIPCLayoutAdapter(
                        workspaceStore: store,
                        windowLifecycleReader: windowLifecycleReader,
                        paneFocusControl: paneFocusControl
                    ),
                    runtimePort: AgentStudioIPCRuntimeAdapter(
                        workspaceStore: store,
                        runtimeRegistry: paneCoordinator.runtimeRegistry,
                        commandDispatcher: ActionExecutorRuntimeCommandDispatcher(actionExecutor: executor)
                    ),
                    permissionApprovalPort: AgentStudioIPCHumanApprovalPort()
                )
            )
            let server = AgentStudioAppIPCServer(
                service: service,
                paths: paths,
                channel: Self.appIPCChannel()
            )
            try server.start()
            appIPCServer = server
            appLogger.info("App IPC server started at \(paths.socketURL.path, privacy: .private)")
        } catch {
            appLogger.warning("App IPC server failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    func stopAppIPCServer() {
        appIPCServer?.stop()
        appIPCServer = nil
    }

    private static func appIPCAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func appIPCChannel() -> AgentStudioIPCChannel {
        #if DEBUG
            return .debug
        #else
            switch AppDataPaths.ReleaseChannel.current {
            case .stable:
                return .stable
            case .beta:
                return .beta
            }
        #endif
    }
}

private struct AgentStudioIPCHumanApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}
