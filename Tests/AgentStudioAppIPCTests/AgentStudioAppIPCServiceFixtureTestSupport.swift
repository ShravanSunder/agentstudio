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
    let workspaceId = UUIDv7.generate()
    let rootURL: URL
    let paths: AgentStudioIPCPaths
    let server: AgentStudioAppIPCServer
    private let testCredentialResolver: IPCFixtureCredentialResolver?

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
        credentialResolver: (any AgentStudioIPCCredentialResolving)? = nil,
        credentialContinuityPort: any AgentStudioIPCCredentialContinuityPort = TestCredentialContinuityPort(),
        canonicalPaneMembership: (@MainActor @Sendable (UUID, UUID) -> Bool)? = nil
    ) throws {
        let resolvedCredentialResolver = credentialResolver ?? IPCFixtureCredentialResolver()
        testCredentialResolver = resolvedCredentialResolver as? IPCFixtureCredentialResolver
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
                accessMode: accessMode
            ),
            ports: ports,
            methodRegistry: methodRegistry,
            eventBroker: eventBroker
        )
        let fixtureWorkspaceID = workspaceId
        let fixtureBoundPaneID = boundPaneId
        let eligiblePaneIDs = Set(panes.map(\.id))
        let resolvedCanonicalPaneMembership =
            canonicalPaneMembership ?? { candidatePaneID, candidateWorkspaceID in
                candidateWorkspaceID == fixtureWorkspaceID
                    && (candidatePaneID == fixtureBoundPaneID || eligiblePaneIDs.contains(candidatePaneID))
            }
        let principalRegistry = AgentStudioIPCPrincipalRegistry(
            runtimeId: runtimeId,
            credentialResolver: resolvedCredentialResolver,
            canonicalPaneMembership: resolvedCanonicalPaneMembership
        )
        server = AgentStudioAppIPCServer(
            service: service,
            paths: paths,
            channel: channel,
            principalRegistry: principalRegistry,
            credentialContinuityPort: credentialContinuityPort
        )
    }

    func issueTestCredential(for intent: IPCFixtureCredentialIntent) throws -> AgentStudioIPCSubjectToken {
        guard let testCredentialResolver else {
            throw IPCFixtureCredentialError.requiresExplicitResolver
        }
        return testCredentialResolver.issueTestCredential(for: intent, workspaceId: workspaceId, runtimeId: runtimeId)
    }

    func cleanup() {
        server.stop()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

final class TestCredentialContinuityPort: AgentStudioIPCCredentialContinuityPort, @unchecked Sendable {
    func registerIssuedPaneCredential(
        _: AgentStudioIPCIssuedPaneCredential,
        if _: @escaping @Sendable () -> Bool
    ) async throws -> Bool { true }

    func revokeAllPaneCredentials(paneID _: UUID) async throws {}
}

enum IPCFixtureCredentialIntent: Sendable {
    case pane(paneId: UUID, credentialRecordId: UUID, status: AgentStudioIPCPaneCredentialStatus)
    case diagnostic(generationId: UUID, status: AgentStudioIPCDiagnosticCredentialStatus)
}

enum IPCFixtureCredentialError: Error, Equatable {
    case requiresExplicitResolver
}

final class IPCFixtureCredentialResolver: AgentStudioIPCCredentialResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var resolutions: [String: AgentStudioIPCCredentialResolution] = [:]

    func issueTestCredential(
        for intent: IPCFixtureCredentialIntent,
        workspaceId: UUID,
        runtimeId: UUID
    ) -> AgentStudioIPCSubjectToken {
        let token = AgentStudioIPCSubjectToken(rawValue: "fixture-\(UUIDv7.generate().uuidString)")
        let resolution: AgentStudioIPCCredentialResolution
        switch intent {
        case .pane(let paneId, let credentialRecordId, let status):
            resolution = .pane(
                paneID: paneId,
                workspaceID: workspaceId,
                credentialRecordID: credentialRecordId,
                status: status
            )
        case .diagnostic(let generationId, let status):
            resolution = .diagnostic(
                runtimeID: runtimeId,
                generationID: generationId,
                status: status
            )
        }
        lock.withLock {
            resolutions[token.rawValue] = resolution
        }
        return token
    }

    func resolveCredential(
        _ credential: AgentStudioIPCSubjectToken,
        serverRuntimeID _: UUID
    ) async throws -> AgentStudioIPCCredentialResolution {
        guard let resolution = lock.withLock({ resolutions[credential.rawValue] }) else {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        return resolution
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
