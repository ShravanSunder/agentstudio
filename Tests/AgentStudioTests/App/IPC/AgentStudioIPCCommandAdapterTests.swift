import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("AgentStudio IPC command adapter", .serialized)
struct AgentStudioIPCCommandAdapterTests {
    @Test("catalog exposes exactly the current 15 typed headless commands")
    func catalogContainsCurrentHeadlessCommandsOnly() throws {
        let harness = CommandAdapterHarness()
        let catalog = try harness.adapter.listCommands()
        let ids = Set(catalog.commands.map(\.id.rawValue))

        #expect(catalog.compatibility == .current)
        #expect(catalog.commands.count == 15)
        #expect(ids.contains(AppCommand.zoomPane.rawValue))
        #expect(ids.contains(AppCommand.reloadBridgeWebView.rawValue))
        #expect(ids.contains(AppCommand.showReposSidebar.rawValue))
        #expect(ids.contains(AppCommand.pinRepo.rawValue))
        #expect(!ids.contains(AppCommand.closePane.rawValue))
        #expect(!ids.contains(AppCommand.showInboxNotifications.rawValue))
        for command in retiredPanesOrganizationCommands {
            #expect(!ids.contains(command.rawValue))
        }

        let reload = try #require(
            catalog.commands.first { $0.id.rawValue == AppCommand.reloadBridgeWebView.rawValue }
        )
        #expect(reload.argumentVariants == [.pane])
        #expect(reload.resultVariants == [.accepted])
        #expect(reload.requiredPrivileges == [.appCommandExecute, .workspaceRead])
    }

    @Test("retired Panes organization commands remain unavailable without reaching an owner")
    func retiredPanesOrganizationCommandsRemainUnavailable() async throws {
        let shell = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(shellCommandHandler: shell)

        for command in retiredPanesOrganizationCommands {
            #expect(command.ipcSpec.exposure == .debugTesting)
            #expect(command.ipcSpec.resultVariants == [.unavailable])
            do {
                _ = try await harness.adapter.executeCommand(
                    IPCCommandExecutionRequest(
                        commandId: .init(rawValue: command.rawValue),
                        correlationId: UUIDv7.generate(),
                        arguments: .workspaceWindow(.init(workspaceWindowId: harness.windowId))
                    )
                )
                Issue.record("Retired Panes organization command unexpectedly executed")
            } catch let error as AppIPCCommandError {
                #expect(error.reason == .unsupportedCommand)
            }
        }
        #expect(shell.handledRequests.isEmpty)
    }

    @Test("explicit window sidebar command reaches its existing shell owner")
    func sidebarCommandUsesExplicitWindow() async throws {
        let shell = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(shellCommandHandler: shell)
        let request = IPCCommandExecutionRequest(
            commandId: .init(rawValue: AppCommand.showReposSidebar.rawValue),
            correlationId: UUIDv7.generate(),
            arguments: .workspaceWindow(.init(workspaceWindowId: harness.windowId))
        )

        let result = try await harness.adapter.executeCommand(request)

        #expect(result.variant == .applied)
        #expect(result.correlationId == request.correlationId)
        #expect(shell.handledRequests.map(\.command) == [.showReposSidebar])
    }

    @Test("pane alias is canonicalized before targeted execution")
    func paneAliasCanonicalizesBeforeExecution() async throws {
        let harness = CommandAdapterHarness()
        let pane = harness.workspaceStore.createPane(title: "Target")
        harness.workspaceStore.appendTab(Tab(paneId: pane.id))
        let request = IPCCommandExecutionRequest(
            commandId: .init(rawValue: AppCommand.zoomPane.rawValue),
            correlationId: UUIDv7.generate(),
            arguments: .pane(
                .init(
                    workspaceWindowId: harness.windowId,
                    paneSelector: try .init(rawValue: "self")
                )
            )
        )
        let tools = AppIPCTargetResolutionTools { _ in
            IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id))
        }

        let prepared = try await harness.adapter.prepareCommand(
            request,
            principal: testPrincipal(),
            tools: tools
        )

        guard case .pane(let arguments) = prepared.request.arguments else {
            Issue.record("Expected canonical pane arguments")
            return
        }
        #expect(arguments.paneSelector.rawValue == pane.id.uuidString)
        #expect(prepared.canonicalHandle == IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id)))
        #expect(prepared.target == .pane(pane.id.uuidString))
        #expect(prepared.requiredScopes.map(\.privilege) == [.layoutMutate])
    }

    @Test("targeted execution awaits the dispatcher owner outcome")
    func targetedExecutionAwaitsOwner() async throws {
        let harness = CommandAdapterHarness()
        let pane = harness.workspaceStore.createPane(title: "Target")
        harness.workspaceStore.appendTab(Tab(paneId: pane.id))
        let owner = RecordingWorkspaceCommandHandler()
        let request = IPCCommandExecutionRequest(
            commandId: .init(rawValue: AppCommand.zoomPane.rawValue),
            correlationId: UUIDv7.generate(),
            arguments: .pane(
                .init(
                    workspaceWindowId: harness.windowId,
                    paneSelector: try .init(rawValue: pane.id.uuidString)
                )
            )
        )

        let result = try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = owner
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                try await harness.adapter.executeCommand(request)
            }
        )

        #expect(result.variant == .applied)
        #expect(owner.awaitedCommands == [.zoomPane])
    }

    @Test("registered historical window is rejected when the App owner has been replaced")
    func registeredHistoricalWindowDoesNotReachCurrentShellOwner() async throws {
        let historicalWindowId = UUIDv7.generate()
        let currentWindowId = UUIDv7.generate()
        let historicalLifecycle = WorkspaceWindowLifecycleSnapshot(
            registeredWindowIds: [historicalWindowId, currentWindowId],
            keyWindowId: currentWindowId,
            focusedWindowId: currentWindowId,
            preferredWorkspaceWindowId: currentWindowId
        )
        let shell = RecordingShellCommandHandler(currentWindowId: currentWindowId)
        let harness = CommandAdapterHarness(
            windowId: currentWindowId,
            shellCommandHandler: shell
        )
        let request = IPCCommandExecutionRequest(
            commandId: .init(rawValue: AppCommand.showReposSidebar.rawValue),
            correlationId: UUIDv7.generate(),
            arguments: .workspaceWindow(.init(workspaceWindowId: historicalWindowId))
        )

        #expect(historicalLifecycle.registeredWindowIds.contains(historicalWindowId))
        await #expect(throws: AppIPCCommandError.self) {
            try await harness.adapter.executeCommand(request)
        }
        #expect(shell.handledRequests.isEmpty)
    }

    @Test("prepared command is rejected when the sole App window is replaced before execution")
    func preparedCommandRechecksCurrentWindowOwnerBeforeExecution() async throws {
        let firstWindowId = UUIDv7.generate()
        let replacementWindowId = UUIDv7.generate()
        let shell = RecordingShellCommandHandler(currentWindowId: firstWindowId)
        let harness = CommandAdapterHarness(
            windowId: firstWindowId,
            shellCommandHandler: shell
        )
        let request = IPCCommandExecutionRequest(
            commandId: .init(rawValue: AppCommand.showReposSidebar.rawValue),
            correlationId: UUIDv7.generate(),
            arguments: .workspaceWindow(.init(workspaceWindowId: firstWindowId))
        )
        let prepared = try await harness.adapter.prepareCommand(
            request,
            principal: testPrincipal(),
            tools: AppIPCTargetResolutionTools { _ in
                throw AppIPCCommandError(reason: .validationRejected)
            }
        )

        shell.currentWindowId = replacementWindowId

        await #expect(throws: AppIPCCommandError.self) {
            try await harness.adapter.executeCommand(prepared.request)
        }
        #expect(shell.handledRequests.isEmpty)
    }

    @Test("targeted command rejects a dispatcher handler owned by another window")
    func targetedCommandRequiresMatchingDispatcherOwner() async throws {
        let requestedWindowId = UUIDv7.generate()
        let harness = CommandAdapterHarness(windowId: requestedWindowId)
        let pane = harness.workspaceStore.createPane(title: "Target")
        harness.workspaceStore.appendTab(Tab(paneId: pane.id))
        let wrongWindowOwner = RecordingWorkspaceCommandHandler(currentWindowId: UUIDv7.generate())
        let request = IPCCommandExecutionRequest(
            commandId: .init(rawValue: AppCommand.zoomPane.rawValue),
            correlationId: UUIDv7.generate(),
            arguments: .pane(
                .init(
                    workspaceWindowId: requestedWindowId,
                    paneSelector: try .init(rawValue: pane.id.uuidString)
                )
            )
        )

        await #expect(throws: AppIPCCommandError.self) {
            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = wrongWindowOwner
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    try await harness.adapter.executeCommand(request)
                }
            )
        }
        #expect(wrongWindowOwner.awaitedCommands.isEmpty)
    }

    @Test("default headless IPC execution fails closed without invoking a void owner")
    func defaultHeadlessIPCExecutionFailsClosed() async {
        let owner = DefaultWorkspaceCommandHandler()

        let applied = await owner.executeHeadlessIPC(
            .zoomPane,
            target: UUIDv7.generate(),
            targetType: .pane
        )

        #expect(!applied)
        #expect(owner.executedCommands.isEmpty)
    }

    @Test("complete actual capabilities catalog fits the existing one MiB NDJSON frame")
    func completeActualCapabilitiesCatalogFitsExistingFrame() throws {
        let adapter = CommandAdapterHarness().adapter
        let commandCatalog = try adapter.listCommands()
        let commandComposition = try IPCCommandMethodComposition(
            compatibility: .current,
            commands: commandCatalog.commands
        )
        let builtIns = try IPCBuiltInMethodCatalog(
            inputs: IPCBuiltInMethodCatalogInputs(
                terminalWaitMaximumSeconds: AppPolicies.IPC.maximumTerminalWaitSeconds,
                relationships: IPCBuiltInMethodRelationshipInputs(
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
        let commandDescriptors = try [
            IPCAnyMethodDescriptor(erasing: commandComposition.list),
            IPCAnyMethodDescriptor(erasing: commandComposition.execute),
        ]
        let availableDescriptors = builtIns.erasedDescriptors + commandDescriptors
        let ping = try #require(
            builtIns.erasedDescriptors.first { $0.metadata.name == "system.ping" }
        )
        let capabilities = try IPCSystemCapabilitiesDescriptorFactory.compose(
            compatibility: .current,
            availableDescriptors: availableDescriptors,
            illustrativeDescriptor: ping
        )

        #expect(builtIns.erasedDescriptors.count == 47)
        #expect(commandCatalog.commands.count == 15)
        #expect(capabilities.result.methods.count == 50)

        let encodedCatalog = try capabilities.descriptor.encodeResult(capabilities.result)
        let decodedCatalog = try IPCMethodCatalogDecoder.decode(encodedCatalog)
        #expect(decodedCatalog == capabilities.result)

        let response = JSONRPCResponse.success(
            id: .number(1),
            result: try JSONRPCCodec.encodeJSONValue(capabilities.result)
        )
        let responsePayload = try JSONRPCCodec.encodeResponse(response)
        let frameByteLimit = 1_048_576
        let frameByteCount = responsePayload.utf8.count + 1
        #expect(
            frameByteCount <= frameByteLimit,
            "Complete 43 built-in + 15 command capabilities frame is \(frameByteCount) bytes"
        )
        let frame = try NDJSONFrameEncoder.encode(
            responsePayload,
            maxFrameBytes: frameByteLimit
        )
        #expect(frame.count == frameByteCount)

        var decoder = NDJSONFrameDecoder(maxFrameBytes: frameByteLimit)
        let decodedFrames = try decoder.append(frame)
        #expect(decodedFrames.count == 1)
        let decodedPayload = try #require(decodedFrames.first)
        let decodedResponse = try JSONRPCCodec.decodeResponse(decodedPayload)
        let decodedResult = try #require(decodedResponse.result)
        let strictRoundTrip = try IPCMethodCatalogDecoder.decode(
            JSONEncoder().encode(decodedResult)
        )
        #expect(strictRoundTrip == capabilities.result)
    }
}

let retiredPanesOrganizationCommands: [AppCommand] = [
    .setPanesGroupingRepo,
    .setPanesGroupingTab,
    .setPanesGroupingActivity,
    .setPanesSubgroupNone,
    .setPanesSubgroupActivity,
    .setPanesSortFieldName,
    .setPanesSortFieldActivity,
    .togglePanesSortDirection,
]

@MainActor
func makeIPCCommandAdapterForPresentationIsolationTests() -> AgentStudioIPCCommandAdapter {
    CommandAdapterHarness().adapter
}

@MainActor
private struct CommandAdapterHarness {
    let adapter: AgentStudioIPCCommandAdapter
    let workspaceStore: WorkspaceStore
    let windowId: UUID
    let shellCommandHandler: RecordingShellCommandHandler

    init(
        windowId: UUID = UUIDv7.generate(),
        shellCommandHandler: RecordingShellCommandHandler = RecordingShellCommandHandler()
    ) {
        workspaceStore = WorkspaceStore()
        self.windowId = windowId
        self.shellCommandHandler = shellCommandHandler
        if shellCommandHandler.currentWindowId == nil {
            shellCommandHandler.currentWindowId = windowId
        }
        adapter = AgentStudioIPCCommandAdapter(
            workspaceId: workspaceStore.identityAtom.workspaceId,
            targetAuthorizer: WorkspaceDurableTargetAuthorizationPort(workspaceStore: workspaceStore),
            shellCommandHandler: shellCommandHandler
        )
    }
}

@MainActor
private final class RecordingShellCommandHandler: ShellCommandHandling {
    var handledRequests: [AppCommandExecutionRequest] = []
    var currentWindowId: UUID?

    init(currentWindowId: UUID? = nil) {
        self.currentWindowId = currentWindowId
    }

    func ownsWorkspaceWindow(_ workspaceWindowId: UUID) -> Bool {
        currentWindowId == workspaceWindowId
    }

    func canExecute(_: AppCommand) -> Bool { true }
    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { true }
    func execute(_: AppCommand) -> Bool { false }
    func execute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        handledRequests.append(request)
        return .applied
    }

    func showRepoCommandBar() {}
    func refreshWorktrees() {}
    func refocusActivePane() {}
}

@MainActor
private final class RecordingWorkspaceCommandHandler: WorkspaceCommandHandling {
    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabInsertionIndex _: Int?) {}
    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}

    var awaitedCommands: [AppCommand] = []
    let currentWindowId: UUID?

    init(currentWindowId: UUID? = nil) {
        self.currentWindowId = currentWindowId
    }

    func ownsWorkspaceWindow(_ workspaceWindowId: UUID) -> Bool {
        currentWindowId == nil || currentWindowId == workspaceWindowId
    }

    func execute(_: AppCommand) {}
    func execute(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canExecute(_: AppCommand) -> Bool { false }
    func canExecute(_: AppCommand, target _: UUID, targetType: SearchItemType) -> Bool {
        targetType == .pane
    }

    func executeHeadlessIPC(
        _ command: AppCommand,
        target _: UUID,
        targetType _: SearchItemType
    ) async -> Bool {
        awaitedCommands.append(command)
        return true
    }
}

@MainActor
private final class DefaultWorkspaceCommandHandler: WorkspaceCommandHandling {
    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabInsertionIndex _: Int?) {}
    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}

    var executedCommands: [AppCommand] = []

    func execute(_ command: AppCommand) {
        executedCommands.append(command)
    }

    func execute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) {
        executedCommands.append(command)
    }

    func canExecute(_: AppCommand) -> Bool { true }
    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { true }
}

private func testPrincipal() -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUIDv7.generate(),
        runtimeId: UUIDv7.generate(),
        accessMode: .unsafeDebug,
        kind: .unsafeDebugClient,
        approvalAuthority: .noApprovalAuthority
    )
}

@MainActor
private struct FakeCommandWorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading {
    let snapshotValue: WorkspaceWindowLifecycleSnapshot
    func snapshot() -> WorkspaceWindowLifecycleSnapshot { snapshotValue }
}
