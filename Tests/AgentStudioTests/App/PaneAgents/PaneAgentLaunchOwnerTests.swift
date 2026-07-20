import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

#if canImport(Darwin)
    import Darwin
#endif

@Suite("Pane agent launch owner", .serialized)
struct PaneAgentLaunchOwnerTests {
    @Test("launch remaps bootstrap fd and rewrites child environment")
    func launchRemapsBootstrapFDAndRewritesChildEnvironment() throws {
        let paneId = UUID()
        let runtimeId = UUID()
        let bootstrap = try makeBootstrap(socketPath: "/tmp/agentstudio-ipc.sock", runtimeId: runtimeId)
        defer {
            bootstrap.closeTokenReadFileDescriptor()
        }
        let provider = RecordingPaneAgentBootstrapProvider(bootstrap: bootstrap)
        let spawner = RecordingPaneAgentProcessSpawner(result: PaneAgentProcessHandle(processIdentifier: 42))
        let owner = PaneAgentLaunchOwner(
            bootstrapProvider: provider,
            processSpawner: spawner,
            helperExecutableURL: URL(fileURLWithPath: "/tmp/agentstudio-pane-agent")
        )

        let handle = try owner.launchPaneAgent(boundPaneId: paneId, boundWorkspaceId: nil)

        #expect(handle.processIdentifier == 42)
        #expect(provider.requestedPaneId == paneId.uuidString)
        let request = try #require(spawner.request)
        #expect(request.executableURL.path == "/tmp/agentstudio-pane-agent")
        #expect(request.environment["AGENTSTUDIO_IPC_SOCKET"] == "/tmp/agentstudio-ipc.sock")
        #expect(request.environment["AGENTSTUDIO_IPC_RUNTIME_ID"] == runtimeId.uuidString)
        #expect(
            request.environment["AGENTSTUDIO_IPC_BOOTSTRAP_FD"]
                == String(PaneAgentLaunchOwner.childBootstrapFileDescriptor)
        )
        #expect(request.environment.values.allSatisfy { !$0.contains("secret-token") })
        #expect(request.fileActions.count == 1)
        let fileAction = try #require(request.fileActions.first)
        #expect(fileAction.targetFileDescriptor == PaneAgentLaunchOwner.childBootstrapFileDescriptor)
        if bootstrap.descriptor.tokenReadFileDescriptor == PaneAgentLaunchOwner.childBootstrapFileDescriptor {
            #expect(fileAction.sourceFileDescriptor != bootstrap.descriptor.tokenReadFileDescriptor)
            #expect(fileAction.sourceFileDescriptor > PaneAgentLaunchOwner.childBootstrapFileDescriptor)
        } else {
            #expect(fileAction.sourceFileDescriptor == bootstrap.descriptor.tokenReadFileDescriptor)
        }
        #expect(request.closeAllUnmappedFileDescriptors)
    }

    @Test("spawn failure cancels the bootstrap token")
    func spawnFailureCancelsBootstrapToken() throws {
        let paneId = UUID()
        let bootstrap = try makeBootstrap(socketPath: "/tmp/agentstudio-ipc.sock", runtimeId: UUID())
        defer {
            bootstrap.closeTokenReadFileDescriptor()
        }
        let provider = RecordingPaneAgentBootstrapProvider(bootstrap: bootstrap)
        let spawner = RecordingPaneAgentProcessSpawner(error: PaneAgentLaunchError.spawnFailed(errnoCode: EACCES))
        let owner = PaneAgentLaunchOwner(
            bootstrapProvider: provider,
            processSpawner: spawner,
            helperExecutableURL: URL(fileURLWithPath: "/tmp/agentstudio-pane-agent")
        )

        #expect(throws: PaneAgentLaunchError.self) {
            _ = try owner.launchPaneAgent(boundPaneId: paneId, boundWorkspaceId: nil)
        }
        #expect(provider.cancelledBootstrap === bootstrap)
    }

    @Test("helper authenticates against local server through fd bootstrap")
    func helperAuthenticatesAgainstLocalServerThroughFDBootstrap() throws {
        #if canImport(Darwin)
            let helperURL = try findBuiltPaneAgentHelper()
            let fixture = try PaneAgentLiveServerFixture()
            defer {
                fixture.cleanup()
            }
            try fixture.server.start()
            let owner = PaneAgentLaunchOwner(
                bootstrapProvider: AgentStudioPaneAgentBootstrapProvider(server: fixture.server),
                helperExecutableURL: helperURL
            )

            let handle = try owner.launchPaneAgent(boundPaneId: fixture.boundPaneId, boundWorkspaceId: nil)

            let status = try #require(waitForProcessExit(processIdentifier: handle.processIdentifier))
            #expect(status == 0)
        #endif
    }

    @Test("pane agent helper target stays out of app and server targets")
    func paneAgentHelperTargetStaysOutOfAppAndServerTargets() throws {
        let packageURL = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
            .appending(path: "Package.swift")
        let package = try String(contentsOf: packageURL, encoding: .utf8)
        let targetStart = try #require(package.range(of: #"name: "AgentStudioPaneAgent""#)?.lowerBound)
        let targetSuffix = package[targetStart...]
        let targetEnd =
            targetSuffix.range(of: ".testTarget(")?
            .lowerBound ?? targetSuffix.endIndex
        let target = String(targetSuffix[..<targetEnd])

        #expect(target.contains(#""AgentStudioIPCClientCore""#))
        #expect(!target.contains(#""AgentStudio""#))
        #expect(!target.contains(#""AgentStudioAppIPC""#))
    }
}

#if canImport(Darwin)
    private func waitForProcessExit(
        processIdentifier: pid_t,
        timeout: DispatchTimeInterval = .seconds(10)
    ) -> Int32? {
        let semaphore = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeProcessSource(
            identifier: processIdentifier,
            eventMask: .exit,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler {
            semaphore.signal()
        }
        source.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        source.cancel()

        var status: Int32 = 0
        if waitResult == .timedOut {
            _ = kill(processIdentifier, SIGKILL)
            _ = waitpid(processIdentifier, &status, 0)
            return nil
        }

        let waited = waitpid(processIdentifier, &status, 0)
        return waited == processIdentifier ? status : nil
    }
#endif

private final class RecordingPaneAgentBootstrapProvider: PaneAgentBootstrapProviding {
    let bootstrap: AgentStudioIPCPaneBootstrap
    var requestedPaneId: String?
    var cancelledBootstrap: AgentStudioIPCPaneBootstrap?

    init(bootstrap: AgentStudioIPCPaneBootstrap) {
        self.bootstrap = bootstrap
    }

    func makePaneBootstrap(
        boundPaneId: String,
        boundWorkspaceId: UUID?,
        approvalAuthority: IPCApprovalAuthority
    ) throws -> AgentStudioIPCPaneBootstrap {
        requestedPaneId = boundPaneId
        return bootstrap
    }

    func cancelPaneBootstrap(_ bootstrap: AgentStudioIPCPaneBootstrap) {
        cancelledBootstrap = bootstrap
    }
}

private final class RecordingPaneAgentProcessSpawner: PaneAgentProcessSpawning, @unchecked Sendable {
    let result: PaneAgentProcessHandle?
    let error: Error?
    var request: PaneAgentSpawnRequest?

    init(result: PaneAgentProcessHandle) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func spawn(_ request: PaneAgentSpawnRequest) throws -> PaneAgentProcessHandle {
        self.request = request
        if let error {
            throw error
        }
        return try #require(result)
    }
}

private func makeBootstrap(socketPath: String, runtimeId: UUID) throws -> AgentStudioIPCPaneBootstrap {
    #if canImport(Darwin)
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else {
            throw PaneAgentLaunchError.pipeFailed(errnoCode: errno)
        }
        let readFileDescriptor = fds[0]
        let writeFileDescriptor = fds[1]
        _ = "secret-token\n".withCString { pointer in
            Darwin.write(writeFileDescriptor, pointer, strlen(pointer))
        }
        _ = Darwin.close(writeFileDescriptor)
        return AgentStudioIPCPaneBootstrap(
            descriptor: AgentStudioIPCPaneBootstrapDescriptor(
                environment: AgentStudioIPCSpawnEnvironment(
                    socketPath: socketPath,
                    runtimeId: runtimeId,
                    bootstrapFileDescriptor: readFileDescriptor
                ),
                tokenReadFileDescriptor: readFileDescriptor
            ),
            writeFileDescriptor: -1
        )
    #else
        throw PaneAgentLaunchError.unsupportedPlatform
    #endif
}

private struct PaneAgentLiveServerFixture {
    let runtimeId = UUID()
    let boundPaneId = UUID()
    let rootURL: URL
    let paths: AgentStudioIPCPaths
    let server: AgentStudioAppIPCServer

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp/as-pane-agent-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        #if canImport(Darwin)
            _ = chmod(rootURL.path, 0o700)
        #endif
        paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootURL)
        let methodRegistry = try AppIPCMethodRegistry.phaseOne()
        let service = AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(
                runtimeId: runtimeId,
                accessMode: .agentStudioOnly,
                methodDefinitions: methodRegistry.definitions
            ),
            ports: AgentStudioAppIPCPorts(
                queryPort: PaneAgentTestQueryPort(runtimeId: runtimeId),
                layoutPort: PaneAgentTestLayoutPort(),
                runtimePort: PaneAgentTestRuntimePort(),
                bridgePort: PaneAgentTestBridgePort(),
                commandPort: PaneAgentTestCommandPort(),
                uiPresentationPort: PaneAgentTestUIPresentationPort(),
                sidebarPort: PaneAgentTestSidebarPort(),
                permissionApprovalPort: PaneAgentTestPermissionApprovalPort()
            )
        )
        server = AgentStudioAppIPCServer(service: service, paths: paths, channel: .debug)
    }

    func cleanup() {
        server.stop()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct PaneAgentTestQueryPort: AppIPCQueryPort {
    let runtimeId: UUID

    func systemIdentify() throws -> IPCSystemIdentifyResult {
        IPCSystemIdentifyResult(runtimeId: runtimeId, accessMode: .agentStudioOnly, appVersion: "test")
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        IPCSystemVersionResult(appVersion: "test")
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: [])
    }

    func listWindows() throws -> IPCWindowListResult {
        IPCWindowListResult(windows: [])
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        IPCWorkspaceListResult(workspaces: [])
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listPanes() throws -> IPCPaneListResult {
        IPCPaneListResult(panes: [])
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func snapshotPane(_: UUID) throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .targetNotFound)
    }
}

private struct PaneAgentTestLayoutPort: AppIPCLayoutPort {
    func focusPane(_: IPCHandle) throws -> IPCPaneFocusResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }

    func splitPane(_: IPCPaneSplitParams) throws -> IPCPaneSplitResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }

    func closePane(_: IPCPaneCloseParams) throws -> IPCPaneCloseResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }

    func addDrawerPane(_: IPCDrawerAddPaneParams) throws -> IPCDrawerAddPaneResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }

    func toggleDrawer(_: IPCDrawerToggleParams) throws -> IPCDrawerToggleResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }
}

private struct PaneAgentTestRuntimePort: AppIPCRuntimePort {
    func terminalStatus(_: IPCHandle) throws -> IPCTerminalStatusResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func terminalSnapshot(_: IPCHandle) throws -> IPCTerminalSnapshotResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func sendTerminalInput(to _: IPCHandle, input _: String, correlationId _: UUID?) async throws
        -> IPCTerminalSendInputResult
    {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func waitForTerminal(
        _: IPCHandle,
        condition _: IPCTerminalWaitCondition,
        timeout _: Duration,
        afterSequence _: UInt64?
    ) async throws -> IPCTerminalWaitResult {
        throw AppIPCRuntimeError(reason: .timeout)
    }
}

private struct PaneAgentTestCommandPort: AppIPCCommandPort {
    func listCommands() throws -> IPCCommandListResult {
        IPCCommandListResult(commands: [])
    }

    func requiredPermissionScopes(for command: IPCCommandListEntry) throws -> [IPCPermissionScope] {
        command.requiredPrivileges.map { privilege in
            IPCPermissionScope(
                privilege: privilege,
                target: .app,
                dataScope: PermissionScopeCanonicalizer.dataScope(for: privilege)
            )
        }
    }

    func executeCommand(_: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        throw AppIPCCommandError(reason: .unsupportedCommand)
    }
}

private struct PaneAgentTestBridgePort: AppIPCBridgePort {
    func openReview(_: IPCBridgeReviewOpenParams) throws -> IPCBridgeReviewOpenResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func openFileView(_: IPCBridgeFileViewOpenParams) throws -> IPCBridgeFileViewOpenResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func refreshReview(_: IPCBridgeReviewRefreshParams) async throws -> IPCBridgeReviewRefreshResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func getPackage(_: IPCHandle) throws -> IPCBridgeReviewPackageResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func renderState(_: IPCHandle) async throws -> IPCBridgeRenderStateResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func selectFile(_: IPCBridgeReviewSelectFileParams) async throws -> IPCBridgeReviewSelectFileResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func scrollToFile(_: IPCBridgeDiffScrollToFileParams) async throws -> IPCBridgePageControlResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func expandFile(_: IPCBridgeDiffExpandFileParams) async throws -> IPCBridgePageControlResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func collapseFile(_: IPCBridgeDiffCollapseFileParams) async throws -> IPCBridgePageControlResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func searchFileTree(_: IPCBridgeFileTreeSearchParams) async throws -> IPCBridgePageControlResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func setFileTreeFilter(_: IPCBridgeFileTreeSetFilterParams) async throws -> IPCBridgePageControlResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func revealFileTreePath(_: IPCBridgeFileTreeRevealPathParams) async throws -> IPCBridgePageControlResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func showMarkdownPreview(_: IPCBridgeFileViewShowMarkdownPreviewParams) async throws
        -> IPCBridgePageControlResult
    {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func getContent(_: IPCBridgeContentGetParams) async throws -> IPCBridgeContentGetResult {
        throw AppIPCBridgeError(reason: .contentUnavailable)
    }

    func telemetrySnapshot(_: IPCHandle) async throws -> IPCBridgeTelemetrySnapshotResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }

    func flushTelemetry(_: IPCHandle) async throws -> IPCBridgeTelemetryFlushResult {
        throw AppIPCBridgeError(reason: .targetNotFound)
    }
}

private struct PaneAgentTestUIPresentationPort: AppIPCUIPresentationPort {
    func openCommandBar(_: IPCCommandBarOpenParams) throws -> IPCCommandBarOpenResult {
        throw AppIPCUIPresentationError(reason: .noActiveWindow)
    }
}

private struct PaneAgentTestSidebarPort: AppIPCSidebarPort {
    func getGrouping(_ params: IPCSidebarGroupingGetParams) throws -> IPCSidebarGroupingResult {
        IPCSidebarGroupingResult(surface: params.surface, mode: .repo)
    }

    func getSurface(_: IPCSidebarSurfaceGetParams) throws -> IPCSidebarSurfaceResult {
        IPCSidebarSurfaceResult(surface: .repo)
    }
}

private struct PaneAgentTestPermissionApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}

private func findBuiltPaneAgentHelper() throws -> URL {
    let fileManager = FileManager.default
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath), isDirectory: true)
    var candidateDirectories: [URL] = []
    if let swiftBuildDir = ProcessInfo.processInfo.environment["SWIFT_BUILD_DIR"], !swiftBuildDir.isEmpty {
        return try findPaneAgentHelper(
            in: debugDirectories(under: URL(fileURLWithPath: swiftBuildDir, isDirectory: true))
        )
    }
    if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
        var cursor = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        for _ in 0..<8 {
            candidateDirectories.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
    }
    if let entries = try? fileManager.contentsOfDirectory(atPath: projectRoot.path) {
        candidateDirectories.append(
            contentsOf:
                entries
                .filter { $0.hasPrefix(".build") }
                .flatMap { debugDirectories(under: projectRoot.appending(path: $0, directoryHint: .isDirectory)) }
        )
    }

    return try findPaneAgentHelper(in: candidateDirectories)
}

private func findPaneAgentHelper(in candidateDirectories: [URL]) throws -> URL {
    let fileManager = FileManager.default
    var seen: Set<String> = []
    for directory in candidateDirectories where seen.insert(directory.path).inserted {
        let candidate = directory.appending(path: "agentstudio-pane-agent")
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    throw PaneAgentLaunchError.spawnFailed(errnoCode: ENOENT)
}

private func debugDirectories(under rootURL: URL) -> [URL] {
    let fileManager = FileManager.default
    var directories: [URL] = [
        rootURL.appending(path: "debug", directoryHint: .isDirectory)
    ]
    guard
        let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else {
        return directories
    }
    directories.append(
        contentsOf:
            entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map { $0.appending(path: "debug", directoryHint: .isDirectory) }
    )
    return directories
}
