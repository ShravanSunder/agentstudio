import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct LiveServerFixture {
    let runtimeId = UUID()
    let boundPaneId = UUID()
    let rootURL: URL
    let paths: AgentStudioIPCPaths
    let server: AgentStudioAppIPCServer

    init(
        accessMode: IPCAccessMode = .agentStudioOnly,
        channel: AgentStudioIPCChannel = .debug,
        panes: [IPCPaneSummary] = [],
        queryPort: (any AppIPCQueryPort)? = nil,
        runtimePort: any AppIPCRuntimePort = FakeRuntimePort(),
        bridgePort: (any AppIPCBridgePort)? = nil,
        commandPort: any AppIPCCommandPort = FakeCommandPort(),
        uiPresentationPort: any AppIPCUIPresentationPort = FakeUIPresentationPort(),
        sidebarPort: any AppIPCSidebarPort = FakeSidebarPort(),
        commandComposition: IPCCommandMethodComposition? = nil,
        debugTokenEscrowEnabled: Bool = false,
        debugTokenEscrowPermissionScopes: [IPCPermissionScope] = []
    ) throws {
        rootURL = URL(
            fileURLWithPath: "/tmp/asipc-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        #if canImport(Darwin)
            _ = chmod(rootURL.path, 0o700)
        #endif
        paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootURL)
        let ports = AgentStudioAppIPCPorts(
            queryPort: queryPort ?? FakeQueryPort(runtimeId: runtimeId, panes: panes),
            layoutPort: FakeLayoutPort(),
            runtimePort: runtimePort,
            bridgePort: bridgePort ?? FakeBridgePort(paneId: panes.first?.id ?? boundPaneId),
            commandPort: commandPort,
            uiPresentationPort: uiPresentationPort,
            sidebarPort: sidebarPort,
            permissionApprovalPort: FakePermissionApprovalPort()
        )
        let eventBroker = IPCEventBroker()
        let catalog = try makeLiveServerBuiltInCatalog(
            runtimeId: runtimeId,
            paneId: panes.first?.id ?? boundPaneId
        )
        var registrations = try AppIPCBuiltInMethodRegistrations.make(
            inputs: AppIPCBuiltInRegistrationInputs(
                catalog: catalog,
                runtimeId: runtimeId,
                ports: ports,
                eventBroker: eventBroker
            )
        )
        if let commandComposition {
            registrations += try AppIPCCommandMethodRegistrations.make(
                composition: commandComposition,
                port: commandPort
            )
        }
        let methodRegistry = try AppIPCMethodRegistry(registrations: registrations, channel: channel)
        let service = AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(
                runtimeId: runtimeId,
                accessMode: accessMode,
                debugTokenEscrowEnabled: debugTokenEscrowEnabled,
                debugTokenEscrowPermissionScopes: debugTokenEscrowPermissionScopes
            ),
            ports: ports,
            methodRegistry: methodRegistry,
            eventBroker: eventBroker
        )
        server = AgentStudioAppIPCServer(service: service, paths: paths, channel: channel)
    }

    func cleanup() {
        server.stop()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

func makePaneSummary(
    id: UUID,
    ordinal: Int,
    contentKind: IPCPaneContentKind = .terminal
) -> IPCPaneSummary {
    IPCPaneSummary(
        id: id,
        ordinal: ordinal,
        contentKind: contentKind,
        residency: .active,
        tabId: nil,
        repoId: nil,
        worktreeId: nil,
        isActive: false,
        isDrawerChild: false
    )
}

func makePaneSnapshotResult(pane: IPCPaneSummary, paneCount: Int) -> IPCPaneSnapshotResult {
    IPCPaneSnapshotResult(
        pane: pane,
        tab: nil,
        workspace: IPCWorkspaceSummary(
            id: UUID(),
            ordinal: 1,
            name: "Test Workspace",
            tabCount: 1,
            paneCount: paneCount,
            isCurrent: true
        )
    )
}

private func makeLiveServerBuiltInCatalog(
    runtimeId: UUID,
    paneId: UUID
) throws -> IPCBuiltInMethodCatalog {
    let illustrativeId = UUIDv7.generate()
    return try IPCBuiltInMethodCatalog(
        inputs: IPCBuiltInMethodCatalogInputs(
            terminalWaitMaximumSeconds: 86_400,
            relationships: IPCBuiltInMethodRelationshipInputs(
                paneFocus: .noInteractiveIdentity,
                paneClose: .noInteractiveIdentity,
                drawerToggle: .noInteractiveIdentity,
                drawerAddPane: .noInteractiveIdentity,
                bridgeDiffLoad: .noInteractiveIdentity,
                bridgeFileViewOpen: .noInteractiveIdentity
            ),
            examples: IPCBuiltInMethodExampleContext(
                runtimeId: runtimeId,
                windowId: illustrativeId,
                workspaceId: illustrativeId,
                repositoryId: illustrativeId,
                worktreeId: illustrativeId,
                tabId: illustrativeId,
                paneId: paneId,
                commandId: illustrativeId,
                correlationId: illustrativeId,
                subscriptionId: illustrativeId
            )
        )
    )
}
