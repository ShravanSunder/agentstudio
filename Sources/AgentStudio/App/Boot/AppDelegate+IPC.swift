import AgentStudioAppIPC
import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

@MainActor
enum AppIPCDeferredInitialization {
    static func run(
        windowLifecycleStore: WindowLifecycleAtom,
        initialization: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard await windowLifecycleStore.waitUntilFirstInteractiveFramePublished() == .completed else {
            return
        }
        guard !Task.isCancelled else { return }
        await initialization()
    }

    static func prepareOptionalSchema(
        using datastore: WorkspaceSQLiteDatastoreActor
    ) async -> Bool {
        guard case .ready = await datastore.prepareOptionalApplicationLocalSchema() else {
            return false
        }
        return !Task.isCancelled
    }
}

extension AppDelegate {
    func scheduleAppIPCInitialization() {
        guard appIPCServer == nil, appIPCInitializationTask == nil else { return }
        let windowLifecycleStore = windowLifecycleStore!
        appIPCInitializationTask = Task { @MainActor [weak self] in
            await AppIPCDeferredInitialization.run(
                windowLifecycleStore: windowLifecycleStore
            ) { [weak self] in
                await self?.startAppIPCServer()
            }
        }
    }

    func startAppIPCServer() async {
        guard appIPCServer == nil else { return }
        guard let workspaceSQLiteDatastore else {
            appLogger.warning("App IPC server skipped: local SQLite is unavailable")
            return
        }
        guard await AppIPCDeferredInitialization.prepareOptionalSchema(using: workspaceSQLiteDatastore) else {
            appLogger.warning("App IPC server skipped: optional local schema is unavailable")
            return
        }
        guard appIPCServer == nil else { return }

        do {
            let composition = try makeAppIPCServer(workspaceSQLiteDatastore: workspaceSQLiteDatastore)
            try composition.server.start()
            appIPCServer = composition.server
            appLogger.info("App IPC server started at \(composition.socketURL.path, privacy: .private)")
        } catch {
            appLogger.warning("App IPC server failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    func stopAppIPCServer() {
        appIPCInitializationTask?.cancel()
        appIPCInitializationTask = nil
        appIPCServer?.stop()
        appIPCServer = nil
    }

    private func makeAppIPCServer(
        workspaceSQLiteDatastore: WorkspaceSQLiteDatastoreActor
    ) throws -> (server: AgentStudioAppIPCServer, socketURL: URL) {
        let runtimeId = UUIDv7.generate()
        let accessMode = Self.appIPCAccessMode()
        let rootDirectory = AppDataPaths.rootDirectory()
        let paths = AgentStudioIPCPathResolver().paths(
            rootDirectory: rootDirectory,
            socketDirectory: Self.appIPCSocketDirectory()
        )
        let windowLifecycleReader = WorkspaceWindowLifecycleReader(lifecycleStore: windowLifecycleStore)
        guard mainWindowController?.acceptsIPCCommands == true else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        let ports = AgentStudioAppIPCPorts(
            queryPort: AgentStudioIPCQueryAdapter(
                runtimeId: runtimeId,
                accessMode: accessMode,
                appVersion: Self.appIPCAppVersion(),
                workspaceStore: store,
                windowLifecycleReader: windowLifecycleReader
            ),
            layoutPort: AgentStudioIPCLayoutAdapter(
                workspaceStore: store,
                windowLifecycleReader: windowLifecycleReader,
                paneFocusControl: self,
                workspaceActionExecutor: executor
            ),
            runtimePort: AgentStudioIPCRuntimeAdapter(
                workspaceStore: store,
                runtimeRegistry: workspaceSurfaceCoordinator.runtimeRegistry,
                commandDispatcher: workspaceSurfaceCoordinator
            ),
            bridgePort: AgentStudioIPCBridgeAdapter(
                workspaceStore: store,
                viewRegistry: viewRegistry,
                actionExecutor: executor
            ),
            commandPort: AgentStudioIPCCommandAdapter(
                workspaceId: store.identityAtom.workspaceId,
                targetAuthorizer: WorkspaceDurableTargetAuthorizationPort(workspaceStore: store),
                shellCommandHandler: self
            ),
            uiPresentationPort: AgentStudioIPCUIPresentationAdapter(
                presenter: self,
                targetAuthorizer: WorkspaceDurableTargetAuthorizationPort(workspaceStore: store)
            ),
            sidebarPort: AgentStudioIPCSidebarAdapter(
                repoPrefs: atomStore.repoExplorerSidebarPrefs,
                sidebarState: atomStore.core.workspaceSidebarState
            ),
            permissionApprovalPort: AgentStudioIPCHumanApprovalPort()
        )
        let eventBroker = IPCEventBroker()
        let catalog = try Self.appIPCBuiltInMethodCatalog()
        var registrations = try AppIPCBuiltInMethodRegistrations.make(
            inputs: .init(catalog: catalog, runtimeId: runtimeId, ports: ports, eventBroker: eventBroker)
        )
        let commandComposition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: ports.commandPort.listCommands().commands
        )
        registrations += try AppIPCCommandMethodRegistrations.make(
            composition: commandComposition,
            port: ports.commandPort
        )
        let registry = try AppIPCMethodRegistry(registrations: registrations, channel: Self.appIPCChannel())
        let service = AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(runtimeId: runtimeId, accessMode: accessMode),
            ports: ports,
            methodRegistry: registry,
            eventBroker: eventBroker
        )
        let continuityRepository = IPCContinuityRepository(datastore: workspaceSQLiteDatastore)
        let credentialResolver = IPCContinuityCredentialResolver(repository: continuityRepository)
        let principalRegistry = AgentStudioIPCPrincipalRegistry(
            runtimeId: runtimeId,
            credentialResolver: credentialResolver,
            canonicalPaneMembership: { [store] paneID, workspaceID in
                store.identityAtom.workspaceId == workspaceID && store.paneAtom.pane(paneID) != nil
            }
        )
        return (
            AgentStudioAppIPCServer(
                service: service,
                paths: paths,
                channel: Self.appIPCChannel(),
                principalRegistry: principalRegistry,
                credentialContinuityPort: continuityRepository
            ),
            paths.socketURL
        )
    }

    private static func appIPCAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func appIPCBuiltInMethodCatalog() throws -> IPCBuiltInMethodCatalog {
        try IPCBuiltInMethodCatalog(
            inputs: .init(
                terminalWaitMaximumSeconds: AppPolicies.IPC.maximumTerminalWaitSeconds,
                relationships: .init(
                    paneFocus: .appCommand(identifier: AppCommand.focusPane.rawValue),
                    paneClose: .appCommand(identifier: AppCommand.closePane.rawValue),
                    drawerToggle: .appCommand(identifier: AppCommand.toggleDrawer.rawValue),
                    drawerAddPane: .appCommand(identifier: AppCommand.addDrawerPane.rawValue),
                    bridgeDiffLoad: .appCommand(identifier: AppCommand.showBridgeReview.rawValue),
                    bridgeFileViewOpen: .appCommand(identifier: AppCommand.showBridgeFiles.rawValue)
                ),
                examples: .init(illustrativeIdentifier: UUIDv7.generate())
            )
        )
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

    static func debugAutomationIPCPermissionScopes(workspaceId: UUID) -> [IPCPermissionScope] {
        [
            IPCPermissionScope(
                privilege: .workspaceRead,
                target: .app,
                dataScope: .unspecified
            ),
            IPCPermissionScope(
                privilege: .appCommandExecute,
                target: .app,
                dataScope: .unspecified
            ),
            IPCPermissionScope(
                privilege: .layoutMutate,
                target: .app,
                dataScope: .paneContext
            ),
            IPCPermissionScope(
                privilege: .uiPresent,
                target: .app,
                dataScope: .uiSurface
            ),
            IPCPermissionScope(
                privilege: .sidebarStateMutate,
                target: .workspace(workspaceId),
                dataScope: .sidebarState
            ),
        ]
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

extension AppDelegate: PaneFocusAppControlling {
    func focusPane(_ paneId: UUID) throws {
        guard let controller = mainWindowController, controller.acceptsIPCCommands,
            let focusControl = controller.makePaneFocusAppControl(store: store)
        else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        try focusControl.focusPane(paneId)
    }
}
