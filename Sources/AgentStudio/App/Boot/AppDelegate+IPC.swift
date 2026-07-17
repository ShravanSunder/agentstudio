import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

extension AppDelegate {
    func startAppIPCServer() {
        guard appIPCServer == nil else { return }

        do {
            let ipcComposition = try AgentStudioIPCContributionRegistry.phaseAComposition()
            let runtimeId = UUID()
            let accessMode = Self.appIPCAccessMode()
            let rootDirectory = AppDataPaths.rootDirectory()
            let paths = AgentStudioIPCPathResolver().paths(
                rootDirectory: rootDirectory,
                socketDirectory: Self.appIPCSocketDirectory()
            )
            let windowLifecycleReader = WorkspaceWindowLifecycleReader(lifecycleStore: windowLifecycleStore)
            guard let paneFocusControl = mainWindowController?.makePaneFocusAppControl(store: store) else {
                appLogger.warning("App IPC server skipped: pane focus control is unavailable")
                return
            }

            let service = try AgentStudioAppIPCService(
                configuration: AgentStudioAppIPCConfiguration(
                    runtimeId: runtimeId,
                    accessMode: accessMode,
                    methodDefinitions: ipcComposition.baseDefinitions,
                    debugTokenEscrowEnabled: Self.appIPCDebugTokenEscrowEnabled(),
                    debugTokenEscrowPermissionScopes: [
                        IPCPermissionScope(
                            privilege: .sidebarStateMutate,
                            target: .workspace(store.identityAtom.workspaceId),
                            dataScope: .sidebarState
                        )
                    ]
                ),
                ports: AgentStudioAppIPCPorts(
                    queryPort: AgentStudioIPCQueryAdapter(
                        runtimeId: runtimeId,
                        accessMode: accessMode,
                        appVersion: Self.appIPCAppVersion(),
                        methodRegistry: ipcComposition.methodRegistry,
                        workspaceStore: store,
                        windowLifecycleReader: windowLifecycleReader
                    ),
                    layoutPort: AgentStudioIPCLayoutAdapter(
                        workspaceStore: store,
                        windowLifecycleReader: windowLifecycleReader,
                        paneFocusControl: paneFocusControl,
                        workspaceActionExecutor: executor
                    ),
                    runtimePort: AgentStudioIPCRuntimeAdapter(
                        workspaceStore: store,
                        runtimeRegistry: workspaceSurfaceCoordinator.runtimeRegistry,
                        commandDispatcher: workspaceSurfaceCoordinator
                    ),
                    commandPort: AgentStudioIPCCommandAdapter(
                        workspaceId: store.identityAtom.workspaceId,
                        repositoryTargetAuthorizer: WorkspaceRepositoryTargetAuthorizationPort(
                            repositoryTopology: store.repositoryTopologyAtom
                        ),
                        windowLifecycleReader: windowLifecycleReader,
                        shellCommandHandler: self
                    ),
                    uiPresentationPort: AgentStudioIPCUIPresentationAdapter(presenter: self),
                    sidebarPort: AgentStudioIPCSidebarAdapter(
                        repoPrefs: atomStore.repoExplorerSidebarPrefs,
                        inboxPrefs: atomStore.inboxNotificationPrefs,
                        sidebarState: atomStore.workspaceSidebarState
                    ),
                    permissionApprovalPort: AgentStudioIPCHumanApprovalPort()
                ),
                methodContributions: ipcComposition.methodContributions
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

    private static func appIPCAccessMode() -> IPCAccessMode {
        #if DEBUG
            if ProcessInfo.processInfo.environment["AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"] == "1" {
                return .unsafeDebug
            }
        #endif
        return .agentStudioOnly
    }

    private static func appIPCDebugTokenEscrowEnabled() -> Bool {
        #if DEBUG
            return ProcessInfo.processInfo.environment["AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW"] == "1"
        #else
            return false
        #endif
    }

    private static func appIPCSocketDirectory() -> URL? {
        #if DEBUG
            guard
                let rawPath = ProcessInfo.processInfo.environment["AGENTSTUDIO_IPC_SOCKET_DIR"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawPath.isEmpty
            else {
                return nil
            }

            return URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
                .standardizedFileURL
        #else
            return nil
        #endif
    }
}
