import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC command adapter")
struct AgentStudioIPCCommandAdapterTests {
    @Test("lists app command specs through IPC command contracts")
    func listsAppCommandSpecsThroughIPCCommandContracts() throws {
        let harness = CommandAdapterHarness()

        let result = try harness.adapter.listCommands()
        let commandsById = Dictionary(uniqueKeysWithValues: result.commands.map { ($0.id, $0) })

        #expect(result.commands.count == AppCommand.allCases.count)

        let commandBar = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.showCommandBarEverything.rawValue)])
        #expect(commandBar.title == AppCommand.showCommandBarEverything.definition.label)
        #expect(commandBar.executionModes == [.uiPresentation])
        #expect(commandBar.targetKinds.isEmpty)
        #expect(commandBar.requiredPrivileges == [.uiPresent])

        let closePane = try #require(commandsById[IPCCommandIdentifier(rawValue: AppCommand.closePane.rawValue)])
        #expect(closePane.title == AppCommand.closePane.definition.label)
        #expect(closePane.executionModes == [.requiresInteractiveInput])
        #expect(closePane.targetKinds == [.pane])
        #expect(closePane.requiredPrivileges == [.layoutMutate])

        let copyCurrentPanePath = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.copyCurrentPanePath.rawValue)])
        #expect(copyCurrentPanePath.executionModes == [.requiresInteractiveInput])
        #expect(copyCurrentPanePath.targetKinds == [.pane])
        #expect(copyCurrentPanePath.requiredPrivileges == [.workspaceRead])

        let repoVisibility = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue)])
        #expect(repoVisibility.executionModes == [.headless])
        #expect(repoVisibility.targetKinds.isEmpty)
        #expect(repoVisibility.requiredPrivileges == [.sidebarStateMutate])
        #expect(
            repoVisibility.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: ["all", "favoritesOnly"]),
                    isRequired: true
                )
            ])

        let repoSortOrder = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarSortOrder.rawValue)])
        #expect(repoSortOrder.executionModes == [.headless])
        #expect(repoSortOrder.targetKinds.isEmpty)
        #expect(repoSortOrder.requiredPrivileges == [.sidebarStateMutate])
        #expect(
            repoSortOrder.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "order",
                    kind: .stringEnum(values: ["ascending", "descending"]),
                    isRequired: true
                )
            ])

        let addRepoFavorite = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.addRepoFavorite.rawValue)])
        #expect(addRepoFavorite.executionModes == [.headless])
        #expect(addRepoFavorite.targetKinds == [.repo])
        #expect(addRepoFavorite.requiredPrivileges == [.sidebarStateMutate])

        let removeRepoFavorite = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.removeRepoFavorite.rawValue)])
        #expect(removeRepoFavorite.executionModes == [.headless])
        #expect(removeRepoFavorite.targetKinds == [.repo])
        #expect(removeRepoFavorite.requiredPrivileges == [.sidebarStateMutate])
    }

    @Test("command list entries are full-catalog IPC projections")
    func commandListEntriesAreFullCatalogIPCProjections() throws {
        let harness = CommandAdapterHarness()

        let result = try harness.adapter.listCommands()
        let commandsById = Dictionary(uniqueKeysWithValues: result.commands.map { ($0.id, $0) })

        for command in AppCommand.allCases {
            let definition = command.definition
            let entry = try #require(commandsById[IPCCommandIdentifier(rawValue: command.rawValue)])

            #expect(entry == definition.ipcCommandListEntry)
            #expect(entry.title == definition.label)
        }
    }

    @Test("sidebar command mutation permissions resolve to current workspace")
    func sidebarCommandMutationPermissionsResolveToCurrentWorkspace() throws {
        let harness = CommandAdapterHarness()
        let command = AppCommand.setRepoSidebarVisibilityMode.definition.ipcCommandListEntry

        let scopes = try harness.adapter.requiredPermissionScopes(for: command)

        #expect(
            scopes == [
                IPCPermissionScope(
                    privilege: .sidebarStateMutate,
                    target: .workspace(harness.workspaceStore.identityAtom.workspaceId),
                    dataScope: .sidebarState
                )
            ])
    }

    @Test("public IPC command contracts do not expose tooltip vocabulary")
    func publicIPCCommandContractsDoNotExposeTooltipVocabulary() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("ControlTooltip"))
        #expect(!source.contains("tooltip"))
        #expect(!source.contains("toolTip"))
    }

    @Test("encoded command list entries expose only IPC contract keys")
    func encodedCommandListEntriesExposeOnlyIPCContractKeys() throws {
        let harness = CommandAdapterHarness()
        let result = try harness.adapter.listCommands()
        let encodedData = try JSONEncoder().encode(result)
        let decodedObject = try #require(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        let encodedCommands = try #require(decodedObject["commands"] as? [[String: Any]])
        let expectedEntryKeys = Set([
            "id",
            "title",
            "executionModes",
            "targetKinds",
            "requiredPrivileges",
            "argumentSchema",
        ])

        #expect(!encodedCommands.isEmpty)
        for encodedCommand in encodedCommands {
            #expect(Set(encodedCommand.keys) == expectedEntryKeys)
        }
    }

    @Test("rejects ui-presentation command specs before workspace window checks")
    func rejectsUIPresentationCommandSpecsBeforeWorkspaceWindowChecks() throws {
        let harness = CommandAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.showCommandBarEverything.rawValue),
                    targetHandle: nil
                )
            )
            Issue.record("command bar command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresPresentation)
        }
    }

    @Test("executes repo sidebar visibility command through injected shell owner")
    func executesRepoSidebarVisibilityCommandThroughInjectedShellOwner() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(shellCommandHandler: shellCommandHandler)

        let favoritesOnly = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue),
                targetHandle: nil,
                arguments: ["mode": "favoritesOnly"]
            )
        )
        let all = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue),
                targetHandle: nil,
                arguments: ["mode": "all"]
            )
        )

        #expect(favoritesOnly.applied)
        #expect(all.applied)
        #expect(
            shellCommandHandler.handledRequests == [
                AppCommandExecutionRequest(
                    command: .setRepoSidebarVisibilityMode,
                    arguments: .repoSidebarVisibilityMode(.favoritesOnly),
                    executionContext: .headlessIPC
                ),
                AppCommandExecutionRequest(
                    command: .setRepoSidebarVisibilityMode,
                    arguments: .repoSidebarVisibilityMode(.all),
                    executionContext: .headlessIPC
                ),
            ])
    }

    @Test("executes repo sidebar sort order command through injected shell owner")
    func executesRepoSidebarSortOrderCommandThroughInjectedShellOwner() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(shellCommandHandler: shellCommandHandler)

        let descending = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarSortOrder.rawValue),
                targetHandle: nil,
                arguments: ["order": "descending"]
            )
        )
        let ascending = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarSortOrder.rawValue),
                targetHandle: nil,
                arguments: ["order": "ascending"]
            )
        )

        #expect(descending.applied)
        #expect(ascending.applied)
        #expect(
            shellCommandHandler.handledRequests == [
                AppCommandExecutionRequest(
                    command: .setRepoSidebarSortOrder,
                    arguments: .repoSidebarSortOrder(.descending),
                    executionContext: .headlessIPC
                ),
                AppCommandExecutionRequest(
                    command: .setRepoSidebarSortOrder,
                    arguments: .repoSidebarSortOrder(.ascending),
                    executionContext: .headlessIPC
                ),
            ])
    }

    @Test("executes typed inbox filter commands through injected shell owner")
    func executesTypedInboxFilterCommandsThroughInjectedShellOwner() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(shellCommandHandler: shellCommandHandler)

        let rowFilter = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: AppCommand.setInboxRowStateFilter.rawValue),
                targetHandle: nil,
                arguments: ["filter": "all"]
            )
        )
        let contentMode = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(
                commandId: IPCCommandIdentifier(rawValue: AppCommand.setInboxContentMode.rawValue),
                targetHandle: nil,
                arguments: ["mode": "activity"]
            )
        )

        #expect(rowFilter.applied)
        #expect(contentMode.applied)
        #expect(
            shellCommandHandler.handledRequests == [
                AppCommandExecutionRequest(
                    command: .setInboxRowStateFilter,
                    arguments: .inboxRowStateFilter(.all),
                    executionContext: .headlessIPC
                ),
                AppCommandExecutionRequest(
                    command: .setInboxContentMode,
                    arguments: .inboxContentMode(.activity),
                    executionContext: .headlessIPC
                ),
            ])
    }

    @Test("rejects invalid repo visibility mode before active window lookup")
    func rejectsInvalidRepoVisibilityModeBeforeActiveWindowLookup() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(
            windowSnapshot: .empty,
            shellCommandHandler: shellCommandHandler
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue),
                    targetHandle: nil,
                    arguments: ["mode": "recent"]
                )
            )
            Issue.record("invalid repo visibility mode unexpectedly executed")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .validationRejected)
        }
        #expect(shellCommandHandler.handledRequests.isEmpty)
    }

    @Test("rejects invalid repo sort order before active window lookup")
    func rejectsInvalidRepoSortOrderBeforeActiveWindowLookup() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(
            windowSnapshot: .empty,
            shellCommandHandler: shellCommandHandler
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarSortOrder.rawValue),
                    targetHandle: nil,
                    arguments: ["order": "currentRepoOrder"]
                )
            )
            Issue.record("invalid repo sort order unexpectedly executed")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .validationRejected)
        }
        #expect(shellCommandHandler.handledRequests.isEmpty)
    }

    @Test("rejects wrong typed repo visibility arguments before active window lookup")
    func rejectsWrongTypedRepoVisibilityArgumentsBeforeActiveWindowLookup() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(
            windowSnapshot: .empty,
            shellCommandHandler: shellCommandHandler
        )
        let paramsData = try JSONSerialization.data(withJSONObject: [
            "commandId": AppCommand.setRepoSidebarVisibilityMode.rawValue,
            "targetHandle": NSNull(),
            "arguments": ["mode": 42],
        ])
        let params = try JSONDecoder().decode(IPCCommandExecuteParams.self, from: paramsData)

        do {
            _ = try harness.adapter.executeCommand(params)
            Issue.record("wrong typed repo visibility mode unexpectedly executed")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .validationRejected)
        }
        #expect(shellCommandHandler.handledRequests.isEmpty)
    }

    @Test("rejects missing repo visibility mode before active window lookup")
    func rejectsMissingRepoVisibilityModeBeforeActiveWindowLookup() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(
            windowSnapshot: .empty,
            shellCommandHandler: shellCommandHandler
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue),
                    targetHandle: nil,
                    arguments: [:]
                )
            )
            Issue.record("missing repo visibility mode unexpectedly executed")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .validationRejected)
        }
        #expect(shellCommandHandler.handledRequests.isEmpty)
    }

    @Test("valid repo visibility command without active window returns no active window")
    func validRepoVisibilityCommandWithoutActiveWindowReturnsNoActiveWindow() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(
            windowSnapshot: .empty,
            shellCommandHandler: shellCommandHandler
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue),
                    targetHandle: nil,
                    arguments: ["mode": "favoritesOnly"]
                )
            )
            Issue.record("repo visibility command unexpectedly executed without an active window")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .noActiveWindow)
        }
        #expect(shellCommandHandler.handledRequests.isEmpty)
    }

    @Test("shell owner state unavailable maps to command state unavailable")
    func shellOwnerStateUnavailableMapsToCommandStateUnavailable() throws {
        let shellCommandHandler = RecordingShellCommandHandler(outcome: .stateUnavailable)
        let harness = CommandAdapterHarness(shellCommandHandler: shellCommandHandler)

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.setRepoSidebarVisibilityMode.rawValue),
                    targetHandle: nil,
                    arguments: ["mode": "favoritesOnly"]
                )
            )
            Issue.record("state-unavailable shell owner unexpectedly reported success")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .stateUnavailable)
        }
        #expect(
            shellCommandHandler.handledRequests == [
                AppCommandExecutionRequest(
                    command: .setRepoSidebarVisibilityMode,
                    arguments: .repoSidebarVisibilityMode(.favoritesOnly),
                    executionContext: .headlessIPC
                )
            ])
    }

    @Test("rejects command bar specs because they require explicit UI presentation")
    func rejectsCommandBarSpecsBecauseTheyRequireExplicitUIPresentation() throws {
        let windowId = UUID()
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(windowId)
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.showCommandBarEverything.rawValue),
                    targetHandle: nil
                )
            )
            Issue.record("command bar command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresPresentation)
        }
    }

    @Test("rejects interactive command specs without misclassifying them as UI presentation")
    func rejectsInteractiveCommandSpecsWithoutMisclassifyingThemAsUIPresentation() throws {
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID())
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.copyCurrentPanePath.rawValue),
                    targetHandle: nil
                )
            )
            Issue.record("interactive command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresParameters)
        }
    }

    @Test("unknown command ids return unsupported command after decoding")
    func unknownCommandIdsReturnUnsupportedCommandAfterDecoding() throws {
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID())
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(commandId: IPCCommandIdentifier(rawValue: "futureCommand"), targetHandle: nil)
            )
            Issue.record("unknown command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .unsupportedCommand)
        }
    }

    @Test("targeted repo commands execute through the shared app command dispatcher")
    func targetedRepoCommandsExecuteThroughSharedAppCommandDispatcher() async throws {
        let commandHandler = RecordingWorkspaceCommandHandler()
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID()),
            shellCommandHandler: shellCommandHandler
        )
        let repoId = harness.workspaceStore.repositoryTopologyAtom.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-ipc-owned-repo")
        ).id

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = commandHandler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                let result = try harness.adapter.executeCommand(
                    IPCCommandExecuteParams(
                        commandId: IPCCommandIdentifier(rawValue: AppCommand.addRepoFavorite.rawValue),
                        targetHandle: "repo:\(repoId.uuidString)"
                    )
                )

                #expect(result.applied)
                #expect(result.targetHandle == "repo:\(repoId.uuidString)")
                #expect(commandHandler.targetedCommands.count == 1)
                #expect(commandHandler.targetedCommands[0].command == .addRepoFavorite)
                #expect(commandHandler.targetedCommands[0].target == repoId)
                #expect(commandHandler.targetedCommands[0].targetType == .repo)
            }
        )
    }

    @Test("targeted repo commands reject repositories outside the authorized workspace")
    func targetedRepoCommandsRejectRepositoriesOutsideAuthorizedWorkspace() throws {
        let harness = CommandAdapterHarness()

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.addRepoFavorite.rawValue),
                    targetHandle: "repo:\(UUID().uuidString)"
                )
            )
            Issue.record("repo favorite unexpectedly accepted a repository outside the workspace")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .targetNotFound)
        }
    }

    @Test("targeted repo commands reject wrong handle kinds")
    func targetedRepoCommandsRejectWrongHandleKinds() throws {
        let shellCommandHandler = RecordingShellCommandHandler()
        let harness = CommandAdapterHarness(shellCommandHandler: shellCommandHandler)

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.addRepoFavorite.rawValue),
                    targetHandle: "pane:\(UUID().uuidString)"
                )
            )
            Issue.record("repo favorite unexpectedly accepted a pane target")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .targetNotFound)
        }
    }
}

@MainActor
private struct CommandAdapterHarness {
    let adapter: AgentStudioIPCCommandAdapter
    let workspaceStore: WorkspaceStore

    init(
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID()),
        shellCommandHandler: RecordingShellCommandHandler = RecordingShellCommandHandler()
    ) {
        workspaceStore = WorkspaceStore()
        adapter = AgentStudioIPCCommandAdapter(
            workspaceId: workspaceStore.identityAtom.workspaceId,
            repositoryTargetAuthorizer: WorkspaceRepositoryTargetAuthorizationPort(
                repositoryExists: { [repositoryTopology = workspaceStore.repositoryTopologyAtom] repositoryId in
                    repositoryTopology.repo(repositoryId) != nil
                }
            ),
            windowLifecycleReader: FakeCommandWorkspaceWindowLifecycleReader(snapshot: windowSnapshot),
            shellCommandHandler: shellCommandHandler
        )
    }
}

@MainActor
private final class RecordingShellCommandHandler: ShellCommandHandling {
    var handledRequests: [AppCommandExecutionRequest] = []
    let outcome: AppCommandExecutionOutcome

    init(outcome: AppCommandExecutionOutcome = .applied) {
        self.outcome = outcome
    }

    func canExecute(_: AppCommand) -> Bool {
        true
    }

    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        true
    }

    func execute(_: AppCommand) -> Bool {
        false
    }

    func execute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        false
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        handledRequests.append(request)
        return outcome
    }

    func showRepoCommandBar() {}

    func refreshWorktrees() {}

    func refocusActivePane() {}
}

@MainActor
private final class RecordingWorkspaceCommandHandler: WorkspaceCommandHandling {
    struct TargetedCommand: Equatable {
        let command: AppCommand
        let target: UUID
        let targetType: SearchItemType
    }

    var targetedCommands: [TargetedCommand] = []

    func execute(_: AppCommand) {}

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        targetedCommands.append(TargetedCommand(command: command, target: target, targetType: targetType))
    }

    func canExecute(_: AppCommand) -> Bool {
        false
    }

    func canExecute(_ command: AppCommand, target _: UUID, targetType: SearchItemType) -> Bool {
        targetType == .repo && (command == .addRepoFavorite || command == .removeRepoFavorite)
    }

    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabIndex _: Int?) {}

    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}

private struct FakeCommandWorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading {
    let snapshotValue: WorkspaceWindowLifecycleSnapshot

    init(snapshot: WorkspaceWindowLifecycleSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> WorkspaceWindowLifecycleSnapshot {
        snapshotValue
    }
}

extension WorkspaceWindowLifecycleSnapshot {
    fileprivate static var empty: Self {
        Self(
            registeredWindowIds: [],
            keyWindowId: nil,
            focusedWindowId: nil,
            preferredWorkspaceWindowId: nil
        )
    }

    fileprivate static func singleActiveWindow(_ windowId: UUID) -> Self {
        Self(
            registeredWindowIds: [windowId],
            keyWindowId: windowId,
            focusedWindowId: windowId,
            preferredWorkspaceWindowId: windowId
        )
    }
}
