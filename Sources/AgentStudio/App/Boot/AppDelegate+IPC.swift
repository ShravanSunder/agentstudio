import AgentStudioAppIPC
import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import CryptoKit
import Foundation
import Security

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
    func installAppIPCIdentityAuthority(datastore: WorkspaceSQLiteDatastoreActor) {
        let runtimeID = UUIDv7.generate()
        let paths = AgentStudioIPCPathResolver().paths(
            rootDirectory: AppDataPaths.rootDirectory(),
            socketDirectory: Self.appIPCSocketDirectory()
        )
        let repository = IPCContinuityRepository(datastore: datastore)
        let resolver = IPCContinuityCredentialResolver(repository: repository)
        let registry = AgentStudioIPCPrincipalRegistry(
            runtimeId: runtimeID,
            credentialResolver: resolver,
            canonicalPaneMembership: { [store] paneID, workspaceID in
                store.identityAtom.workspaceId == workspaceID && store.paneAtom.pane(paneID) != nil
            }
        )
        appIPCRuntimeID = runtimeID
        appIPCPaths = paths
        appIPCDebugCredentialEscrowURL = Self.appIPCDebugCredentialEscrowURL()
        appIPCContinuityRepository = repository
        appIPCCredentialResolver = resolver
        appIPCPrincipalRegistry = registry
        paneIPCIdentityOwner = PaneIPCIdentityOwner(
            principalRegistry: registry,
            socketURL: paths.socketURL,
            spoolDirectory: paths.spoolDirectory,
            cliExecutableURL: Bundle.main.bundleURL
                .appending(path: "Contents/Helpers/agentstudio"),
            canonicalPaneMembership: { [store] paneID, workspaceID in
                store.identityAtom.workspaceId == workspaceID && store.paneAtom.pane(paneID) != nil
            }
        )
    }

    func appIPCWorkspaceSurfaceLifecycle() -> WorkspaceSurfaceIPCLifecycle {
        let paneIPCIdentityOwner = paneIPCIdentityOwner!
        return WorkspaceSurfaceIPCLifecycle(
            environment: { paneID, workspaceID in
                paneIPCIdentityOwner.terminalEnvironment(paneID: paneID, workspaceID: workspaceID)
            },
            invalidatePaneIDs: { [weak self] paneIDs in
                for paneID in paneIDs {
                    if let server = self?.appIPCServer {
                        server.invalidatePrincipals(boundToPaneId: paneID.uuidString)
                    } else {
                        self?.appIPCPrincipalRegistry.invalidatePrincipals(boundToPaneId: paneID.uuidString)
                    }
                }
            },
            finalRevokePaneIDs: { [weak self] paneIDs in
                for paneID in paneIDs {
                    if let server = self?.appIPCServer {
                        server.finalRevokePrincipals(boundToPaneID: paneID)
                    } else {
                        self?.appIPCPrincipalRegistry.finalRevokePane(paneID)
                    }
                }
            }
        )
    }

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
        guard let sessionsIngestion = await prepareAppIPCSessionsIngestion(datastore: workspaceSQLiteDatastore) else {
            return
        }

        do {
            let composition = try makeAppIPCServer(sessionsIngestion: sessionsIngestion)
            try composition.server.start()
            appIPCServer = composition.server
            appLogger.info("App IPC server started at \(composition.socketURL.path, privacy: .private)")
            publishDebugCredentialEscrow(socketURL: composition.socketURL)
            startPaneReportSpoolDrain(sessionsIngestion: sessionsIngestion)
        } catch {
            appLogger.warning(
                "App IPC server failed to start: \(error.localizedDescription, privacy: .private)")
        }
    }

    func stopAppIPCServer() {
        appIPCInitializationTask?.cancel()
        appIPCInitializationTask = nil
        paneReportSpoolDrainTask?.cancel()
        paneReportSpoolDrainTask = nil
        retireDebugCredentialEscrow()
        appIPCServer?.stop()
        appIPCServer = nil
        finishAppIPCSessionsIngestion()
    }

    /// Only a debug app whose launcher named an escrow file hands out a reusable
    /// credential, and only after the socket is listening: the raw value reaches
    /// disk with the endpoint that accepts it. The credential lives in the
    /// principal registry's memory and is never persisted. A failed handover
    /// leaves debug authentication unavailable; it never falls back to the
    /// separate unsafe no-auth composition.
    private func publishDebugCredentialEscrow(socketURL: URL) {
        guard Self.appIPCChannel() == .debug,
            let escrowURL = appIPCDebugCredentialEscrowURL
        else { return }
        var credentialBytes = Data(count: 32)
        let generatedCredential = credentialBytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard generatedCredential == errSecSuccess else {
            appLogger.warning("Debug IPC credential unavailable: random generation failed")
            return
        }
        let token = credentialBytes.base64EncodedString()
        let generationID = appIPCPrincipalRegistry.installDiagnosticCredential(
            verifierSHA256: Data(SHA256.hash(data: Data(token.utf8)))
        )
        do {
            try AgentStudioIPCFilesystem.writeDebugCredentialEscrow(
                IPCDebugCredentialEscrowDocument(
                    runtimeId: appIPCRuntimeID,
                    socketPath: socketURL.path,
                    token: token
                ),
                to: escrowURL
            )
        } catch {
            appIPCPrincipalRegistry.revokeDiagnosticCredential()
            appLogger.warning(
                """
                Debug IPC credential unavailable: escrow handover failed for generation \
                \(generationID, privacy: .public)
                """
            )
        }
    }

    private func retireDebugCredentialEscrow() {
        appIPCPrincipalRegistry?.revokeDiagnosticCredential()
        guard let escrowURL = appIPCDebugCredentialEscrowURL else { return }
        AgentStudioIPCFilesystem.removeDebugCredentialEscrow(at: escrowURL)
    }

    /// Notifications the CLI spooled while this app was unreachable are admitted
    /// once IPC is listening and ingestion is prepared. The drain is detached and
    /// awaited nowhere, so no startup, terminal or zmx path waits on it.
    private func startPaneReportSpoolDrain(sessionsIngestion: SessionsIngestion) {
        guard paneReportSpoolDrainTask == nil, let spoolDirectory = appIPCPaths?.spoolDirectory else {
            return
        }
        let lateAdmission = AgentStudioIPCSessionsAdapter(
            ingestion: sessionsIngestion,
            providerRegistry: SessionsProviderAdapterRegistry(profiles: appIPCSessionsProviderProfiles),
            admissionFreshness: .late
        )
        let spool: PaneReportSpool
        do {
            spool = try PaneReportSpool(admission: lateAdmission)
        } catch {
            appLogger.warning(
                "Offline notification drain skipped: \(error.localizedDescription, privacy: .private)"
            )
            return
        }
        // The drain must not inherit MainActor isolation: it holds a file lock
        // across admission and nothing on the startup path may await it.
        // swiftlint:disable:next no_task_detached
        paneReportSpoolDrainTask = Task.detached(priority: .utility) {
            let report = await spool.drain(spoolDirectory: spoolDirectory)
            guard report.hasWork else { return }
            appLogger.info(
                """
                Offline notification drain admitted \(report.admittedLineCount, privacy: .public) \
                rejected \(report.rejectedLineCount, privacy: .public) \
                malformed \(report.malformedLineCount, privacy: .public) \
                retained \(report.retainedFileCount, privacy: .public) files
                """
            )
        }
    }

    /// Sessions ingestion is built with the IPC server, not on the first-frame
    /// or terminal paths. Launch preparation ends the previous run's active
    /// sources before any live report can reach them.
    private func prepareAppIPCSessionsIngestion(
        datastore: WorkspaceSQLiteDatastoreActor
    ) async -> SessionsIngestion? {
        if let existing = appIPCSessionsIngestion { return existing }
        let ingestion = SessionsIngestion(
            repository: SessionsRepository(
                sqliteAccess: WorkspaceSessionsSQLiteAccess(datastore: datastore)
            ),
            limits: SessionsIngestionLimits(
                maximumPendingPerPane: AppPolicies.Sessions.maximumPendingIngestionPerPane,
                maximumPendingGlobal: AppPolicies.Sessions.maximumPendingIngestionGlobal
            ),
            // Ingestion statistics carry a raw pane UUID, which the OTLP scrub
            // rules exclude. Counts reach no sink until a scrubbed probe exists.
            probe: { _ in }
        )
        do {
            _ = try await ingestion.prepareForLaunch(at: Date())
        } catch {
            appLogger.warning(
                """
                Sessions ingestion skipped: launch preparation failed: \
                \(error.localizedDescription, privacy: .private)
                """
            )
            return nil
        }
        guard !Task.isCancelled else { return nil }
        appIPCSessionsIngestion = ingestion
        return ingestion
    }

    private func finishAppIPCSessionsIngestion() {
        guard let ingestion = appIPCSessionsIngestion else { return }
        appIPCSessionsIngestion = nil
        Task { await ingestion.finish() }
    }

    /// Ends IPC ingress and nothing else. No durable write happens here and
    /// nothing waits for one, so this runs before the workspace flush: it
    /// closes the window in which a late `command.execute` or Bridge open could
    /// mutate state the flush has already written. The escrow file only names
    /// the socket, so it is retired here too.
    func stopAcceptingAppIPCConnections() async {
        let initializationTask = appIPCInitializationTask
        initializationTask?.cancel()
        await initializationTask?.value
        appIPCInitializationTask = nil
        retireDebugCredentialEscrow()
        appIPCServer?.stopAcceptingConnections()
    }

    /// The durable half, which runs after the workspace flush. It writes
    /// through the same serialized workspace datastore actor the offline spool
    /// drain admits through, and that drain holds a file lock across admission,
    /// so it is retired before this waits on anything.
    func drainAppIPCCredentialPersistence() async {
        paneReportSpoolDrainTask?.cancel()
        paneReportSpoolDrainTask = nil
        guard let server = appIPCServer else {
            appIPCPrincipalRegistry?.shutdown()
            finishAppIPCSessionsIngestion()
            appLogger.info("App IPC shutdown completed without a published server or durable drain")
            return
        }
        let result = await server.drainCredentialPersistence()
        appIPCServer = nil
        finishAppIPCSessionsIngestion()
        if result.failedOperationCount > 0 {
            appLogger.warning(
                "App IPC credential persistence drain completed with \(result.failedOperationCount) failures"
            )
        }
    }

    private func makeAppIPCServer(
        sessionsIngestion: SessionsIngestion
    ) throws -> (server: AgentStudioAppIPCServer, socketURL: URL) {
        let runtimeId = appIPCRuntimeID!
        let accessMode = Self.appIPCAccessMode()
        let paths = appIPCPaths!
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
                channel: Self.appIPCChannel(),
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
            sessionsPort: AgentStudioIPCSessionsAdapter(
                ingestion: sessionsIngestion,
                providerRegistry: SessionsProviderAdapterRegistry(
                    profiles: appIPCSessionsProviderProfiles
                )
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
        return (
            AgentStudioAppIPCServer(
                service: service,
                paths: paths,
                channel: Self.appIPCChannel(),
                principalRegistry: appIPCPrincipalRegistry,
                credentialContinuityPort: appIPCContinuityRepository
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

    private static func appIPCDebugCredentialEscrowURL() -> URL? {
        #if DEBUG
            guard
                let rawPath = ProcessInfo.processInfo
                    .environment[IPCDebugCredentialEscrowDocument.environmentVariableName]?
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
